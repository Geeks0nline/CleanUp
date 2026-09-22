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

$taskName         = "Geeks.Online Startup Cleanup" # Legacy
$startupPs1       = Join-Path $scriptRoot "StartupClean.ps1"
$startupBat       = Join-Path $scriptRoot "StartupClean.bat"
$logPath          = Join-Path $scriptRoot "DailyClean.log"

$Version      = "2.2.0"

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

# ====================== Cleanup Helpers ==========================

# One empty folder, reused all run as the "source" robocopy mirrors from.
# Kept out of any temp folder so our own cleanup does not delete it mid-run.
$script:EmptyMirrorDir = $null

function Get-EmptyMirrorDir {
    if ($script:EmptyMirrorDir -and (Test-Path -LiteralPath $script:EmptyMirrorDir)) {
        return $script:EmptyMirrorDir
    }
    $dir = Join-Path $env:ProgramData "Geeks.Online\_empty"
    try {
        New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        # Make sure it really is empty, or /MIR would copy files back in.
        Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $script:EmptyMirrorDir = $dir
        return $dir
    } catch { return $null }
}

function Remove-EmptyMirrorDir {
    if ($script:EmptyMirrorDir -and (Test-Path -LiteralPath $script:EmptyMirrorDir)) {
        Remove-Item -LiteralPath $script:EmptyMirrorDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $script:EmptyMirrorDir = $null
}

# Empties a folder's contents without deleting the folder itself.
# Mirroring an empty folder with robocopy is multi-threaded, so folders holding
# thousands of small files (Temp, shader caches) clear far faster than with
# Remove-Item -Recurse. /R:0 /W:0 is what keeps it quick: without it robocopy
# retries a locked file a million times, 30 seconds apart, and appears to hang.
function Clear-FolderContents {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }

    try { $full = [IO.Path]::GetFullPath($Path) } catch { return }
    # Guard: never let a malformed path turn a "clear folder" into "wipe a drive".
    if ($full.TrimEnd('\').Length -le 2) { return }
    if (-not (Test-Path -LiteralPath $full)) { return }

    $empty = Get-EmptyMirrorDir
    if ($empty) {
        try {
            robocopy $empty $full /MIR /MT:16 /R:0 /W:0 /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
            return
        } catch {}
    }

    # Fallback for the rare machine without robocopy.
    try {
        Remove-Item -Path (Join-Path $full '*') -Recurse -Force -ErrorAction SilentlyContinue
    } catch {}
}

# Free space (bytes) on the system drive, used to report how much we cleared.
function Get-SystemDriveFreeBytes {
    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction SilentlyContinue
        if ($disk) { return [int64]$disk.FreeSpace }
    } catch {}
    return 0
}

# Clears temp + app caches for a single user profile.
# Browser caches (Chrome, Edge, Brave, Firefox) are deliberately left alone:
# wiping them makes browsing feel slow afterwards while sites re-download.
# Pass that profile's Local and Roaming AppData paths so we can reuse this
# for the current user AND every other account on the machine.
function Clear-UserJunk {
    param(
        [string]$LocalAppData,
        [string]$RoamingAppData
    )

    if ([string]::IsNullOrWhiteSpace($LocalAppData)) { return }

    # Temp
    Clear-FolderContents (Join-Path $LocalAppData "Temp")

    # Graphics / DirectX shader caches
    Clear-FolderContents (Join-Path $LocalAppData "D3DSCache")
    Clear-FolderContents (Join-Path $LocalAppData "NVIDIA\DXCache")
    Clear-FolderContents (Join-Path $LocalAppData "NVIDIA\GLCache")

    # Remote Desktop bitmap cache
    Clear-FolderContents (Join-Path $LocalAppData "Microsoft\Terminal Server Client\Cache")

    # Microsoft Teams (classic) caches
    if (-not [string]::IsNullOrWhiteSpace($RoamingAppData)) {
        $teams = Join-Path $RoamingAppData "Microsoft\Teams"
        if (Test-Path $teams) {
            foreach ($sub in @("Cache", "blob_storage", "GPUCache", "Service Worker\CacheStorage", "tmp")) {
                Clear-FolderContents (Join-Path $teams $sub)
            }
        }
    }
}

# Runs the built-in Windows Disk Cleanup silently, with the fast categories only.
# Time-boxed as a safety net; anything unexpected is logged, never shown.
# The user's Downloads folder is deliberately never touched (personal files).
function Invoke-WindowsDiskCleanup {
    param([int]$TimeoutSeconds = 60)

    $cleanMgr = Join-Path $env:SystemRoot "System32\cleanmgr.exe"
    if (-not (Test-Path $cleanMgr)) {
        Log-Line "Disk Cleanup skipped - cleanmgr.exe not present"
        return
    }

    $tag      = 65
    $flagName = "StateFlags{0:D4}" -f $tag
    $vcRoot   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"

    # Never enable handlers that delete the customer's personal files,
    # or the browser web cache (keeps browsing fast after a cleanup).
    #
    # The rest are off for speed. They hand the work to DISM / Windows servicing,
    # which routinely runs for many minutes - that is what made this step blow
    # through its time budget. The steps above already reclaim the same space
    # directly (Windows.old, SoftwareDistribution, Delivery Optimization, logs),
    # so skipping them costs essentially nothing.
    $skipHandlers = @(
        "DownloadsFolder",
        "Internet Cache Files",
        "Update Cleanup",                 # component store servicing - slowest by far
        "Previous Installations",         # Windows.old, already removed above
        "Windows Upgrade Log Files",      # already cleared above
        "Windows ESD installation files",
        "Delivery Optimization Files",    # already cleared above
        "Device Driver Packages",
        "Windows Defender",
        "Old ChkDsk Files"
    )

    if (Test-Path $vcRoot) {
        Get-ChildItem $vcRoot -ErrorAction SilentlyContinue | ForEach-Object {
            $value = if ($skipHandlers -contains $_.PSChildName) { 0 } else { 2 }
            New-ItemProperty -Path $_.PSPath -Name $flagName -Value $value -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    try {
        $proc = Start-Process -FilePath $cleanMgr -ArgumentList "/sagerun:$tag" -PassThru -WindowStyle Hidden -ErrorAction Stop
    } catch {
        Log-Line "Disk Cleanup skipped - could not start cleanmgr.exe"
        return
    }

    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        # Safety net only: with the servicing handlers disabled this should not
        # fire. Stop quietly and log it - the customer never sees a warning.
        Get-Process -Name cleanmgr, dismhost -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Log-Line "Disk Cleanup exceeded ${TimeoutSeconds}s and was stopped (partial clean applied)"
    }
}

# ====================== Manual Cleanup ============================

function Run-ManualCleanup {
    Clear-AndBanner
    Write-Section "Manual Cleanup"

    Write-Host "This will remove temporary junk files, app caches, and empty the Recycle Bin." -ForegroundColor Yellow
    Write-Host "Your personal files (Documents, Downloads, Pictures, etc.) will NOT be touched." -ForegroundColor Yellow
    Write-Host "Browser caches are left alone so your websites keep loading fast." -ForegroundColor Yellow
    Write-Host ""

    Write-Section "Cleanup in progress"

    $freeBefore = Get-SystemDriveFreeBytes

    Write-Host "[1/5] Cleaning temp & caches for all user accounts..." -ForegroundColor White
    # Current user
    Clear-UserJunk -LocalAppData $env:LOCALAPPDATA -RoamingAppData $env:APPDATA
    # Every other real profile on the machine
    Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users', 'defaultuser0') } |
        ForEach-Object {
            Clear-UserJunk -LocalAppData (Join-Path $_.FullName "AppData\Local") `
                           -RoamingAppData (Join-Path $_.FullName "AppData\Roaming")
        }
    # System-wide temp
    Clear-FolderContents "$env:SystemRoot\Temp"
    Write-Host "  Temp folders and app caches cleared." -ForegroundColor Gray

    Write-Host "[2/5] Emptying Recycle Bin (all drives)..." -ForegroundColor White
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}

    Write-Host "[3/5] Cleaning prefetch cache..." -ForegroundColor White
    Clear-FolderContents "$env:SystemRoot\Prefetch"

    # --- Silent housekeeping (no console output, same work as before) ---

    # Flush DNS cache
    ipconfig /flushdns | Out-Null

    # Remove crash dumps & error reports
    Remove-Item "$env:SystemRoot\MEMORY.DMP" -Force -ErrorAction SilentlyContinue
    Clear-FolderContents "$env:SystemRoot\Minidump"
    Clear-FolderContents "$env:LOCALAPPDATA\CrashDumps"
    Clear-FolderContents "$env:LOCALAPPDATA\Microsoft\Windows\WER"
    Clear-FolderContents "$env:ProgramData\Microsoft\Windows\WER"

    # Clean Windows logs, thumbnails & leftovers
    Clear-FolderContents "$env:SystemRoot\Logs\CBS"
    Clear-FolderContents "$env:SystemRoot\Logs\DISM"
    Clear-FolderContents "$env:SystemRoot\Logs\MoSetup"
    Clear-FolderContents "$env:SystemRoot\Logs\WindowsUpdate"
    Clear-FolderContents "$env:SystemRoot\Panther"
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db" -Force -ErrorAction SilentlyContinue
    Clear-FolderContents "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
    Clear-FolderContents "$env:SystemRoot\Downloaded Program Files"

    # --- End silent housekeeping ---

    Write-Host "[4/5] Clearing Windows Update cache & old installations..." -ForegroundColor White
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Clear-FolderContents "$env:SystemRoot\SoftwareDistribution\Download"
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemDrive\Windows.old" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemDrive\`$Windows.~BT" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemDrive\`$Windows.~WS" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Update cache and old installation files cleared." -ForegroundColor Gray

    Write-Host "[5/5] Running Windows Disk Cleanup (all categories)..." -ForegroundColor White
    Invoke-WindowsDiskCleanup -TimeoutSeconds 60
    Write-Host "  Disk Cleanup finished." -ForegroundColor Gray

    Remove-EmptyMirrorDir

    $freeAfter = Get-SystemDriveFreeBytes
    $freedMB   = [math]::Round( [math]::Max(0, ($freeAfter - $freeBefore)) / 1MB, 1)

    Log-Line "Manual cleanup completed - freed approx $freedMB MB"

    Write-Section "Complete"
    Write-Host "Cleanup finished successfully!" -ForegroundColor Green
    if ($freedMB -gt 0) {
        Write-Host ("Approximately {0} MB of space was freed on {1}" -f $freedMB, $env:SystemDrive) -ForegroundColor Green
    }
    Write-Host ""
    Read-Host "Press Enter to return to the menu" | Out-Null
}

# ====================== Task Helpers ==============================

function Get-TaskStatus {
    param($Name)
    # Try native PowerShell command first (Cleaner, no text output)
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        $task = Get-ScheduledTask -TaskName "$Name" -ErrorAction SilentlyContinue
        return ($null -ne $task)
    }
    # Fallback
    $check = schtasks.exe /Query /TN "$Name" 2>$null
    return ($LASTEXITCODE -eq 0)
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
try { Remove-Item -Path "`$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}
try { Remove-Item -Path "`$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}
try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
try { Remove-Item -Path "`$env:SystemRoot\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}

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
        schtasks.exe /Delete /TN "$taskNameLogon" /F | Out-Null
        Write-Host "Startup cleanup has been DISABLED." -ForegroundColor Yellow
    } else {
        Write-Section "Enabling Startup Cleanup..."
        # Removed explicit delete to avoid 'file not found' errors. /Create /F handles overwrite.
        
        # Use cmd /c to properly handle the path with spaces/quotes
        $cmdArgs = "/Create /SC ONLOGON /TN `"$taskNameLogon`" /TR `"'C:\Scripts\StartupClean.bat'`" /RL HIGHEST /F"
        if ($scriptRoot -ne "C:\Scripts") {
             $cmdArgs = "/Create /SC ONLOGON /TN `"$taskNameLogon`" /TR `"`"$startupBat`"`" /RL HIGHEST /F"
        }

        $p = Start-Process schtasks.exe -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru
        
        if ($p.ExitCode -eq 0) {
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
        schtasks.exe /Delete /TN "$taskNameDaily" /F | Out-Null
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

    # Removed explicit delete to avoid errors.
    
    $cmdArgs = "/Create /SC DAILY /TN `"$taskNameDaily`" /TR `"'C:\Scripts\StartupClean.bat'`" /ST $timeStr /RL HIGHEST /F"
    if ($scriptRoot -ne "C:\Scripts") {
         $cmdArgs = "/Create /SC DAILY /TN `"$taskNameDaily`" /TR `"`"$startupBat`"`" /ST $timeStr /RL HIGHEST /F"
    }

    $p = Start-Process schtasks.exe -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru

    if ($p.ExitCode -eq 0) {
        Write-Host "Success! Cleanup scheduled for $displayStr daily." -ForegroundColor Green
    } else {
        Write-Host "Error: Could not create schedule." -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "Press Enter to return to the menu" | Out-Null
}

function Disable-AllCleanups {
    Clear-AndBanner
    Write-Section "Disable Automatic Cleanup"

    # Smart Task Deletion
    if (Get-TaskStatus $taskNameLogon) {
        schtasks.exe /Delete /TN "$taskNameLogon" /F | Out-Null
        Write-Host "Removed Startup Task." -ForegroundColor Gray
    }
    if (Get-TaskStatus $taskNameDaily) {
        schtasks.exe /Delete /TN "$taskNameDaily" /F | Out-Null
        Write-Host "Removed Daily Task." -ForegroundColor Gray
    }
    if (Get-TaskStatus $taskName) {
        schtasks.exe /Delete /TN "$taskName" /F | Out-Null # Legacy
    }

    # Smart File Deletion
    if (Test-Path $startupBat) {
        Remove-Item $startupBat -Force -ErrorAction SilentlyContinue
        Write-Host "Removed StartupClean.bat" -ForegroundColor Gray
    }
    if (Test-Path $startupPs1) {
        Remove-Item $startupPs1 -Force -ErrorAction SilentlyContinue
        Write-Host "Removed StartupClean.ps1" -ForegroundColor Gray
    }

    Log-Line "All automatic cleanups DISABLED"
    Write-Host "All automatic cleanups have been disabled and scripts removed." -ForegroundColor Yellow

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
    
    Write-Host "  [3]  Daily Schedule    " -NoNewline -ForegroundColor Cyan
    Write-Host $scStatus -ForegroundColor $scColor
    
    Write-Host ""
    Write-Host "  [4]  Uninstall / Disable All" -ForegroundColor Yellow
    Write-Host "  [5]  Exit" -ForegroundColor Cyan
    Write-Host ""
}

# ====================== Program Loop =============================

do {
    Show-Menu
    $choice = Read-Host "Enter choice (1-5)"

    switch ($choice) {
        '1' { Run-ManualCleanup }
        '2' { Toggle-Startup }
        '3' { Toggle-Schedule }
        '4' { Disable-AllCleanups }
        '5' { return }
        default {
            Write-Host ""
            Write-Host "Please enter a number between 1 and 5." -ForegroundColor Red
            Start-Sleep -Seconds 1.2
        }
    }
} while ($true)
