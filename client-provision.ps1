param(
  [Parameter(Mandatory=$true)][string]$ClienteNombre,
  [string]$Location              = "westeurope",
  [string]$MysqlDatabase         = "dolibarrdb",
  [string]$DolibarrImage         = "dolibarr/dolibarr:latest",   # imagen pública
  # ACR central (salida del bootstrap)
  [Parameter(Mandatory=$true)][string]$AcrName,
  [Parameter(Mandatory=$true)][string]$AcrUser,
  # [Parameter(Mandatory=$true)][string]$AcrPassword,
  # App Service Plan compartido (creado por platform-bootstrap)
  [Parameter(Mandatory=$true)][string]$AppPlanName,
  [Parameter(Mandatory=$true)][string]$AppPlanResourceGroup,
  # Password MySQL root (opcional). Si no se pasa, genero una "safe".
  [string]$MysqlRootPassword,
  # Usuario/Password de app (no-root) para Dolibarr en MySQL (opcionales; si faltan, se generan)
  [string]$DbAppUser = "dolibarr",
  [string]$DbAppPassword,
  [switch]$Delete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------- Helpers --------
function New-SafePassword([int]$len=20) {
  -join ((48..57)+(65..90)+(97..122) | Get-Random -Count $len | ForEach-Object {[char]$_})
}

function Az-Ok { if ($LASTEXITCODE -ne 0) { throw "Azure CLI devolvió código $LASTEXITCODE" } }

function Test-WebAppExists {
  param([string]$rg,[string]$name)
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  & az webapp show -g $rg -n $name 1>$null 2>$null
  $ok = ($LASTEXITCODE -eq 0)
  $ErrorActionPreference = $prev
  return $ok
}

# -------- Derivados --------
$slug       = ($ClienteNombre.ToLower() -replace "[^a-z0-9-]", "-")
$rg         = "${slug}-rg"
$aciName    = "${slug}-mysql"
$dnsLabel   = ("{0}-{1}" -f $aciName, (Get-Random))
$webAppName = ("{0}-doli-{1}" -f $slug, (Get-Random))   # global unico
$mysqlImage = "${AcrName}.azurecr.io/mysql:8"

# -------- Delete (limpieza por cliente) --------
if ($Delete) {
  Write-Host "Eliminando WebApp si existe..."
  if (Test-WebAppExists -rg $rg -name $webAppName) {
    az webapp delete -g $rg -n $webAppName -o none
  }
  Write-Host "Eliminando ACI si existe..."
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  az container show -g $rg -n $aciName 1>$null 2>$null
  if ($LASTEXITCODE -eq 0) { az container delete -g $rg -n $aciName --yes -o none }
  $ErrorActionPreference = $prev
  Write-Host "Eliminando Resource Group '$rg'..."
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  az group show -n $rg 1>$null 2>$null
  if ($LASTEXITCODE -eq 0) { az group delete --name $rg --yes --no-wait }
  $ErrorActionPreference = $prev
  Write-Host "Listo."
  exit 0
}

# -------- Credenciales MySQL --------
if (-not $MysqlRootPassword -or $MysqlRootPassword.Trim() -eq "") {
  $MysqlRootPassword = New-SafePassword 20
}
if (-not $DbAppPassword -or $DbAppPassword.Trim() -eq "") {
  $DbAppPassword = New-SafePassword 20
}
Write-Host ("MYSQL_ROOT_PASSWORD = {0}" -f $MysqlRootPassword)
Write-Host ("DB APP USER/PASS   = {0} / {1}" -f $DbAppUser, $DbAppPassword)

# -------- RG (idempotente) --------
az group create -n $rg -l $Location -o table | Out-Host
Az-Ok

# -------- ACI MySQL (con usuario de app) --------
Write-Host "Obteniendo credenciales del ACR '$AcrName'..."
$AcrPassword = az acr credential show -n $AcrName --query passwords[0].value -o tsv

Write-Host "Creando MySQL en ACI '$aciName' con imagen $mysqlImage ..."
# Limpieza previa si existía
$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
az container show -g $rg -n $aciName 1>$null 2>$null
if ($LASTEXITCODE -eq 0) { az container delete -g $rg -n $aciName --yes -o none }
$ErrorActionPreference = $prev

az container create `
  -g $rg -n $aciName `
  --image $mysqlImage `
  --cpu 1 --memory 1.5 `
  --ports 3306 `
  --ip-address Public `
  --dns-name-label $dnsLabel `
  --os-type Linux `
  --environment-variables `
    "MYSQL_ROOT_PASSWORD=$MysqlRootPassword" `
    "MYSQL_DATABASE=$MysqlDatabase" `
    "MYSQL_USER=$DbAppUser" `
    "MYSQL_PASSWORD=$DbAppPassword" `
    "MYSQL_ROOT_HOST=%" `
  --registry-login-server "${AcrName}.azurecr.io" `
  --registry-username $AcrUser `
  --registry-password $AcrPassword `
  -o table | Out-Host
Az-Ok

# Esperar estado Running (max 6 min)
$deadline = (Get-Date).AddMinutes(6)
do {
  Start-Sleep -Seconds 6
  $state = az container show -g $rg -n $aciName --query "instanceView.state" -o tsv 2>$null
  Write-Host ("ACI estado: {0}" -f $state)
  if ($state -eq "Failed") { break }
} while ($state -ne "Running" -and (Get-Date) -lt $deadline)

if ($state -ne "Running") {
  Write-Host "Logs del contenedor:" -ForegroundColor Yellow
  az container logs -g $rg -n $aciName | Out-Host
  Write-Host "`nEventos:" -ForegroundColor Yellow
  az container show -g $rg -n $aciName --query "containers[0].instanceView.events" -o table | Out-Host
  throw "El contenedor MySQL no llegó a 'Running'."
}

$DB_FQDN = az container show -g $rg -n $aciName --query "ipAddress.fqdn" -o tsv
$DB_IP   = az container show -g $rg -n $aciName --query "ipAddress.ip"   -o tsv
Write-Host "MySQL ACI FQDN: $DB_FQDN  IP: $DB_IP"

# -------- Resolver ID del App Service Plan compartido --------
$planId = az appservice plan show -g $AppPlanResourceGroup -n $AppPlanName --query id -o tsv
if ([string]::IsNullOrWhiteSpace($planId)) {
  throw "No se encontró el App Service Plan '$AppPlanName' en RG '$AppPlanResourceGroup'."
}

# -------- Web App Dolibarr (en el plan compartido) --------
Write-Host "Creando/asegurando Web App '$webAppName' (plan: $AppPlanName) ..."
$exists = Test-WebAppExists -rg $rg -name $webAppName
if (-not $exists) {
  # crear en el RG del cliente pero asociada al plan compartido (por ID)
  az webapp create -g $rg -n $webAppName --plan $planId --container-image-name $DolibarrImage -o table | Out-Host
  # Re-verificar por consistencia eventual
  Start-Sleep -Seconds 5
  $exists = Test-WebAppExists -rg $rg -name $webAppName
  if (-not $exists) {
    Start-Sleep -Seconds 10
    $exists = Test-WebAppExists -rg $rg -name $webAppName
    if (-not $exists) { throw "No se pudo crear la Web App '$webAppName'." }
  }
} else {
  az webapp config container set -g $rg -n $webAppName --container-image-name $DolibarrImage -o none
  Write-Host "Web App existia; imagen actualizada."
}

# -------- Logging, storage y always-on --------
az webapp log config -g $rg -n $webAppName --docker-container-logging filesystem | Out-Host
az webapp config appsettings set -g $rg -n $webAppName --settings WEBSITES_ENABLE_APP_SERVICE_STORAGE=true -o table | Out-Host
az webapp config set -g $rg -n $webAppName --always-on true | Out-Host

# -------- App Settings (Dolibarr -> MySQL) --------
# Por defecto usamos el FQDN; si diera problemas de DNS, sustituir por IP.
$DbHostForApp = $DB_FQDN  # o: $DbHostForApp = $DB_IP

Write-Host "Configurando app settings..."
az webapp config appsettings set -g $rg -n $webAppName --settings `
  DOLI_DB_HOST="$DbHostForApp" `
  DOLI_DB_NAME="$MysqlDatabase" `
  DOLI_DB_USER="$DbAppUser" `
  DOLI_DB_PASSWORD="$DbAppPassword" `
  DOLI_DB_PORT="3306" `
  DOLI_DB_TYPE="mysqli" `
  DOLI_URL_ROOT="https://${webAppName}.azurewebsites.net" `
  PHP_MEMORY_LIMIT="256M" `
  WEBSITES_PORT="80" `
  WEBSITES_CONTAINER_START_TIME_LIMIT="1800" `
  -o table | Out-Host

# Reinicio
az webapp restart -g $rg -n $webAppName -o none

# -------- Salida --------
$AppUrl = "https://${webAppName}.azurewebsites.net/"
Write-Host ""
Write-Host "=================================="
Write-Host "Cliente listo:"
Write-Host ("Resource Group   : {0}" -f $rg)
Write-Host ("MySQL FQDN       : {0}" -f $DB_FQDN)
Write-Host ("MySQL APP USER   : {0}" -f $DbAppUser)
Write-Host ("MySQL APP PASS   : {0}" -f $DbAppPassword)
Write-Host ("Web App          : {0}" -f $webAppName)
Write-Host ("URL              : {0}" -f $AppUrl)
Write-Host "=================================="
