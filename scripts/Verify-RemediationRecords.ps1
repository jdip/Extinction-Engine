param(
    [string] $RemediationRoot
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($RemediationRoot)) {
    $RemediationRoot = Join-Path $repoRoot "docs/remediation"
}

$openDir = Join-Path $RemediationRoot "open"
$doneDir = Join-Path $RemediationRoot "done"
$errors = New-Object System.Collections.Generic.List[string]
$ids = @{}

foreach ($requiredDir in @($openDir, $doneDir)) {
    if (-not (Test-Path -LiteralPath $requiredDir -PathType Container)) {
        $errors.Add("Missing remediation directory: $requiredDir")
    }
}

if ($errors.Count -eq 0) {
    $files = @(Get-ChildItem -LiteralPath $openDir, $doneDir -Filter "*.md" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @("README.md", "TEMPLATE.md") })

    foreach ($file in $files) {
        $text = Get-Content -Raw -LiteralPath $file.FullName
        $fields = @{}

        foreach ($line in ($text -split "`r?`n")) {
            if ($line -match "^([A-Za-z_]+):\s*(.*)$") {
                $fields[$matches[1].ToLowerInvariant()] = $matches[2].Trim()
            }
        }

        foreach ($field in @("id", "status", "owner", "created", "source")) {
            if (-not $fields.ContainsKey($field) -or [string]::IsNullOrWhiteSpace($fields[$field])) {
                $errors.Add("$($file.FullName) is missing required field '$field'.")
            }
        }

        if ($fields.ContainsKey("id")) {
            $id = $fields["id"]
            if ($ids.ContainsKey($id)) {
                $errors.Add("Duplicate remediation id '$id' in $($file.FullName) and $($ids[$id]).")
            }
            else {
                $ids[$id] = $file.FullName
            }

            if ($file.BaseName -ne $id) {
                $errors.Add("$($file.FullName) filename must match remediation id '$id'.")
            }
        }

        $inOpen = $file.DirectoryName -eq $openDir
        $inDone = $file.DirectoryName -eq $doneDir
        if ($fields.ContainsKey("status")) {
            $status = $fields["status"].ToLowerInvariant()
            if ($inOpen -and $status -ne "open") {
                $errors.Add("$($file.FullName) is in open but status is '$status'.")
            }

            if ($inDone -and $status -notin @("done", "cancelled", "transferred")) {
                $errors.Add("$($file.FullName) is in done but status is '$status'.")
            }
        }

        if ($inDone -and (-not $fields.ContainsKey("closed") -or [string]::IsNullOrWhiteSpace($fields["closed"]))) {
            $errors.Add("$($file.FullName) is closed but missing 'closed'.")
        }
    }
}

if ($errors.Count -gt 0) {
    foreach ($errorMessage in $errors) {
        Write-Error $errorMessage
    }
    throw "Remediation record validation failed with $($errors.Count) error(s)."
}

Write-Host "Remediation record validation passed."
