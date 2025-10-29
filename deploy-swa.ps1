

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)] [string]$ResourceGroup,
  [Parameter(Mandatory=$true)] [string]$SwaName,

  # Parámetros opcionales si solo vas a registrar dominios:
  [string]$GithubUser,
  [string]$Repo,
  [string]$Branch = "main",
  [string]$Location = "West Europe",
  [string]$AppLocation = "site",
  [string]$OutputLocation = "build",
  [string[]]$CustomHostnames = @(),
  [string]$RootARecordIp = "20.49.104.34",

  # NUEVO SWITCH
  [switch]$OnlyHostnames,
  [switch]$NoGithubLogin,
  [bool]$BuildLocal = $false,         # corre build local (site -> build)
  [bool]$DeployLocal = $false,        # publica el build a SWA ahora mismo
  [bool]$AutoInstallSwa = $true       # instala SWA CLI si falta (npm -g)

)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Az-Check {
  if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) no está instalado o no está en el PATH."
  }
}

function Ensure-ProviderRegistered([string]$ns) {
  Write-Host "Registrando provider '$ns' (idempotente)..." -ForegroundColor Cyan
  az provider register --namespace $ns -o none
  $deadline = (Get-Date).AddMinutes(2)
  do {
    Start-Sleep -Seconds 3
    $state = az provider show --namespace $ns --query "registrationState" -o tsv 2>$null
    Write-Host "  $ns -> $state"
    if ($state -eq "Registered") { return }
  } while ((Get-Date) -lt $deadline)
  Write-Warning "Provider $ns no quedó en estado 'Registered' a tiempo."
}

function Ensure-ResourceGroup([string]$rg,[string]$loc) {
  Write-Host "Asegurando Resource Group '$rg' en '$loc'..." -ForegroundColor Cyan
  az group create --name $rg --location $loc -o table | Out-Host
}

function Swa-Exists([string]$name,[string]$rg) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  az staticwebapp show --name $name --resource-group $rg 1>$null 2>$null
  $ok = ($LASTEXITCODE -eq 0)
  $ErrorActionPreference = $prev
  return $ok
}

function Create-Or-Show-SWA {
  param(
    [string]$rg, [string]$name, [string]$loc,
    [string]$githubUser, [string]$repo, [string]$branch,
    [string]$appLoc, [string]$outLoc, [switch]$noLogin
  )
  $exists = Swa-Exists -name $name -rg $rg
  if ($exists) {
    Write-Host "Static Web App '$name' ya existe en RG '$rg'." -ForegroundColor Yellow
  } else {
    Write-Host "Creando Static Web App '$name' y conectando repo..." -ForegroundColor Green
    $args = @(
      "staticwebapp","create",
      "--name",$name,
      "--resource-group",$rg,
      "--source","https://github.com/$githubUser/$repo",
      "--branch",$branch,
      "--location",$loc,
      "--app-location",$appLoc,
      "--output-location",$outLoc
    )
    if (-not $noLogin) { $args += "--login-with-github" }
    az @args -o table | Out-Host
  }

  $defaultHostname = az staticwebapp show --name $name --resource-group $rg --query defaultHostname -o tsv
  if (-not $defaultHostname) { throw "No pude obtener defaultHostname de la SWA." }
  return $defaultHostname
}

function Add-Hostnames {
  param([string]$rg,[string]$name,[string[]]$hosts)
  if (-not $hosts -or $hosts.Count -eq 0) { return }
  Write-Host "Agregando hostnames personalizados..." -ForegroundColor Cyan
  foreach ($h in $hosts) {
    Write-Host "  + $h"
    az staticwebapp hostname set --name $name --resource-group $rg --hostname $h -o table | Out-Host
  }
}

function Ensure-Command($cmd) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { return $false }
  return $true
}

function Ensure-SwaCli {
  if (-not (Ensure-Command "swa")) {
    if (-not $AutoInstallSwa) { throw "No se encontró 'swa'. Instalalo: npm i -g @azure/static-web-apps-cli" }
    Write-Host "Instalando SWA CLI (@azure/static-web-apps-cli)..." -ForegroundColor Cyan
    npm i -g @azure/static-web-apps-cli | Out-Host
    if (-not (Ensure-Command "swa")) { throw "No se pudo instalar 'swa' (SWA CLI)." }
  }
}

function Build-Site([string]$sitePath, [string]$outDir) {
  if (-not (Test-Path $sitePath)) { throw "No existe la carpeta '$sitePath'." }
  Push-Location $sitePath
  try {
    if (-not (Ensure-Command "node")) { throw "Node.js no está en PATH." }

    # Detectar gestor: pnpm > yarn > npm
    $pm = "npm"
    if (Test-Path ".\pnpm-lock.yaml")      { if (Ensure-Command "pnpm") { $pm = "pnpm" } else { throw "Falta pnpm." } }
    elseif (Test-Path ".\yarn.lock")       { if (Ensure-Command "yarn") { $pm = "yarn" } }
    Write-Host "Gestor detectado: $pm" -ForegroundColor Cyan

    switch ($pm) {
      "pnpm" { pnpm install; pnpm run build }
      "yarn" { yarn install --frozen-lockfile; yarn build }
      "npm"  { npm ci; npm run build }
    }

    $outPath = Join-Path (Get-Location) $outDir
    if (-not (Test-Path $outPath)) { throw "No se encontró la carpeta de salida '$outPath' luego del build." }
    return $outPath
  } finally { Pop-Location }
}

function Deploy-Static([string]$rg,[string]$name,[string]$buildPath) {
  Ensure-SwaCli
  # Obtener el deployment token de la SWA
  $token = az staticwebapp secrets list --name $name --resource-group $rg --query "properties.apiKey" -o tsv
  if ([string]::IsNullOrWhiteSpace($token)) { throw "No pude obtener el deployment token." }
  # Publicar el build (carpeta) a producción
  # (podés pasar el folder directamente)
  Write-Host "Publicando '$buildPath' a Azure Static Web Apps..." -ForegroundColor Green
  swa deploy $buildPath --deployment-token $token --env production | Out-Host
}


# ===== MODO SOLO DOMINIOS =====
if ($OnlyHostnames) {
  if ($CustomHostnames.Count -eq 0) {
    throw "Debes especificar al menos un dominio en -CustomHostnames"
  }

  Write-Host "== MODO SOLO HOSTNAMES ACTIVADO ==" -ForegroundColor Cyan

  # 1) Chequear que la SWA existe
  $exists = az staticwebapp show --name $SwaName --resource-group $ResourceGroup 2>$null
  if (-not $?) {
    throw "La Static Web App '$SwaName' no existe en el Resource Group '$ResourceGroup'."
  }

  # 2) Registrar dominios
  foreach ($hostname in $CustomHostnames) {
    Write-Host "`nIntentando registrar dominio: $hostname" -ForegroundColor Green
    az staticwebapp hostname set `
      --name $SwaName `
      --resource-group $ResourceGroup `
      --hostname $hostname -o table | Out-Host

    # 3) Mostrar información de validación
    Write-Host "Información DNS / Validación para: $hostname"
    az staticwebapp hostname show `
      --name $SwaName `
      --resource-group $ResourceGroup `
      --hostname $hostname -o json | Out-Host
  }

  # 4) Listar resultado final
  Write-Host "`nHostnames registrados actualmente:" -ForegroundColor Yellow
  az staticwebapp hostname list `
    --name $SwaName `
    --resource-group $ResourceGroup -o table | Out-Host

  return
}

# --- MAIN ---
Az-Check
Write-Host "=== Azure Static Web App: despliegue ===" -ForegroundColor Magenta
az account show -o table | Out-Host

Ensure-ProviderRegistered "Microsoft.Web"
Ensure-ResourceGroup -rg $ResourceGroup -loc $Location

$defaultHostname = Create-Or-Show-SWA `
  -rg $ResourceGroup -name $SwaName -loc $Location `
  -githubUser $GithubUser -repo $Repo -branch $Branch `
  -appLoc $AppLocation -outLoc $OutputLocation -noLogin:$NoGithubLogin

Write-Host ""
Write-Host "Hostname por defecto: $defaultHostname" -ForegroundColor Green
Write-Host ""

if ($CustomHostnames.Count -gt 0) {
  # Instrucciones DNS
  $wwwHost = ($CustomHostnames | Where-Object { $_ -match '^(www\.)' } | Select-Object -First 1)
  $rootHost = ($CustomHostnames | Where-Object { $_ -notmatch '^(www\.)' } | Select-Object -First 1)

  Write-Host "== Instrucciones DNS sugeridas ==" -ForegroundColor Cyan
  if ($wwwHost) {
    Write-Host ("CNAME  Host: www   ->  {0}" -f $defaultHostname)
  }
  if ($rootHost) {
    Write-Host ("A      Host: @     ->  {0}" -f $RootARecordIp)
  }
  Write-Host ""

  # Intentar agregar hostnames ahora
  Add-Hostnames -rg $ResourceGroup -name $SwaName -hosts $CustomHostnames

  Write-Host ""
  Write-Host "Verificación de hostnames configurados:" -ForegroundColor Cyan
  az staticwebapp hostname list --name $SwaName --resource-group $ResourceGroup -o table | Out-Host
} else {
  Write-Host "No se especificaron dominios personalizados (CustomHostnames). Podés agregarlos luego con:" -ForegroundColor Yellow
  Write-Host ("az staticwebapp hostname set --name {0} --resource-group {1} --hostname <tu-dominio>" -f $SwaName,$ResourceGroup)
}


# === Build & Deploy local opcionales ===
if ($BuildLocal -or $DeployLocal) {
  # Build si se pidió (o si se pidió deploy sin build, verificamos que el folder exista)
  $buildPath = Join-Path (Resolve-Path $AppLocation) $OutputLocation

  if ($BuildLocal) {
    Write-Host "Ejecutando build local..." -ForegroundColor Cyan
    $buildPath = Build-Site -sitePath (Resolve-Path $AppLocation) -outDir $OutputLocation
    Write-Host "Build OK -> $buildPath" -ForegroundColor Green
  } else {
    if (-not (Test-Path $buildPath)) {
      throw "No existe '$buildPath'. Corré con -BuildLocal o generá el build antes."
    }
  }

  if ($DeployLocal) {
    Deploy-Static -rg $ResourceGroup -name $SwaName -buildPath $buildPath
  }
}

Write-Host ""
Write-Host "Listo. Tu SWA queda asociada a: https://$defaultHostname" -ForegroundColor Green
