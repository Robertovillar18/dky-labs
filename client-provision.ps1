param(
  [Parameter(Mandatory=$true)][string]$ClienteNombre,
  [string]$PlatformConfigPath = ".\platform-outputs.json",
  [switch]$Delete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ===== Cargar outputs de plataforma =====
if (-not (Test-Path $PlatformConfigPath)) {
  Write-Warning "No se encuentra $PlatformConfigPath. Ejecuta primero platform-bootstrap.ps1"
  return
}
$cfg = Get-Content -Raw -Path $PlatformConfigPath | ConvertFrom-Json

# Valores globales (no mas parametros)
$Location              = $cfg.location
$AppPlanName           = $cfg.appServicePlan
$AppPlanResourceGroup  = $cfg.appServicePlanResourceGroup
$AcrName               = $cfg.acr.name
$AcrUser               = $cfg.acr.adminUser
$AcrLogin              = $cfg.acr.loginServer

# Defaults estables
$MysqlDatabase         = $cfg.defaults.mysqlDatabase
$DolibarrImage         = $cfg.defaults.dolibarrImage
$DbAppUser             = $cfg.defaults.dbAppUser
$ContainerBackendPort  = [int]$cfg.defaults.containerBackendPort
$BackendRepository     = $cfg.defaults.backend.repository
$BackendTag            = $cfg.defaults.backend.tag

$BackendRef = "${BackendRepository}:$BackendTag"
$BackendImageFromAcr = "$AcrLogin/$BackendRef"

# Imagenes completas
$MysqlImageFromAcr     = $cfg.images.mysql         # "$AcrLogin/mysql:8"

# ============ PRECHECKS (ASCII-safe) ============
function Fail($msg) {
    Write-Warning $msg
    Write-Warning "El script se detendra aqui para evitar una creacion inconsistente."
    return
}
function Normalize-Region([string]$s) { return ($s.ToLower() -replace '[^a-z]', '') }

$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
az account show 1>$null 2>$null
$ErrorActionPreference = $prev
if ($LASTEXITCODE -ne 0) { Fail "No hay sesion de Azure activa. Ejecuta: az login"; return }

$allLocs = az account list-locations --query "[].name" -o tsv | ForEach-Object { $_.ToLower() }
if ($allLocs -notcontains $Location.ToLower()) { Fail "Location invalida: $Location"; return }

$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$planJson = az appservice plan show -g $AppPlanResourceGroup -n $AppPlanName -o json 2>$null
$ErrorActionPreference = $prev
if (-not $planJson) { Fail "No se encontro el App Service Plan '$AppPlanName' en RG '$AppPlanResourceGroup'."; return }
$plan = $planJson | ConvertFrom-Json
if ((Normalize-Region $plan.location) -ne (Normalize-Region $Location)) { Fail "Plan en '$($plan.location)' no coincide con '$Location'."; return }

$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$acrJson = az acr show -n $AcrName -o json 2>$null
$ErrorActionPreference = $prev
if (-not $acrJson) { Fail "No existe el ACR '$AcrName'."; return }
$acr = $acrJson | ConvertFrom-Json
if ($acr.adminUserEnabled -ne $true) { Fail "ACR '$AcrName' sin admin habilitado."; return }

$acrUserReal = az acr credential show -n $AcrName --query username -o tsv
if ($acrUserReal -ne $AcrUser) {
  Write-Warning "AcrUser en JSON '$AcrUser' difiere del real '$acrUserReal'. Se usara '$acrUserReal'."
  $AcrUser = $acrUserReal
}

Write-Host "[OK] Prechecks completados." -ForegroundColor Green
# ============ /PRECHECKS ============

# ===== Helpers (igual que antes) =====
function New-SafePassword([int]$len=20) { -join ((48..57)+(65..90)+(97..122) | Get-Random -Count $len | % {[char]$_}) }
function Get-RandomSuffix { (Get-Random -Minimum 100000 -Maximum 999999) }
function Slugify([string]$s) { ($s.ToLower() -replace "[^a-z0-9-]", "-") }
function Az-Ok { if ($LASTEXITCODE -ne 0) { throw "Azure CLI devolvio codigo $LASTEXITCODE" } }

function Get-ResourcesByTag {
  param(
    [string]$rg,
    [string]$resourceType,
    [string]$client,
    [string]$role = $null
  )
  $q = if ($role) { "[?tags.client=='$client' && tags.role=='$role']" } else { "[?tags.client=='$client']" }
  $json = az resource list -g $rg --resource-type $resourceType --query $q -o json 2>$null
  if ([string]::IsNullOrWhiteSpace($json) -or $json -eq "[]") { return @() }
  return @($json | ConvertFrom-Json)   # <-- fuerza array aunque haya 1 solo item
}
function Tag-Resource { param([string]$id,[hashtable]$tags)
  $kv = $tags.GetEnumerator() | % { "$($_.Key)=$($_.Value)" }
  az resource tag --ids $id --tags $kv -o none
}
function Get-WebAppByTag {
  param([string]$rg,[string]$client,[string]$role)
  $apps = @(Get-ResourcesByTag -rg $rg -resourceType "Microsoft.Web/sites" -client $client -role $role)
  if ($apps.Count -gt 0) { return $apps[0].name }
  return $null
}
function Ensure-WebAppByTag { param([string]$rg,[string]$client,[string]$role,[string]$prefix,[ScriptBlock]$createScript)
  $existing = Get-WebAppByTag -rg $rg -client $client -role $role
  if ($existing) { Write-Host "[OK] Reutilizando WebApp (role=$role): $existing"; return $existing }
  $name = "$prefix-$(Get-RandomSuffix)"; Write-Host "[NEW] Creando WebApp: $name"; & $createScript -Name $name
  $subId = az account show --query id -o tsv
  $resId = "/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.Web/sites/$name"
  Tag-Resource -id $resId -tags @{ client=$client; role=$role }; return $name
}
function Remove-WebAppsByTag {
  param([string]$rg,[string]$client,[string]$role=$null)
  $apps = @(Get-ResourcesByTag -rg $rg -resourceType "Microsoft.Web/sites" -client $client -role $role)
  foreach ($a in $apps) {
    Write-Host "Eliminando WebApp: $($a.name)"
    az webapp delete -g $rg -n $a.name -o none
  }
}
function Get-ContainerByTag {
  param([string]$rg,[string]$client,[string]$role)
  $cons = @(Get-ResourcesByTag -rg $rg -resourceType "Microsoft.ContainerInstance/containerGroups" -client $client -role $role)
  if ($cons.Count -gt 0) { return $cons[0].name }
  return $null
}
function Test-ContainerGroupExists { param([string]$rg,[string]$name)
  $prev=$ErrorActionPreference; $ErrorActionPreference="Continue"; az container show -g $rg -n $name 1>$null 2>$null
  $ok = ($LASTEXITCODE -eq 0); $ErrorActionPreference=$prev; return $ok
}

# ===== Derivados por cliente =====
$slug             = Slugify $ClienteNombre
$rg               = "${slug}-rg"
$aciNameDefault   = "${slug}-mysql"
$webDoliPrefix    = "${slug}-dolibarr"
$webBackendPrefix = "${slug}-backend"

# ===== Delete por tag =====
if ($Delete) {
  Write-Host "Eliminando recursos del cliente '$ClienteNombre'..."
  Remove-WebAppsByTag -rg $rg -client $ClienteNombre -role "dolibarr"
  Remove-WebAppsByTag -rg $rg -client $ClienteNombre -role "backend"
  $cons = Get-ResourcesByTag -rg $rg -resourceType "Microsoft.ContainerInstance/containerGroups" -client $ClienteNombre -role "mysql"
  foreach ($c in $cons) { Write-Host "Eliminando ACI: $($c.name)"; az container delete -g $rg -n $c.name --yes -o none }
  $prev=$ErrorActionPreference; $ErrorActionPreference="Continue"
  az group show -n $rg 1>$null 2>$null; if ($LASTEXITCODE -eq 0) { az group delete -n $rg --yes --no-wait }
  $ErrorActionPreference=$prev; Write-Host "Listo."; return
}

# ===== Credenciales dinamicas por cliente =====
#$MysqlRootPassword = New-SafePassword 20
#$DbAppPassword     = New-SafePassword 20
#Write-Host ("MYSQL_ROOT_PASSWORD = {0}" -f $MysqlRootPassword)
#Write-Host ("DB APP USER/PASS   = {0} / {1}" -f $DbAppUser, $DbAppPassword)

# ===== Resolver contraseñas por cliente (reusar si existen) =====
# Intentar obtener ACI existente por tag
$aciName = Get-ContainerByTag -rg $rg -client $ClienteNombre -role "mysql"

$ResolvedRootPwd = $null
$ResolvedAppPwd  = $null

if ($aciName) {
  # 1) Hay ACI: leer variables del contenedor existente
  $envJson = az container show -g $rg -n $aciName --query "containers[0].environmentVariables" -o json 2>$null
  if ($envJson -and $envJson -ne "[]") {
    $env = $envJson | ConvertFrom-Json
    $ResolvedRootPwd = ($env | Where-Object { $_.name -eq "MYSQL_ROOT_PASSWORD" }).value
    $ResolvedAppPwd  = ($env | Where-Object { $_.name -eq "MYSQL_PASSWORD" }).value
  }
}

if (-not $ResolvedAppPwd) {
  # 2) Si no hay ACI (o no vino la var), intentar reusar de la WebApp Dolibarr
  $existingDoli = Get-WebAppByTag -rg $rg -client $ClienteNombre -role "dolibarr"
  if ($existingDoli) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $ResolvedAppPwd = az webapp config appsettings list -g $rg -n $existingDoli `
      --query "[?name=='DOLI_DB_PASSWORD'].value" -o tsv 2>$null
    $ErrorActionPreference = $prev
  }
}

# 3) Generar lo que falte
if (-not $ResolvedRootPwd) { $ResolvedRootPwd = New-SafePassword 20 }
if (-not $ResolvedAppPwd)  { $ResolvedAppPwd  = New-SafePassword 20 }

# Mostrar (opcional, útil para depurar)
Write-Host ("MYSQL_ROOT_PASSWORD(resuelto) = {0}" -f $ResolvedRootPwd)
Write-Host ("DB APP USER/PASS(resuelto)    = {0} / {1}" -f $DbAppUser, $ResolvedAppPwd)

# ===== RG del cliente =====
az group create -n $rg -l $Location -o table | Out-Host
$subId = az account show --query id -o tsv
$rgId  = "/subscriptions/$subId/resourceGroups/$rg"
Tag-Resource -id $rgId -tags @{ client=$ClienteNombre }

# ===== ACR creds =====
$AcrPassword = az acr credential show -n $AcrName --query passwords[0].value -o tsv

# ===== ACI MySQL =====
$aciName = Get-ContainerByTag -rg $rg -client $ClienteNombre -role "mysql"
if (-not $aciName) {
  $aciName = if (-not (Test-ContainerGroupExists -rg $rg -name $aciNameDefault)) { $aciNameDefault } else { "${aciNameDefault}-$(Get-RandomSuffix)" }
  $dnsLabel = ("{0}-{1}" -f $aciName, (Get-Random))

  az container create -g $rg -n $aciName --image $MysqlImageFromAcr --cpu 1 --memory 1.5 --ports 3306 `
    --ip-address Public --dns-name-label $dnsLabel --os-type Linux `
    --environment-variables `
      "MYSQL_ROOT_PASSWORD=$ResolvedRootPwd" `
      "MYSQL_DATABASE=$MysqlDatabase" `
      "MYSQL_USER=$DbAppUser" `
      "MYSQL_PASSWORD=$ResolvedAppPwd" `
      "MYSQL_ROOT_HOST=%" `
    --registry-login-server "$AcrLogin" --registry-username $AcrUser --registry-password $AcrPassword `
    -o table | Out-Host

  if ($LASTEXITCODE -ne 0) {
    throw "Fallo la creacion del ACI '$aciName'. Revisa el error anterior."
  }

  # Taggear despues (compatibilidad)
  $aciId = az container show -g $rg -n $aciName --query id -o tsv
  az resource tag --ids $aciId --tags client=$ClienteNombre role=mysql -o none
} else {
  Write-Host "[OK] ACI MySQL ya existe (por tag): $aciName"
}

# Esperar Running
$deadline = (Get-Date).AddMinutes(6)
do {
  Start-Sleep -Seconds 6
  $state = az container show -g $rg -n $aciName --query "instanceView.state" -o tsv 2>$null
  Write-Host ("ACI estado: {0}" -f $state)
  if ($state -eq "Failed") { break }
} while ($state -ne "Running" -and (Get-Date) -lt $deadline)
if ($state -ne "Running") {
  az container logs -g $rg -n $aciName | Out-Host
  az container show -g $rg -n $aciName --query "containers[0].instanceView.events" -o table | Out-Host
  throw "El contenedor MySQL no llego a 'Running'."
}
$DB_FQDN = az container show -g $rg -n $aciName --query "ipAddress.fqdn" -o tsv
$DB_IP   = az container show -g $rg -n $aciName --query "ipAddress.ip"   -o tsv

# ===== Plan compartido =====
$planId = az appservice plan show -g $AppPlanResourceGroup -n $AppPlanName --query id -o tsv
if ([string]::IsNullOrWhiteSpace($planId)) { Fail "No se encontro el App Service Plan."; return }

# ===== Dolibarr WebApp =====
$webDoliName = Ensure-WebAppByTag -rg $rg -client $ClienteNombre -role "dolibarr" -prefix $webDoliPrefix -createScript {
  param([string]$Name)
  # El bloque captura $rg, $planId y $DolibarrImage del scope actual (no hace falta using:)
  az webapp create -g $rg -n $Name --plan $planId --container-image-name $DolibarrImage -o table | Out-Host
}
az webapp config container set -g $rg -n $webDoliName --container-image-name $DolibarrImage -o none
az webapp log config -g $rg -n $webDoliName --docker-container-logging filesystem | Out-Host
az webapp config appsettings set -g $rg -n $webDoliName --settings WEBSITES_ENABLE_APP_SERVICE_STORAGE=true -o table | Out-Host
az webapp config set -g $rg -n $webDoliName --always-on true | Out-Host

# ===== Backend WebApp =====
# Verificar que el repo:tag exista en ACR
$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
az acr repository show -n $AcrName --image $BackendRef 1>$null 2>$null
$imgOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $prev
if (-not $imgOk) {
  Fail "La imagen '${BackendRepository}:$BackendTag' no existe en $AcrName. Hacer push antes."
  return
}

$webBackendAppName = Ensure-WebAppByTag -rg $rg -client $ClienteNombre -role "backend" -prefix $webBackendPrefix -createScript {
  param([string]$Name)
  # Captura $rg, $planId y $BackendImageFromAcr del scope actual
  az webapp create -g $rg -n $Name --plan $planId --container-image-name $BackendImageFromAcr -o table | Out-Host
}
az webapp config container set -g $rg -n $webBackendAppName `
  --container-registry-url "https://$AcrLogin" --container-registry-user $AcrUser --container-registry-password $AcrPassword `
  --container-image-name $BackendImageFromAcr -o none
az webapp log config -g $rg -n $webBackendAppName --docker-container-logging filesystem -o none | Out-Host
az webapp config set -g $rg -n $webBackendAppName --always-on true -o none | Out-Host
az webapp config appsettings set -g $rg -n $webBackendAppName --settings `
  WEBSITES_ENABLE_APP_SERVICE_STORAGE=true `
  WEBSITES_PORT="$ContainerBackendPort" -o none | Out-Host

# ===== App Settings (Dolibarr -> MySQL) =====
$DbHostForApp = $DB_FQDN
az webapp config appsettings set -g $rg -n $webDoliName --settings `
  DOLI_DB_HOST="$DbHostForApp" `
  DOLI_DB_NAME="$MysqlDatabase" `
  DOLI_DB_USER="$DbAppUser" `
  DOLI_DB_PASSWORD="$ResolvedAppPwd" `
  DOLI_DB_PORT="3306" DOLI_DB_TYPE="mysqli" `
  DOLI_URL_ROOT="https://${webDoliName}.azurewebsites.net" `
  PHP_MEMORY_LIMIT="256M" WEBSITES_PORT="80" WEBSITES_CONTAINER_START_TIME_LIMIT="1800" -o table | Out-Host

# Reinicios
az webapp restart -g $rg -n $webDoliName -o none
az webapp restart -g $rg -n $webBackendAppName -o none

# ===== Salida =====
$AppDolibarrUrl = "https://$webDoliName.azurewebsites.net/"
$AppBackendUrl  = "https://$webBackendAppName.azurewebsites.net/"

Write-Host ""
Write-Host "=================================="
Write-Host "Cliente listo:"
Write-Host ("Resource Group   : {0}" -f $rg)
Write-Host ("MySQL FQDN       : {0}" -f $DB_FQDN)
Write-Host ("MySQL APP USER   : {0}" -f $DbAppUser)
Write-Host ("MySQL APP PASS   : {0}" -f $DbAppPassword)
Write-Host ("App Dolibarr     : {0}" -f $webDoliName)
Write-Host ("URL Dolibarr     : https://$webDoliName.azurewebsites.net/")
Write-Host ("App Backend      : {0}" -f $webBackendAppName)
Write-Host ("URL Backend      : https://$webBackendAppName.azurewebsites.net/")
Write-Host "=================================="

