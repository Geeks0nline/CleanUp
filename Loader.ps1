# ===========================
#  Geeks.Online Auto-Updater
# ===========================

$repoBase   = "https://raw.githubusercontent.com/GeeksOnline/CleanUp/main"
$remoteVer  = "$repoBase/version.txt"
$remotePs1  = "$repoBase/GeeksCleanup.ps1"

$localDir   = "C:\Scripts"
$localPs1   = Join-Path $localDir "GeeksCleanup.ps1"
$localVer   = Join-Path $localDir "cleanup-version.txt"

# Ensure directory exists
if (-not (Test-Path $localDir)) {
    New-Item -Path $localDir -ItemType Directory -Force | Out-Null
}

# Get local version
function Get-LocalVersion {
    if (Test-Path $localVer) {
        return (Get-Content $localVer -Raw).Trim()
    }
    return "0.0.0"
}

# Get GitHub version
function Get-RemoteVersion {
    try {
        return (Invoke-WebRequest -Uri $remoteVer -UseBasicParsing -TimeoutSec 10).Content.Trim()
    } catch { return $null }
}

function Update-IfNeeded {

    $current  = [version](Get-LocalVersion)
    $latestStr = Get-RemoteVersion
    if (-not $latestStr) {
        Write-Host "Could not check for updates. Using local version." -ForegroundColor Yellow
        return
    }

    $latest = [version]$latestStr

    if ($latest -gt $current) {
        Write-Host "Updating to version $latest..."
        try {
            $script = (Invoke-WebRequest -Uri $remotePs1 -UseBasicParsing -TimeoutSec 10).Content
            Set-Content -Path $localPs1 -Value $script -Encoding UTF8
            Set-Content -Path $localVer -Value $latestStr -Encoding ASCII
            Write-Host "Update complete!" -ForegroundColor Green
        } catch {
            Write-Host "Failed to download update." -ForegroundColor Red
        }
    }
}

Update-IfNeeded

# Run latest script
if (Test-Path $localPs1) {
    . $localPs1
} else {
    Write-Host "No cleanup script available." -ForegroundColor Red
    Read-Host "Press Enter to exit"
}
