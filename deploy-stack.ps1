$ErrorActionPreference = "Stop"

# (A) Login + subscripción
az account show -o table

# (B) Vars mínimas para la sesión (ajusta solo ClienteNombre si quieres)
$ClienteNombre   = "clientex"
$Location        = "westeurope"
$MysqlDatabase   = "dolibarrdb"
$PlanSku         = "B1"
$DolibarrImage   = "dolibarr/dolibarr:latest"

# Password MySQL (si quieres forzar una conocida, cámbiala aquí)
if (-not $MysqlRootPassword -or $MysqlRootPassword.Trim() -eq "") {
  Add-Type -AssemblyName System.Web
  $MysqlRootPassword = [System.Web.Security.Membership]::GeneratePassword(16,3)
  Write-Host "MYSQL_ROOT_PASSWORD = $MysqlRootPassword"
}

# Derivados
$slug       = ($ClienteNombre.ToLower() -replace "[^a-z0-9-]", "-")
$rg         = "$slug-rg"
$aciName    = "$slug-mysql"
$dnsLabel   = "$slug-mysql-{0}" -f (Get-Random)
$planName   = "$slug-plan-$($PlanSku.ToLower())"
$webAppName = "{0}-doli-{1}" -f $slug, (Get-Random)

# Providers (idempotente)
az provider register --namespace Microsoft.ContainerInstance -o none
az provider register --namespace Microsoft.Network            -o none
az provider register --namespace Microsoft.Storage           -o none

# Espera simple (máx ~2 min). Reintenta si no quedan Registered.
$providers = "Microsoft.ContainerInstance","Microsoft.Network","Microsoft.Storage"
foreach ($p in $providers) {
  $deadline = (Get-Date).AddMinutes(2)
  do {
    $state = az provider show -n $p --query registrationState -o tsv 2>$null
    Write-Host "$p -> $state"
    if ($state -eq "Registered") { break }
    Start-Sleep 5
  } while ((Get-Date) -lt $deadline)
}

# Resource Group
az group create -n $rg -l $Location -o table

$AcrName = ("{0}acr{1}" -f $slug, (Get-Random))
az acr create -g $rg -n $AcrName -l $Location --sku Basic -o table

# MUY IMPORTANTE: habilitar admin
az acr update -n $AcrName --admin-enabled true -o table

# Importar mysql:8 desde Docker Hub (evita rate limit del runtime)
az acr import -n $AcrName --source docker.io/library/mysql:8 --image mysql:8 --force -o table

# Credenciales para ACI/WebApp
$acrCred = az acr credential show -n $AcrName | ConvertFrom-Json
$acrUser = $acrCred.username
$acrPwd  = $acrCred.passwords[0].value
$mysqlImage = "$AcrName.azurecr.io/mysql:8"
Write-Host "ACR: $AcrName  | User: $acrUser  | Image: $mysqlImage"

