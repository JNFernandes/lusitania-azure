# Upload the consumer's REFERENCE DATA (Project 2's silver products and exchange rates) to the
# cloud lake, for the consumer running in Azure (it reads them from abfss://silver@...).
# Run after `terraform apply`, from C:\Projects\LusitaniaAzure, logged in with `az login`:
#     .\scripts\upload_reference.ps1
# A snapshot: run it again after DAG 4 has refreshed silver (the consumer accepts rates up to
# 7 days old, see rates_as_of() in Project 3).
$ErrorActionPreference = "Stop"
$lake = "stlusitaniadevjf01"
foreach ($table in "products", "exchange_rates") {
    $src = "C:\Projects\LusitaniaLakehouse\data\silver\$table"
    Write-Host "silver/$table"
    az storage blob upload-batch --account-name $lake --auth-mode login --destination silver `
        --destination-path $table --source $src --overwrite --output none
    # az does not stop the script on its own when it fails: check its exit code
    if ($LASTEXITCODE -ne 0) {
        throw "Upload of silver/$table failed. Does $lake exist (terraform apply in envs\dev)? Is your role active?"
    }
}
Write-Host "Done: abfss://silver@$lake.dfs.core.windows.net/{products,exchange_rates}"
