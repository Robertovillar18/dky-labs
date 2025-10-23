# ==========================================
# platform-bootstrap.ps1  (infra compartida)
# - Crea/asegura RG y ACR únicos
# - Importa mysql:8 al ACR evitando TOOMANYREQUESTS
# - No maneja credenciales MySQL (eso va por cliente)
# Recomendado:
#   $env:DOCKERHUB_USER="usuario"
#   $env:DOCKERHUB_TOKEN="token"
# ==========================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# A) Cuenta
az account show -o table | Out-Host

# B) Variables
$ClienteNombre = "clientex"
$Location      = "westeurope"

$slug    = ($ClienteNombre.ToLower() -replace "[^a-z0-9-]", "-")
$rg      = "${slug}-rg"
$AcrName = "${slug}-acr"   # nombre estable para tu plataforma

# C) Providers (idempotente)
az provider register --namespace Microsoft.ContainerInstance -o none
az provider register --namespace Microsoft.Network            -o none
az provider register --namespace Microsoft.Storage           -o none

$providers = @("Microsoft.ContainerInstance","Microsoft.Network","Microsoft.Storage")
foreach ($p in $providers) {
  $deadline = (Get-Date).AddMinutes(2)
  do {
    $state = az provider show -n $p --query registrationState -o tsv 2>$null
    Write-Host "$p -> $state"
    if ($state -eq "Registered") { break }
    Start-Sleep -Seconds 5
  } while ((Get-Date) -lt $deadline)
}

# D) Resource Group (idempotente)
az group create -n $rg -l $Location -o table | Out-Host

# E) App Service Plan compartido (idempotente)
# Nombre estable para el plan (puedes cambiar B1 por S1/P1v3 si necesitas)
$AppPlanSku  = "B1"
$AppPlanName = "$slug-plan-$($AppPlanSku.ToLower())"

# Crear si no existe
$planExists = $false
try {
  az appservice plan show -g $rg -n $AppPlanName 1>$null 2>$null
  if ($LASTEXITCODE -eq 0) { $planExists = $true }
} catch { $planExists = $false }

if (-not $planExists) {
  az appservice plan create `
    -g $rg `
    -n $AppPlanName `
    --is-linux `
    --sku $AppPlanSku `
    -l $Location `
    -o table | Out-Host
} else {
  Write-Host "App Service Plan '$AppPlanName' ya existe en RG '$rg'."
}

# F) ACR (nombre válido, alfanumérico, 5-50 chars, globalmente único)
# Base alfanumérica a partir del slug
$acrRoot = ($slug -replace "[^a-z0-9]", "")  # quita guiones y todo lo no alfanumérico
if ([string]::IsNullOrWhiteSpace($acrRoot)) { $acrRoot = "dky" }  # fallback

# Ensamblar base y asegurar longitud
$acrBase = ($acrRoot + "acr")
if ($acrBase.Length -lt 5) { $acrBase = $acrBase + "000" } # mínimo 5
$acrBase = $acrBase.Substring(0, [Math]::Min(45, $acrBase.Length)) # deja margen para sufijo

# Si ya hay un ACR en el RG que empiece por esa base, úsalo
$existingAcr = az acr list -g $rg --query "[?starts_with(name, '$acrBase')].name" -o tsv 2>$null
if ($existingAcr) {
  $AcrName = ($existingAcr -split "`n")[0]
  Write-Host "ACR '$AcrName' ya existe en RG '$rg'."
} else {
  # Buscar un nombre disponible globalmente
  $AcrName = $acrBase
  $tries = 0
  while ($true) {
    $avail = az acr check-name -n $AcrName --query nameAvailable -o tsv 2>$null
    if ($avail -eq "true") { break }
    $tries++
    $suffix = (Get-Random -Minimum 10000 -Maximum 999999).ToString()
    $maxPrefixLen = 50 - $suffix.Length
    $prefix = $acrBase.Substring(0, [Math]::Min($maxPrefixLen, $acrBase.Length))
    $AcrName = "$prefix$suffix"
    if ($tries -gt 20) { throw "No se encontró nombre disponible para ACR tras varios intentos." }
  }

  # Crear ACR
  az acr create -g $rg -n $AcrName -l $Location --sku Basic -o table | Out-Host
}

# Admin-enabled para poder emitir credenciales
az acr update -n $AcrName --admin-enabled true -o table | Out-Host

# G) Funcion de importacion robusta
function Import-ImageSafe {
  param(
    [Parameter(Mandatory=$true)][string]$AcrName,
    [Parameter(Mandatory=$true)][string]$Repository,
    [Parameter(Mandatory=$true)][string]$Tag
  )

  # 0) Ya existe?
  $exists = $false
  try {
    az acr repository show -n $AcrName --image "${Repository}:${Tag}" 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) { $exists = $true }
  } catch { $exists = $false }

  if ($exists) {
    Write-Host "Imagen ${Repository}:${Tag} ya existe en ${AcrName}. No se reimporta."
    return
  }

  # 1) Intento: Amazon ECR Public
  $ecrSource = "public.ecr.aws/docker/library/${Repository}:${Tag}"
  Write-Host "Intento ECR Public: $ecrSource"
  try {
    az acr import -n $AcrName --source $ecrSource --image "${Repository}:${Tag}" --force -o table | Out-Host
    Write-Host "Importado desde ECR Public."
    return
  } catch {
    Write-Host "Fallo ECR Public. Probando Docker Hub autenticado (si hay credenciales)..."
  }

  # 2) Intento: Docker Hub autenticado (si hay env vars)
  $dhUser  = $env:DOCKERHUB_USER
  $dhToken = $env:DOCKERHUB_TOKEN
  if ($dhUser -and $dhToken) {
    $dhSource = "docker.io/library/${Repository}:${Tag}"
    Write-Host "Intento Docker Hub autenticado: $dhSource"
    try {
      az acr import -n $AcrName --source $dhSource --image "${Repository}:${Tag}" `
        --username $dhUser --password $dhToken --force -o table | Out-Host
      Write-Host "Importado desde Docker Hub autenticado."
      return
    } catch {
      Write-Host "Fallo Docker Hub autenticado. Probando pull local + push..."
    }
  } else {
    Write-Host "Sin DOCKERHUB_USER/DOCKERHUB_TOKEN. Se pasa a pull local + push."
  }

  # 3) Intento: Pull local + push (requiere Docker)
  try {
    az acr login -n $AcrName 1>$null
    $source = "${Repository}:${Tag}"
    $target = "${AcrName}.azurecr.io/${Repository}:${Tag}"

    if ($dhUser -and $dhToken) {
      docker login -u $dhUser -p $dhToken 1>$null
    }

    docker pull $source
    if ($LASTEXITCODE -ne 0) { throw "docker pull fallo con codigo $LASTEXITCODE" }

    docker tag $source $target
    if ($LASTEXITCODE -ne 0) { throw "docker tag fallo con codigo $LASTEXITCODE" }

    docker push $target
    if ($LASTEXITCODE -ne 0) { throw "docker push fallo con codigo $LASTEXITCODE" }

    Write-Host "Importado mediante pull local + push."
    return
  } catch {
    throw "No fue posible importar ${Repository}:${Tag} con ECR, Docker Hub autenticado ni pull local. Revise red/credenciales."
  }
}

# H) Importar mysql:8 de forma robusta
Import-ImageSafe -AcrName $AcrName -Repository "mysql" -Tag "8"

# I) Datos utiles para scripts por cliente
$acrCred = az acr credential show -n $AcrName | ConvertFrom-Json
$acrUser = $acrCred.username
$acrPwd  = $acrCred.passwords[0].value
$mysqlImage = "${AcrName}.azurecr.io/mysql:8"

Write-Host ""
Write-Host "=================================="
Write-Host "Infra lista. Usa esto en el script por cliente:"
Write-Host ("Resource Group : {0}" -f $rg)
Write-Host ("ACR            : {0}" -f $AcrName)
Write-Host ("Login server   : {0}.azurecr.io" -f $AcrName)
Write-Host ("ACR user       : {0}" -f $acrUser)
Write-Host ("ACR password   : {0}" -f $acrPwd)
Write-Host ("MySQL image    : {0}" -f $mysqlImage)
Write-Host ("App Service Plan: {0}" -f $AppPlanName)
Write-Host "=================================="

