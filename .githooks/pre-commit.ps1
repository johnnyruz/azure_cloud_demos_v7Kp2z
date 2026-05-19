$ErrorActionPreference = 'Stop'

$patterns = @(
    'AccountEndpoint=https://.*\.documents\.azure\.com',
    'AccountKey=',
    'CosmosDb.*ConnectionString.*AccountEndpoint'
)

$stagedFiles = git diff --cached --name-only --diff-filter=ACM |
    Where-Object { $_ -notlike '.githooks/*' }
$secretFindings = New-Object System.Collections.Generic.List[string]

foreach ($file in $stagedFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        continue
    }

    $content = git show ":$file"
    for ($i = 0; $i -lt $content.Count; $i++) {
        foreach ($pattern in $patterns) {
            if ($content[$i] -match $pattern) {
                $secretFindings.Add("${file}:$($i + 1):$($content[$i])")
                break
            }
        }
    }
}

if ($secretFindings.Count -gt 0) {
    Write-Host 'Commit blocked: staged files appear to contain an Azure Cosmos DB connection string or account key.' -ForegroundColor Red
    Write-Host ''
    $secretFindings | ForEach-Object { Write-Host $_ }
    Write-Host ''
    Write-Host 'Remove the secret from the file, keep appsettings.json values blank, and use environment variables or Azure App Service settings instead.'
    exit 1
}

exit 0
