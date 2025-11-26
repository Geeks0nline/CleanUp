<#
    Geeks.Online - Debra Cleanup Tool
    Description:
      • Manual cleanup on demand (visible, with status)
      • Optional automatic cleanup at Windows logon (startup) with a popup
#>


# ====================== Self-Elevation & Setup ====================

# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell";
    $newProcess.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"";
    $newProcess.Verb = "runas";
    [System.Diagnostics.Process]::Start($newProcess);
    Exit
}

# Dynamic Path determination
if ($PSScriptRoot) {
    $scriptRoot = $PSScriptRoot
} else {
    $targetDrive = if ($env:SystemDrive) { $env:SystemDrive } else { "C:" }
    $scriptRoot  = "$targetDrive\Scripts"
}

$taskName         = "Geeks.Online Startup Cleanup"
$startupPs1       = Join-Path $scriptRoot "StartupClean.ps1"
$startupBat       = Join-Path $scriptRoot "StartupClean.bat"
$logPath          = Join-Path $scriptRoot "DailyClean.log"

# ====================== ASCII BANNER ===============================

$Banner = @"
                 ===============================================
                 =                                             =
                 =             Geeks.Online Cleanup            =
                 =                                             =
                 =         1-800-Geeks.Online (Support)        =
                 = 24x7 Remote Computer Repair & Onsite Service=
                 =                                             =
                 ===============================================

"@

# ====================== UI Helpers ================================

function Ensure-ScriptFolder {
    if (-not (Test-Path $scriptRoot)) {
        New-Item -Path $scriptRoot -ItemType Directory -Force | Out-Null
    }
}

function Clear-AndBanner {
    cls
    Write-Host $Banner -ForegroundColor Cyan
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "--------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host "  $Text" -ForegroundColor DarkCyan
    Write-Host "--------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host ""
}

function Log-Line {
    param([string]$Text)
    Ensure-ScriptFolder
    "$Text  [$([DateTime]::Now)]" | Add-Content $logPath
}

# ====================== Manual Cleanup ============================

function Run-ManualCleanup {
    Clear-AndBanner
    Write-Section "Manual Cleanup"

    Write-Host "This will remove temporary junk files and empty the Recycle Bin." -ForegroundColor Yellow
    Write-Host "Your personal files will NOT be touched." -ForegroundColor Yellow
    Write-Host ""

    Write-Section "Cleanup in progress"

    Write-Host "[1/4] Cleaning temporary folders..." -ForegroundColor White
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "[2/4] Emptying Recycle Bin..." -ForegroundColor White
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}

    Write-Host "[3/4] Cleaning prefetch cache..." -ForegroundColor White
    Remove-Item -Path "$env:SystemRoot\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "[4/4] Running Windows Disk Cleanup silently..." -ForegroundColor White
    try {
        Start-Process cleanmgr.exe -ArgumentList "/VERYLOWDISK","/d","C" -Wait -WindowStyle Hidden
        Write-Host "Disk Cleanup finished." -ForegroundColor Green
    } catch {
        Write-Host "Disk Cleanup failed, but the rest completed." -ForegroundColor Red
    }

    Log-Line "Manual cleanup completed"

    Write-Section "Complete"
    Write-Host "Cleanup finished successfully!" -ForegroundColor Green
    Write-Host ""
    Read-Host "Press Enter to return to the menu" | Out-Null
}

# ====================== Startup Cleanup ===========================

function Ensure-StartupScript {
    Ensure-ScriptFolder

    if (-not (Test-Path $startupPs1)) {
        # Dynamically generate the script with correct paths
        $content = @"
Remove-Item -Path "`$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "`$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
Remove-Item -Path "`$env:SystemRoot\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue

"Startup cleanup ran at $(Get-Date)" | Add-Content "$scriptRoot\DailyClean.log"

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show(
    "Geeks.Online has finished cleaning up your computer. You are all set!",
    "Geeks.Online Cleanup",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
) | Out-Null
"@ 
        Set-Content -Path $startupPs1 -Value $content -Encoding UTF8
    }

    if (-not (Test-Path $startupBat)) {
        $batContent = @"
@echo off
powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "$startupPs1"
"@ 
        Set-Content -Path $startupBat -Value $batContent -Encoding ASCII
    }
}

function Enable-StartupCleanup {
    Clear-AndBanner
    Write-Section "Enable Automatic Cleanup at Startup"

    Ensure-StartupScript
    schtasks.exe /Delete /TN "$taskName" /F | Out-Null 2>&1

    $result = schtasks.exe /Create `
        /SC ONLOGON `
        /TN "$taskName" `
        /TR "`"$startupBat`"" `
        /RL HIGHEST `
        /F 2>&1

    if ($LASTEXITCODE -eq 0) {
        Log-Line "Startup cleanup ENABLED"
        Write-Host "Startup cleanup has been ENABLED." -ForegroundColor Green
        Write-Host "It will automatically run each time the computer logs in." -ForegroundColor Green
    } else {
        Write-Host "Error enabling startup cleanup:" -ForegroundColor Red
        Write-Host $result -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "Press Enter to return to the menu" | Out-Null
}

function Disable-StartupCleanup {
    Clear-AndBanner
    Write-Section "Disable Automatic Cleanup at Startup"

    $result = schtasks.exe /Delete /TN "$taskName" /F 2>&1

    if ($LASTEXITCODE -eq 0) {
        Log-Line "Startup cleanup DISABLED"
        Write-Host "Startup cleanup has been disabled." -ForegroundColor Yellow
    } else {
        Write-Host "Error disabling startup cleanup:" -ForegroundColor Red
        Write-Host $result -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "Press Enter to return to the menu" | Out-Null
}

# ====================== Main Menu ================================

function Show-Menu {
    Clear-AndBanner

    Write-Host "Select an option:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1]  Run cleanup now" -ForegroundColor Cyan
    Write-Host "  [2]  Turn ON cleanup at startup" -ForegroundColor Cyan
    Write-Host "  [3]  Turn OFF cleanup at startup" -ForegroundColor Cyan
    Write-Host "  [4]  Exit" -ForegroundColor Cyan
    Write-Host ""
}

# ====================== Program Loop =============================

do {
    Show-Menu
    $choice = Read-Host "Enter choice (1-4)"

    switch ($choice) {
        '1' { Run-ManualCleanup }
        '2' { Enable-StartupCleanup }
        '3' { Disable-StartupCleanup }
        '4' { break }
        default {
            Write-Host ""
            Write-Host "Please enter a number between 1 and 4." -ForegroundColor Red
            Start-Sleep -Seconds 1.2
        }
    }
} while ($true)
