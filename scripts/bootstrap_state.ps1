# ONE-TIME BOOTSTRAP: the storage for Terraform's remote state.
#
# Terraform can't create the place where it keeps its own memory (it needs it before it starts),
# and `terraform destroy` must never delete it. So it is created here, once, with the Azure CLI,
# in its own resource group that the evening destroy doesn't touch. It holds a few KB: ~€0.
#
# Run from the project folder, after `az login`:
#     .\scripts\bootstrap_state.ps1

$ErrorActionPreference = "Stop"
$rg        = "rg-lusitania-tfstate"
$account   = "sttfstatelusitjf01"     # globally unique, 3-24 lowercase letters/digits
$container = "tfstate"
$location  = "westeurope"

Write-Host "1/4 resource group $rg"
az group create --name $rg --location $location --tags project=lusitania purpose=terraform-state --output none

Write-Host "2/4 storage account $account (private, TLS 1.2, no anonymous access)"
az storage account create --name $account --resource-group $rg --location $location `
    --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --allow-blob-public-access false `
    --tags project=lusitania purpose=terraform-state --output none

Write-Host "3/4 versioning: every change to the state keeps the previous version (undo for mistakes)"
az storage account blob-service-properties update --account-name $account --resource-group $rg `
    --enable-versioning true --output none

Write-Host "4/4 you get read/write on the state's DATA (Terraform logs in as you, no storage key)"
$me = az ad signed-in-user show --query id --output tsv
$scope = az storage account show --name $account --resource-group $rg --query id --output tsv
az role assignment create --assignee-object-id $me --assignee-principal-type User `
    --role "Storage Blob Data Contributor" --scope $scope --output none

Write-Host "   container $container (wait ~1 min if this says 'not authorized': the role is spreading)"
az storage container create --name $container --account-name $account --auth-mode login --output none

Write-Host "Done. Next: terraform init -migrate-state"
