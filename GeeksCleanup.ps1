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

$Version      = "1.2.6"

$taskNameOld  = "Geeks.Online Startup Cleanup"
$taskNameLogon = "Geeks.Online Cleanup (Startup)"
$taskNameDaily = "Geeks.Online Cleanup (Daily)"

# ====================== ASCII BANNER ===============================

$Banner = @"
                 ===============================================
                 =                                             =
                 =             Geeks.Online Cleanup            =
                 =                  v$Version                    =
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


# ====================== Task Helpers ==============================

function Get-TaskStatus {
    param($Name)
    $check = schtasks.exe /Query /TN "$Name" 2>$null
    if ($LASTEXITCODE -eq 0) { return $true }
    return $false
}

function Remove-LegacyTask {
    # Remove the old single-task if it exists
    if (Get-TaskStatus $taskNameOld) {
        schtasks.exe /Delete /TN "$taskNameOld" /F | Out-Null 2>&1
    }
}

# ====================== Startup Cleanup ===========================

function Ensure-StartupScript {
    Ensure-ScriptFolder
    Remove-LegacyTask

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

function Toggle-Startup {
    Clear-AndBanner
    Ensure-StartupScript
    
    $exists = Get-TaskStatus $taskNameLogon

    if ($exists) {
        Write-Section "Disabling Startup Cleanup..."
        schtasks.exe /Delete /TN "$taskNameLogon" /F | Out-Null 2>&1
        Write-Host "Startup cleanup has been DISABLED." -ForegroundColor Yellow
    } else {
        Write-Section "Enabling Startup Cleanup..."
        schtasks.exe /Delete /TN "$taskNameLogon" /F | Out-Null 2>&1 # Clean slate
    # Use cmd /c to properly handle the path with spaces/quotes
    $cmdArgs = "/Create /SC ONLOGON /TN `"$taskNameLogon`" /TR `"'C:\Scripts\StartupClean.bat'`" /RL HIGHEST /F"
    
    # If path is dynamic (not C:\Scripts), we need to handle it carefully
    if ($scriptRoot -ne "C:\Scripts") {
         $cmdArgs = "/Create /SC ONLOGON /TN `"$taskNameLogon`" /TR `"`"$startupBat`"`" /RL HIGHEST /F"
    }

    Start-Process schtasks.exe -ArgumentList $cmdArgs -Wait -NoNewWindow
    
    if ($LASTEXITCODE -eq 0) {
         Write-Host "Startup cleanup has been ENABLED." -ForegroundColor Green
    } else {
         Write-Host "Error: Could not create task." -ForegroundColor Red
    }
    }
    Write-Host ""
    Read-Host "Press Enter to return to the menu" | Out-Null
}

function Toggle-Schedule {
    Clear-AndBanner
    Ensure-StartupScript
    
    $exists = Get-TaskStatus $taskNameDaily

    if ($exists) {
        Write-Section "Disabling Scheduled Cleanup..."
        schtasks.exe /Delete /TN "$taskNameDaily" /F | Out-Null 2>&1
        Write-Host "Scheduled daily cleanup has been DISABLED." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to return to the menu" | Out-Null
        return
    }

    # Enable Logic
    Write-Section "Enable Daily Cleanup"
    Write-Host "Enter the time for daily cleanup (e.g. 7:00 PM, 14:30)" -ForegroundColor White
    Write-Host "Current Schedule: DISABLED" -ForegroundColor Yellow
    Write-Host ""

    $validTime = $false
    $timeStr = ""
    
    while (-not $validTime) {
        $userInput = Read-Host "Enter Time"
        if ([string]::IsNullOrWhiteSpace($userInput)) { return }
        
        try {
            $dt = [DateTime]::Parse($userInput)
            $timeStr = $dt.ToString("HH:mm")
            $displayStr = $dt.ToString("h:mm tt")
            $validTime = $true
        } catch {
            Write-Host "Invalid format. Try again (e.g. 7:00 PM)" -ForegroundColor Red
        }
    }

    schtasks.exe /Delete /TN "$taskNameDaily" /F | Out-Null 2>&1
    
    $cmdArgs = "/Create /SC DAILY /TN `"$taskNameDaily`" /TR `"'C:\Scripts\StartupClean.bat'`" /ST $timeStr /RL HIGHEST /F"
    if ($scriptRoot -ne "C:\Scripts") {
         $cmdArgs = "/Create /SC DAILY /TN `"$taskNameDaily`" /TR `"`"$startupBat`"`" /ST $timeStr /RL HIGHEST /F"
    }

    Start-Process schtasks.exe -ArgumentList $cmdArgs -Wait -NoNewWindow

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Success! Cleanup scheduled for $displayStr daily." -ForegroundColor Green
    } else {
        Write-Host "Error: Could not create schedule." -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "Press Enter to return to the menu" | Out-Null
}


# ====================== Main Menu ================================

function Show-Menu {
    Clear-AndBanner

    # Get dynamic status
    $stStatus = if (Get-TaskStatus $taskNameLogon) { "[ENABLED] " } else { "[DISABLED]" }
    $stColor  = if ($stStatus -match "ENABLED") { "Green" } else { "Gray" }

    $scStatus = if (Get-TaskStatus $taskNameDaily) { "[ENABLED] " } else { "[DISABLED]" }
    $scColor  = if ($scStatus -match "ENABLED") { "Green" } else { "Gray" }

    Write-Host "Select an option:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1]  Run cleanup now" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "  [2]  Startup Cleanup   " -NoNewline -ForegroundColor Cyan
    Write-Host $stStatus -ForegroundColor $stColor
    
    Write-Host "  [3]  Daily Schedule Clean Up   " -NoNewline -ForegroundColor Cyan
    Write-Host $scStatus -ForegroundColor $scColor
    
    Write-Host ""
    Write-Host "  [4]  Exit" -ForegroundColor Cyan
    Write-Host ""
}

# ====================== Program Loop =============================

do {
    Show-Menu
    $choice = Read-Host "Enter choice (1-4)"

    switch ($choice) {
        '1' { Run-ManualCleanup }
        '2' { Toggle-Startup }
        '3' { Toggle-Schedule }
        '4' { break }
        default {
            Write-Host ""
            Write-Host "Please enter a number between 1 and 4." -ForegroundColor Red
            Start-Sleep -Seconds 1.2
        }
    }
} while ($true)
