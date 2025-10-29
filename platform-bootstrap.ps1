param(
  [string]$PlatformName = "platform",
  [string]$Location     = "westeurope",
  [string]$PlanSku      = "B1",
  # ==== Defaults estables para todos los clientes ====
  [string]$MysqlDatabase         = "dolibarrdb",
  [string]$DolibarrImage         = "dolibarr/dolibarr:latest",
  [string]$BackendRepository     = "backend",   # repo en tu ACR
  [string]$BackendTag            = "test",      # tag en tu ACR
  [string]$DbAppUser             = "dolibarr",
  [int]$ContainerBackendPort     = 8000,
  [string]$OutputFile            = ".\platform-outputs.json",

  # ==== NUEVO: build del backend desde carpeta local ====
  [string]$BackendPath           = ".\apps\backend",
  [switch]$UseDockerLocalBuild,              # si lo seteás, usa docker build + push
  [switch]$ForceBackendRebuild               # rehace la imagen aunque exista
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Slugify([string]$s) { return ($s.ToLower() -replace "[^a-z0-9-]", "-") }

# Mostrar cuenta activa
az account show -o table | Out-Host

# Registrar providers (idempotente)
az provider register --namespace Microsoft.ContainerInstance -o none
az provider register --namespace Microsoft.Network            -o none
az provider register --namespace Microsoft.Storage           -o none
az provider register --namespace Microsoft.Web               -o none

$providers = @("Microsoft.ContainerInstance","Microsoft.Network","Microsoft.Storage","Microsoft.Web")
foreach ($p in $providers) {
  $deadline = (Get-Date).AddMinutes(2)
  do {
    $state = az provider show -n $p --query registrationState -o tsv 2>$null
    Write-Host "$p -> $state"
    if ($state -eq "Registered") { break }
    Start-Sleep -Seconds 5
  } while ((Get-Date) -lt $deadline)
}

# Nombres base de plataforma
$slug   = Slugify $PlatformName
$rg     = "${slug}-rg"
$plan   = "$slug-plan-$($PlanSku.ToLower())"

# Resource Group (idempotente)
az group create -n $rg -l $Location -o table | Out-Host

# App Service Plan Linux (idempotente)
$planExists = $false
$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
az appservice plan show -g $rg -n $plan 1>$null 2>$null
$planExists = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $prev

if (-not $planExists) {
  az appservice plan create `
    -g $rg `
    -n $plan `
    --is-linux `
    --sku $PlanSku `
    -l $Location `
    -o table | Out-Host
} else {
  Write-Host "App Service Plan '$plan' ya existe en RG '$rg'."
}

# ACR (globalmente unico). Base alfanumerica desde el slug + "acr"
$acrRoot = ($slug -replace "[^a-z0-9]", "")
if ([string]::IsNullOrWhiteSpace($acrRoot)) { $acrRoot = "dky" }
$acrBase = ($acrRoot + "acr")
if ($acrBase.Length -lt 5) { $acrBase = $acrBase + "000" }
$acrBase = $acrBase.Substring(0, [Math]::Min(45, $acrBase.Length))  # margen para sufijo

# Si ya hay un ACR en este RG que empiece por la base, usarlo
$existingAcr = az acr list -g $rg --query "[?starts_with(name, '$acrBase')].name" -o tsv 2>$null
if ($existingAcr) {
  $AcrName = ($existingAcr -split "`n")[0]
  Write-Host "ACR '$AcrName' ya existe en RG '$rg'."
} else {
  # Buscar nombre disponible globalmente
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
    if ($tries -gt 25) { throw "No se encontro nombre disponible para ACR tras varios intentos." }
  }

  az acr create -g $rg -n $AcrName -l $Location --sku Basic -o table | Out-Host
}

# Habilitar admin (para emitir credenciales facilmente)
az acr update -n $AcrName --admin-enabled true -o table | Out-Host

# Funcion robusta para importar imagenes
function Import-ImageSafe {
  param(
    [Parameter(Mandatory=$true)][string]$AcrName,
    [Parameter(Mandatory=$true)][string]$Repository,  # ej: "mysql"
    [Parameter(Mandatory=$true)][string]$Tag          # ej: "8"
  )

  # Ya existe en ACR?
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  az acr repository show -n $AcrName --image "${Repository}:${Tag}" 1>$null 2>$null
  $exists = ($LASTEXITCODE -eq 0)
  $ErrorActionPreference = $prev
  if ($exists) { Write-Host "Imagen ${Repository}:${Tag} ya existe en ${AcrName}. No se reimporta."; return }

  # 1) Intentar ECR Public
  $ecrSource = "public.ecr.aws/docker/library/${Repository}:${Tag}"
  Write-Host "Intento ECR Public: $ecrSource"
  try {
    az acr import -n $AcrName --source $ecrSource --image "${Repository}:${Tag}" --force -o table | Out-Host
    Write-Host "Importado desde ECR Public."
    return
  } catch { Write-Host "Fallo ECR Public. Probando Docker Hub autenticado (si hay credenciales)..." }

  # 2) Intentar Docker Hub autenticado (si hay vars)
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

  # 3) Pull local + push (requiere Docker)
  try {
    az acr login -n $AcrName 1>$null
    $source = "${Repository}:${Tag}"
    $target = "${AcrName}.azurecr.io/${Repository}:${Tag}"

    if ($dhUser -and $dhToken) { docker login -u $dhUser -p $dhToken 1>$null }

    docker pull $source
    if ($LASTEXITCODE -ne 0) { throw "docker pull fallo con codigo $LASTEXITCODE" }
    docker tag  $source $target
    if ($LASTEXITCODE -ne 0) { throw "docker tag fallo con codigo $LASTEXITCODE" }
    docker push $target
    if ($LASTEXITCODE -ne 0) { throw "docker push fallo con codigo $LASTEXITCODE" }

    Write-Host "Importado mediante pull local + push."
  } catch {
    throw "No fue posible importar ${Repository}:${Tag} con ECR, Docker Hub o pull local. Revise red/credenciales."
  }
}

function BuildAndPush-Backend {
  param(
    [Parameter(Mandatory=$true)][string]$AcrName,
    [Parameter(Mandatory=$true)][string]$BackendRepository,
    [Parameter(Mandatory=$true)][string]$BackendTag,
    [Parameter(Mandatory=$true)][string]$BackendPath,
    [switch]$UseDockerLocalBuild,
    [switch]$ForceBackendRebuild
  )

  # ¿Ya existe la imagen en ACR?
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  az acr repository show -n $AcrName --image "${BackendRepository}:${BackendTag}" 1>$null 2>$null
  $exists = ($LASTEXITCODE -eq 0)
  $ErrorActionPreference = $prev

  if ($exists -and -not $ForceBackendRebuild) {
    Write-Host "Imagen $($BackendRepository):$BackendTag ya existe en $AcrName. Usa -ForceBackendRebuild para reconstruir."
    return
  }

  if (-not (Test-Path $BackendPath)) {
    throw "No existe la ruta de backend: $BackendPath"
  }

  if ($UseDockerLocalBuild) {
    Write-Host "==> Build local (docker) y push a ACR..."
    az acr login -n $AcrName 1>$null
    $loginServer = "$AcrName.azurecr.io"
    $targetImage = "$loginServer/$($BackendRepository):$BackendTag"
    pushd $BackendPath
    try {
      docker build -t $targetImage .
      if ($LASTEXITCODE -ne 0) { throw "docker build falló con código $LASTEXITCODE" }
      docker push $targetImage
      if ($LASTEXITCODE -ne 0) { throw "docker push falló con código $LASTEXITCODE" }
    } finally {
      popd
    }
  } else {
    Write-Host "==> Build en ACR (az acr build) desde $BackendPath ..."
    az acr build `
      -r $AcrName `
      -t "$($BackendRepository):$BackendTag" `
      $BackendPath `
      -o table | Out-Host
  }

  Write-Host "Backend publicado como ${BackendRepository}:${BackendTag} en $AcrName."
}

# Importar imagen base necesaria para los clientes (mysql:8)
Import-ImageSafe -AcrName $AcrName -Repository "mysql" -Tag "8"

# Credenciales ACR y login server
$acrCred     = az acr credential show -n $AcrName | ConvertFrom-Json
$acrUser     = $acrCred.username
$acrPwd      = $acrCred.passwords[0].value
$loginServer = "$AcrName.azurecr.io"

# Construir imagenes completas
$mysqlImage   = "$loginServer/mysql:8"
$backendImage = "$loginServer/${BackendRepository}:$BackendTag"


# === Build & push del backend desde apps\backend al ACR ===
BuildAndPush-Backend `
  -AcrName $AcrName `
  -BackendRepository $BackendRepository `
  -BackendTag $BackendTag `
  -BackendPath $BackendPath `
  -UseDockerLocalBuild:$UseDockerLocalBuild `
  -ForceBackendRebuild:$ForceBackendRebuild

# --------- Persistir outputs a JSON ---------
$outputs = [ordered]@{
  platformName                 = $PlatformName
  location                     = $Location
  resourceGroup                = $rg
  appServicePlan               = $plan
  appServicePlanResourceGroup  = $rg
  acr = [ordered]@{
    name         = $AcrName
    loginServer  = $loginServer
    adminUser    = $acrUser
    adminPass    = $acrPwd
  }
  images = [ordered]@{
    mysql   = $mysqlImage
    backend = $backendImage
  }
  defaults = [ordered]@{
    mysqlDatabase         = $MysqlDatabase
    dolibarrImage         = $DolibarrImage
    backend = [ordered]@{
      repository = $BackendRepository
      tag        = $BackendTag
    }
    dbAppUser             = $DbAppUser
    containerBackendPort  = $ContainerBackendPort
  }
  generatedAtUtc               = (Get-Date).ToUniversalTime().ToString("s") + "Z"
}

# Guardar JSON (igual que antes)
$destDir = Split-Path -Path $OutputFile -Parent
if (-not [string]::IsNullOrWhiteSpace($destDir) -and -not (Test-Path $destDir)) {
  New-Item -ItemType Directory -Path $destDir | Out-Null
}
$null = $outputs | ConvertTo-Json -Depth 8 | Out-File -FilePath $OutputFile -Encoding UTF8

# --------- Salida por consola ---------
Write-Host ""
Write-Host "=================================="
Write-Host "Plataforma lista. Usa estos valores en el script por cliente:"
Write-Host ("Resource Group        : {0}" -f $rg)
Write-Host ("App Service Plan      : {0}" -f $plan)
Write-Host ("ACR Name              : {0}" -f $AcrName)
Write-Host ("Login server          : {0}" -f $loginServer)
Write-Host ("ACR user              : {0}" -f $acrUser)
Write-Host ("ACR password          : {0}" -f $acrPwd)
Write-Host ("MySQL image           : {0}" -f $mysqlImage)
Write-Host ("Backend image (ACR)   : {0}" -f $backendImage)
Write-Host ("Defaults -> DB name   : {0}" -f $MysqlDatabase)
Write-Host ("Defaults -> Doli img  : {0}" -f $DolibarrImage)
Write-Host ("Defaults -> DB user   : {0}" -f $DbAppUser)
Write-Host ("Defaults -> BE port   : {0}" -f $ContainerBackendPort)
Write-Host ("Outputs JSON          : {0}" -f (Resolve-Path $OutputFile))
Write-Host "=================================="