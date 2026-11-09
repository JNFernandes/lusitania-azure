# ONE-TIME BOOTSTRAP: the identity GitHub Actions uses to run `terraform plan`, with OIDC.
#
# OIDC = no secret anywhere. GitHub gives each workflow run a short-lived token saying
# "I am repo X, branch Y". The FEDERATED CREDENTIALS below tell Entra ID to accept GitHub's tokens
# for exactly two cases, and nothing else:
#     repo:<owner>@<owner id>/<repo>@<repo id>:ref:refs/heads/main     pushes to main
#     repo:<owner>@<owner id>/<repo>@<repo id>:pull_request            pull requests
# GitHub puts the account and repo ID NUMBERS in the subject: a repo deleted and re-created
# with the same name gets a new id, so Azure stops trusting it. The ids come from GitHub's API.
#
# Roles (least privilege for PLANNING, not applying):
#     Reader on the subscription                               see what exists
#     Storage Blob Data Contributor on the STATE account       read the state + take the lock
#
# Run once, from C:\Projects\LusitaniaAzure, after `az login`:
#     .\scripts\bootstrap_ci.ps1 -Repo JNFernandes/lusitania-azure
param([string]$Repo = "JNFernandes/lusitania-azure")
$ErrorActionPreference = "Stop"
$name = "sp-lusitania-github-ci"

function Check([string]$what) { if ($LASTEXITCODE -ne 0) { throw "failed: $what" } }

$sub    = az account show --query id -o tsv;        Check "az account show"
$tenant = az account show --query tenantId -o tsv

Write-Host "1/4 application + service principal '$name'"
$appId = az ad app list --display-name $name --query "[0].appId" -o tsv
if (-not $appId) { $appId = az ad app create --display-name $name --query appId -o tsv; Check "app create" }
$spId = az ad sp list --filter "appId eq '$appId'" --query "[0].id" -o tsv
if (-not $spId) { $spId = az ad sp create --id $appId --query id -o tsv; Check "sp create" }

Write-Host "2/4 federated credentials (trust GitHub for ${Repo}: main + pull requests)"
$gh = Invoke-RestMethod "https://api.github.com/repos/$Repo"          # public repo: no login needed
$base = "repo:$($gh.owner.login)@$($gh.owner.id)/$($gh.name)@$($gh.id)"
$existing = az ad app federated-credential list --id $appId --query "[].name" -o tsv
foreach ($fc in @(
        @{ name = "github-main";          subject = "${base}:ref:refs/heads/main" },
        @{ name = "github-pull-requests"; subject = "${base}:pull_request" })) {
    $action = if ($existing -contains $fc.name) { "update" } else { "create" }
    $file = New-TemporaryFile
    @{ name = $fc.name; issuer = "https://token.actions.githubusercontent.com"; subject = $fc.subject
       audiences = @("api://AzureADTokenExchange") } | ConvertTo-Json -Compress | Set-Content $file
    if ($action -eq "update") {
        az ad app federated-credential update --id $appId --federated-credential-id $fc.name `
            --parameters "@$($file.FullName)" --output none
    } else {
        az ad app federated-credential create --id $appId --parameters "@$($file.FullName)" --output none
    }
    Check "federated credential $($fc.name)"
    Remove-Item $file
    Write-Host "   $($fc.name): $($fc.subject)"
}

Write-Host "3/4 roles: Reader (subscription) + Storage Blob Data Contributor (state account)"
$state = az storage account show --name sttfstatelusitjf01 --resource-group rg-lusitania-tfstate --query id -o tsv
foreach ($r in @(@{ role = "Reader"; scope = "/subscriptions/$sub" },
                 @{ role = "Storage Blob Data Contributor"; scope = $state })) {
    az role assignment create --assignee-object-id $spId --assignee-principal-type ServicePrincipal `
        --role $r.role --scope $r.scope --output none
    Check "role $($r.role)"
}

Write-Host "4/4 done. In GitHub: Settings -> Secrets and variables -> Actions -> VARIABLES tab:"
Write-Host "   AZURE_CLIENT_ID       = $appId"
Write-Host "   AZURE_TENANT_ID       = $tenant"
Write-Host "   AZURE_SUBSCRIPTION_ID = $sub"
Write-Host "and in the SECRETS tab:  TF_VAR_ALERT_EMAIL = your e-mail (kept private in the logs)"
