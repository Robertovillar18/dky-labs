#$subs="3965c2f1-88a4-43a1-b792-9b08970bf05f"   # Coloca tu Subscription ID de la "Subscription 1"
#az account set --subscription $subs

# Confirma antes de borrar
$groups = az group list --query "[].name" -o tsv
Write-Host "Se van a eliminar estos Resource Groups:" -ForegroundColor Yellow
$groups

# Ejecuta la eliminación
foreach ($g in $groups) {
    az group delete --name $g --yes --no-wait
}
