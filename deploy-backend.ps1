param(
  [Parameter(Mandatory=$true)][string]$ClientResourceGroup,
  [Parameter(Mandatory=$true)][string]$AppPlanName,
  [Parameter(Mandatory=$true)][string]$AppPlanResourceGroup,
  [Parameter(Mandatory=$true)][string]$AcrName,          # ej: clientexacr
  [string]$AcrUser,                                      # por defecto = $AcrName
  [string]$AcrPassword,                                  # se obtiene solo si no lo pasas
  [string]$AppName = "backend-" + (Get-Random),
  [string]$AcrImageTag = "backend:test",                 # debe existir en ACR
  [string]$Location = "westeurope",
  [int]$ContainerPort = 8000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Az-Ok { if ($LASTEXITCODE -ne 0) { throw "Azure CLI devolvió código $LASTEXITCODE" } }
function New-Slug([string]$s) { return ($s.ToLower() -replace "[^a-z0-9-]", "-") }
function Test-WebAppExists { param([string]$rg,[string]$name)
  $prev=$ErrorActionPreference; $ErrorActionPreference="Continue"
  az webapp show -g $rg -n $name 1>$null 2>$null; $ok=($LASTEXITCODE -eq 0)
  $ErrorActionPreference=$prev; return $ok
}

# Defaults
if (-not $AcrUser -or $AcrUser.Trim() -eq "") { $AcrUser = $AcrName }
if (-not $AcrPassword -or $AcrPassword.Trim() -eq "" -or $AcrPassword -eq "TU_ACR_PASSWORD") {
  # Obtención silenciosa (no se imprime)
  $AcrPassword = az acr credential show -n $AcrName --query passwords[0].value -o tsv
  if ([string]::IsNullOrWhiteSpace($AcrPassword)) { throw "No pude obtener contraseña del ACR '$AcrName'. Habilita admin: az acr update -n $AcrName --admin-enabled true" }
}

$AppName  = New-Slug $AppName
$acrLogin = "${AcrName}.azurecr.io"
$acrImage = "${acrLogin}/$AcrImageTag"

Write-Host "=== CONFIG ==="
Write-Host "App Name        : $AppName"
Write-Host "Resource Group  : $ClientResourceGroup"
Write-Host "Plan            : $AppPlanName in $AppPlanResourceGroup"
Write-Host "ACR Image       : $acrImage"
Write-Host "Container port  : $ContainerPort"
Write-Host "================"

# Asegurar RG
az group create -n $ClientResourceGroup -l $Location -o none
Az-Ok

# Asegurar/leer plan
$plan = az appservice plan show -g $AppPlanResourceGroup -n $AppPlanName -o json | ConvertFrom-Json
if (-not $plan) {
  Write-Host "Plan '$AppPlanName' no existe. Creándolo (B1 Linux)..." -ForegroundColor Yellow
  az appservice plan create -g $AppPlanResourceGroup -n $AppPlanName --is-linux --sku B1 -l $Location -o none
  $plan = az appservice plan show -g $AppPlanResourceGroup -n $AppPlanName -o json | ConvertFrom-Json
}
if (-not $plan) { throw "No se pudo crear/leer el App Service Plan '$AppPlanName'." }

# Ajustar región si difiere
$planLocation = $plan.location
if ($planLocation -ne $Location) {
  Write-Host "Ajustando Location a la región del plan: $planLocation (antes: $Location)" -ForegroundColor Yellow
  $Location = $planLocation
  az group create -n $ClientResourceGroup -l $Location -o none
}
$planId = $plan.id

# Verificar que la imagen exista en ACR (opcional pero útil)
$prev=$ErrorActionPreference; $ErrorActionPreference="Continue"
az acr repository show -n $AcrName --image $AcrImageTag 1>$null 2>$null
$imgOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference=$prev
if (-not $imgOk) { throw "La imagen '$AcrImageTag' no existe en $AcrName. Asegúrate de que el workflow de GitHub haya hecho push." }

# Crear/actualizar Web App
if (-not (Test-WebAppExists -rg $ClientResourceGroup -name $AppName)) {
  az webapp create -g $ClientResourceGroup -n $AppName --plan $planId --container-image-name $acrImage -o none
} else {
  az webapp config container set -g $ClientResourceGroup -n $AppName --container-image-name $acrImage -o none
  Write-Host "Web App existía; imagen actualizada."
}

# Configurar pull privado
az webapp config container set `
  -g $ClientResourceGroup `
  -n $AppName `
  --docker-registry-server-url "https://$acrLogin" `
  --docker-registry-server-user $AcrUser `
  --docker-registry-server-password $AcrPassword `
  -o none

# Logging / storage / always-on / puerto
az webapp log config -g $ClientResourceGroup -n $AppName --docker-container-logging filesystem -o none
az webapp config set -g $ClientResourceGroup -n $AppName --always-on true -o none
az webapp config appsettings set -g $ClientResourceGroup -n $AppName --settings `
  WEBSITES_ENABLE_APP_SERVICE_STORAGE=true `
  WEBSITES_PORT="$ContainerPort" `
  -o none

az webapp restart -g $ClientResourceGroup -n $AppName -o none

$publicUrl = "https://$AppName.azurewebsites.net"
Write-Host "Backend desplegado en: $publicUrl"
