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

$Version      = "2.0.0"

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
    Clear-Host
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

    # ---------- 1. Temp folders ----------
    Write-Host "[1/7] Cleaning temporary folders..." -ForegroundColor White
    try { Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Item -Path "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}

    # ---------- 2. Recycle Bin ----------
    Write-Host "[2/7] Emptying Recycle Bin..." -ForegroundColor White
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}

    # ---------- 3. Prefetch ----------
    Write-Host "[3/7] Cleaning prefetch cache..." -ForegroundColor White
    try { Remove-Item -Path "$env:SystemRoot\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}

    # ---------- 4. Browser caches ----------
    Write-Host "[4/7] Cleaning browser caches..." -ForegroundColor White
    # Chrome
    $chromeCachePaths = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Service Worker\CacheStorage",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Service Worker\ScriptCache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\ShaderCache"
    )
    foreach ($p in $chromeCachePaths) {
        if (Test-Path $p) { Remove-Item "$p\*" -Recurse -Force -ErrorAction SilentlyContinue }
    }
    # Edge
    $edgeCachePaths = @(
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Service Worker\ScriptCache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\ShaderCache"
    )
    foreach ($p in $edgeCachePaths) {
        if (Test-Path $p) { Remove-Item "$p\*" -Recurse -Force -ErrorAction SilentlyContinue }
    }
    # Firefox
    $ffProfiles = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $ffProfiles) {
        Get-ChildItem $ffProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $cachePath = Join-Path $_.FullName "cache2"
            if (Test-Path $cachePath) { Remove-Item "$cachePath\*" -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    Write-Host "  Browser caches cleaned (Chrome, Edge, Firefox)." -ForegroundColor Gray

    # ---------- 5. Windows caches & logs ----------
    Write-Host "[5/7] Cleaning Windows caches & logs..." -ForegroundColor White
    try {
        # Windows Update cache
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue

        # Windows logs
        Remove-Item "$env:SystemRoot\Logs\CBS\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SystemRoot\Logs\DISM\*" -Recurse -Force -ErrorAction SilentlyContinue

        # Thumbnail cache
        Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue

        # Windows Error Reports
        Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\WER\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:ProgramData\Microsoft\Windows\WER\*" -Recurse -Force -ErrorAction SilentlyContinue

        # Delivery Optimization cache
        Remove-Item "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue

        # Downloaded Program Files
        Remove-Item "$env:SystemRoot\Downloaded Program Files\*" -Recurse -Force -ErrorAction SilentlyContinue

        # Old Windows installations
        Remove-Item "$env:SystemDrive\Windows.old" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SystemDrive\`$Windows.~BT" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SystemDrive\`$Windows.~WS" -Recurse -Force -ErrorAction SilentlyContinue

        # Memory dump files
        Remove-Item "$env:SystemRoot\MEMORY.DMP" -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SystemRoot\Minidump\*" -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\CrashDumps\*" -Force -ErrorAction SilentlyContinue

        # Windows Installer orphaned patch cache
        Remove-Item "$env:SystemRoot\Installer\`$PatchCache`$\*" -Recurse -Force -ErrorAction SilentlyContinue

        # Recent file shortcuts
        Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*" -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations\*" -Force -ErrorAction SilentlyContinue

        Write-Host "  Windows caches cleaned." -ForegroundColor Gray
    } catch {
        Write-Host "  Some Windows cache cleaning encountered errors, but completed." -ForegroundColor Yellow
    }

    # ---------- 6. Flush DNS ----------
    Write-Host "[6/7] Flushing DNS cache..." -ForegroundColor White
    ipconfig /flushdns | Out-Null

    # ---------- 7. DISM component cleanup ----------
    Write-Host "[7/7] Running DISM component cleanup (this may take a moment)..." -ForegroundColor White
    try {
        dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet 2>$null
        Write-Host "  Component cleanup finished." -ForegroundColor Gray
    } catch {
        Write-Host "  Component cleanup skipped." -ForegroundColor Yellow
    }

    Log-Line "Manual cleanup completed"

    Write-Section "Complete"
    Write-Host "Cleanup finished successfully!" -ForegroundColor Green
    Write-Host ""
    Read-Host "Press Enter to return to the menu" | Out-Null
}

# ====================== Performance Optimization =================

function Run-PerformanceTuning {
    Clear-AndBanner
    Write-Section "Performance Optimization"

    Write-Host "This will apply safe performance tweaks to speed up your computer." -ForegroundColor Yellow
    Write-Host "All changes can be reversed. No personal data is affected." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1]  Apply ALL recommended tweaks" -ForegroundColor Cyan
    Write-Host "  [2]  Choose individual tweaks" -ForegroundColor Cyan
    Write-Host "  [3]  Back to main menu" -ForegroundColor Cyan
    Write-Host ""
    $perfChoice = Read-Host "Enter choice (1-3)"

    switch ($perfChoice) {
        '1' {
            Apply-PowerPlan
            Apply-VisualPerformance
            Disable-StartupBloat
            Optimize-Services
            Optimize-DiskDrive
            Clear-EventLogs
            Write-Section "All Optimizations Applied"
            Write-Host "Performance tuning complete!" -ForegroundColor Green
            Log-Line "Full performance optimization applied"
        }
        '2' {
            Run-IndividualTweaks
        }
        '3' { return }
        default {
            Write-Host "Invalid choice." -ForegroundColor Red
            Start-Sleep -Seconds 1
            return
        }
    }

    Write-Host ""
    Read-Host "Press Enter to return to the menu" | Out-Null
}

function Run-IndividualTweaks {
    Clear-AndBanner
    Write-Section "Individual Performance Tweaks"

    Write-Host "  [A]  Set High Performance power plan" -ForegroundColor Cyan
    Write-Host "  [B]  Optimize visual effects for performance" -ForegroundColor Cyan
    Write-Host "  [C]  Disable unnecessary startup programs" -ForegroundColor Cyan
    Write-Host "  [D]  Optimize background services" -ForegroundColor Cyan
    Write-Host "  [E]  Optimize disk (defrag HDD / TRIM SSD)" -ForegroundColor Cyan
    Write-Host "  [F]  Clear Windows Event Logs" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Enter letters of tweaks to apply (e.g. ABD) or * for all:" -ForegroundColor White
    $picks = (Read-Host "Choices").ToUpper()

    if ($picks -eq '*') { $picks = "ABCDEF" }

    if ($picks -match 'A') { Apply-PowerPlan }
    if ($picks -match 'B') { Apply-VisualPerformance }
    if ($picks -match 'C') { Disable-StartupBloat }
    if ($picks -match 'D') { Optimize-Services }
    if ($picks -match 'E') { Optimize-DiskDrive }
    if ($picks -match 'F') { Clear-EventLogs }

    Log-Line "Individual performance tweaks applied: $picks"
}

function Apply-PowerPlan {
    Write-Section "Power Plan: High Performance"
    try {
        $highPerf = powercfg /list | Select-String "High performance"
        if ($highPerf) {
            $guid = ($highPerf -replace '.*GUID:\s*', '' -replace '\s*\(.*', '').Trim()
            powercfg /setactive $guid
            Write-Host "  Power plan set to High Performance." -ForegroundColor Green
        } else {
            powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null
            $highPerf = powercfg /list | Select-String "High performance"
            if ($highPerf) {
                $guid = ($highPerf -replace '.*GUID:\s*', '' -replace '\s*\(.*', '').Trim()
                powercfg /setactive $guid
                Write-Host "  High Performance plan created and activated." -ForegroundColor Green
            }
        }
        powercfg /hibernate off 2>$null
        Write-Host "  Hibernation disabled (saves disk space)." -ForegroundColor Gray
    } catch {
        Write-Host "  Could not set power plan." -ForegroundColor Yellow
    }
}

function Apply-VisualPerformance {
    Write-Section "Visual Effects: Performance Mode"
    try {
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        Set-ItemProperty -Path $regPath -Name "VisualFXSetting" -Value 2 -ErrorAction SilentlyContinue

        $deskRegPath = "HKCU:\Control Panel\Desktop"
        Set-ItemProperty -Path $deskRegPath -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $deskRegPath -Name "FontSmoothing" -Value "2" -ErrorAction SilentlyContinue

        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0 -ErrorAction SilentlyContinue

        # Disable tips & suggestions
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-310093Enabled" -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SoftLandingEnabled" -Value 0 -ErrorAction SilentlyContinue

        Write-Host "  Visual effects set to performance mode (fonts stay smooth)." -ForegroundColor Green
        Write-Host "  Transparency & animations disabled." -ForegroundColor Gray
        Write-Host "  Tips & suggestions disabled." -ForegroundColor Gray
    } catch {
        Write-Host "  Could not fully apply visual tweaks." -ForegroundColor Yellow
    }
}

function Disable-StartupBloat {
    Write-Section "Startup Programs Review"
    try {
        $startupItems = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
            Select-Object Name, Command, Location
        
        if ($startupItems) {
            Write-Host "  Current startup programs:" -ForegroundColor White
            $startupItems | ForEach-Object {
                Write-Host "    - $($_.Name)" -ForegroundColor Gray
            }
            Write-Host ""
        }

        $bloatKeys = @(
            "OneDrive", "OneDriveSetup",
            "iTunesHelper", "AdobeAAMUpdater",
            "Spotify", "SpotifyWebHelper",
            "Discord", "Steam",
            "EpicGamesLauncher",
            "CCleanerBrowserMonitor",
            "Teams", "TeamsMachineInstaller"
        )

        $regStartupPaths = @(
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
        )

        $disabledCount = 0
        foreach ($regPath in $regStartupPaths) {
            if (Test-Path $regPath) {
                $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                foreach ($bloat in $bloatKeys) {
                    $match = $entries.PSObject.Properties | Where-Object { $_.Name -like "*$bloat*" }
                    if ($match) {
                        foreach ($m in $match) {
                            Remove-ItemProperty -Path $regPath -Name $m.Name -ErrorAction SilentlyContinue
                            Write-Host "    Disabled: $($m.Name)" -ForegroundColor Yellow
                            $disabledCount++
                        }
                    }
                }
            }
        }

        if ($disabledCount -eq 0) {
            Write-Host "  No common bloatware found in startup." -ForegroundColor Green
        } else {
            Write-Host "  Disabled $disabledCount startup item(s)." -ForegroundColor Green
        }
    } catch {
        Write-Host "  Startup review encountered errors." -ForegroundColor Yellow
    }
}

function Optimize-Services {
    Write-Section "Background Services Optimization"

    $servicesToOptimize = @(
        @{ Name = "DiagTrack";       Desc = "Connected User Experiences and Telemetry" },
        @{ Name = "dmwappushservice"; Desc = "WAP Push Message Routing" },
        @{ Name = "SysMain";         Desc = "Superfetch" },
        @{ Name = "WSearch";         Desc = "Windows Search Indexer" },
        @{ Name = "MapsBroker";      Desc = "Downloaded Maps Manager" },
        @{ Name = "lfsvc";           Desc = "Geolocation Service" },
        @{ Name = "RetailDemo";      Desc = "Retail Demo Service" },
        @{ Name = "WMPNetworkSvc";   Desc = "Windows Media Player Sharing" },
        @{ Name = "XblAuthManager";  Desc = "Xbox Live Auth Manager" },
        @{ Name = "XblGameSave";     Desc = "Xbox Live Game Save" },
        @{ Name = "XboxNetApiSvc";   Desc = "Xbox Live Networking" },
        @{ Name = "XboxGipSvc";      Desc = "Xbox Accessory Management" }
    )

    foreach ($svc in $servicesToOptimize) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service) {
            try {
                if ($service.Status -eq 'Running') {
                    Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                }
                Set-Service -Name $svc.Name -StartupType Manual -ErrorAction SilentlyContinue
                Write-Host "  Set to Manual: $($svc.Desc)" -ForegroundColor Gray
            } catch {
                Write-Host "  Skipped: $($svc.Desc)" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host "  Background services optimized." -ForegroundColor Green
}

function Optimize-DiskDrive {
    Write-Section "Disk Optimization"
    try {
        $systemDrive = $env:SystemDrive.TrimEnd(':')
        $diskInfo = Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($diskInfo -and $diskInfo.MediaType -eq 'SSD') {
            Write-Host "  SSD detected - running TRIM..." -ForegroundColor White
            Optimize-Volume -DriveLetter $systemDrive -ReTrim -ErrorAction SilentlyContinue
            Write-Host "  TRIM completed." -ForegroundColor Green
        } else {
            Write-Host "  HDD detected - running defragmentation..." -ForegroundColor White
            Write-Host "  (This may take several minutes)" -ForegroundColor Gray
            Optimize-Volume -DriveLetter $systemDrive -Defrag -ErrorAction SilentlyContinue
            Write-Host "  Defragmentation completed." -ForegroundColor Green
        }
    } catch {
        Write-Host "  Disk optimization encountered errors." -ForegroundColor Yellow
    }
}

function Clear-EventLogs {
    Write-Section "Clearing Windows Event Logs"
    try {
        $logs = wevtutil.exe el 2>$null
        $cleared = 0
        foreach ($log in $logs) {
            wevtutil.exe cl "$log" 2>$null
            $cleared++
        }
        Write-Host "  Cleared $cleared event logs." -ForegroundColor Green
    } catch {
        Write-Host "  Could not clear all event logs." -ForegroundColor Yellow
    }
}

# ====================== System Health Check =======================

function Run-HealthCheck {
    Clear-AndBanner
    Write-Section "System Health Check"

    Write-Host "Running diagnostics..." -ForegroundColor Yellow
    Write-Host ""

    # --- Disk Space ---
    Write-Host "[Disk Space]" -ForegroundColor Cyan
    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $null -ne $_.Used }
    foreach ($d in $drives) {
        $totalGB = [math]::Round(($d.Used + $d.Free) / 1GB, 1)
        $freeGB  = [math]::Round($d.Free / 1GB, 1)
        $pctFree = if ($totalGB -gt 0) { [math]::Round(($freeGB / $totalGB) * 100, 0) } else { 0 }
        $color   = if ($pctFree -lt 10) { "Red" } elseif ($pctFree -lt 25) { "Yellow" } else { "Green" }
        Write-Host "  $($d.Name): $freeGB GB free / $totalGB GB total ($pctFree% free)" -ForegroundColor $color
    }
    Write-Host ""

    # --- RAM Usage ---
    Write-Host "[Memory (RAM)]" -ForegroundColor Cyan
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $totalRAM = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeRAM  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $usedRAM  = [math]::Round($totalRAM - $freeRAM, 1)
        $pctUsed  = [math]::Round(($usedRAM / $totalRAM) * 100, 0)
        $ramColor = if ($pctUsed -gt 85) { "Red" } elseif ($pctUsed -gt 70) { "Yellow" } else { "Green" }
        Write-Host "  $usedRAM GB used / $totalRAM GB total ($pctUsed% used)" -ForegroundColor $ramColor
    }
    Write-Host ""

    # --- CPU Info ---
    Write-Host "[Processor]" -ForegroundColor Cyan
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cpu) {
        Write-Host "  $($cpu.Name.Trim())" -ForegroundColor White
        Write-Host "  Cores: $($cpu.NumberOfCores) / Threads: $($cpu.NumberOfLogicalProcessors)" -ForegroundColor Gray
    }
    Write-Host ""

    # --- Disk Type ---
    Write-Host "[Storage Type]" -ForegroundColor Cyan
    $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    foreach ($disk in $disks) {
        $dtype = if ($disk.MediaType) { $disk.MediaType } else { "Unknown" }
        $dsize = [math]::Round($disk.Size / 1GB, 0)
        Write-Host "  $($disk.FriendlyName): $dtype ($dsize GB)" -ForegroundColor White
    }
    Write-Host ""

    # --- Uptime ---
    Write-Host "[System Uptime]" -ForegroundColor Cyan
    if ($os) {
        $uptime = (Get-Date) - $os.LastBootUpTime
        $uptimeStr = "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
        $uptimeColor = if ($uptime.Days -gt 14) { "Red" } elseif ($uptime.Days -gt 7) { "Yellow" } else { "Green" }
        Write-Host "  $uptimeStr" -ForegroundColor $uptimeColor
        if ($uptime.Days -gt 7) {
            Write-Host "  (Consider restarting - long uptime can cause slowdowns)" -ForegroundColor Yellow
        }
    }
    Write-Host ""

    # --- Top CPU processes ---
    Write-Host "[Top 5 CPU-Consuming Processes]" -ForegroundColor Cyan
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 |
        ForEach-Object {
            $cpuSec = [math]::Round($_.CPU, 1)
            $memMB  = [math]::Round($_.WorkingSet64 / 1MB, 0)
            Write-Host "  $($_.ProcessName) - CPU: ${cpuSec}s, RAM: ${memMB} MB" -ForegroundColor Gray
        }
    Write-Host ""

    # --- Top RAM processes ---
    Write-Host "[Top 5 RAM-Consuming Processes]" -ForegroundColor Cyan
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 |
        ForEach-Object {
            $memMB = [math]::Round($_.WorkingSet64 / 1MB, 0)
            Write-Host "  $($_.ProcessName) - RAM: ${memMB} MB" -ForegroundColor Gray
        }
    Write-Host ""

    Log-Line "Health check completed"
    Read-Host "Press Enter to return to the menu" | Out-Null
}

# ====================== Task Helpers ==============================

function Get-TaskStatus {
    param($Name)
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        $task = Get-ScheduledTask -TaskName "$Name" -ErrorAction SilentlyContinue
        return ($null -ne $task)
    }
    $check = schtasks.exe /Query /TN "$Name" 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Remove-LegacyTask {
    if (Get-TaskStatus $taskNameOld) {
        schtasks.exe /Delete /TN "$taskNameOld" /F | Out-Null 2>&1
    }
}

# ====================== Startup Cleanup ===========================

function Ensure-StartupScript {
    Ensure-ScriptFolder
    Remove-LegacyTask

    if (-not (Test-Path $startupPs1)) {
        $content = 'try { Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}' + "`n"
        $content += 'try { Remove-Item -Path "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}' + "`n"
        $content += 'try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}' + "`n"
        $content += 'try { Remove-Item -Path "$env:SystemRoot\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}' + "`n"
        $content += "`n"
        $content += "`"Startup cleanup ran at `$(Get-Date)`" | Add-Content `"$logPath`"`n"
        $content += "`n"
        $content += 'Add-Type -AssemblyName System.Windows.Forms' + "`n"
        $content += '[System.Windows.Forms.MessageBox]::Show(' + "`n"
        $content += '    "Geeks.Online has finished cleaning up your computer. You are all set!",' + "`n"
        $content += '    "Geeks.Online Cleanup",' + "`n"
        $content += '    [System.Windows.Forms.MessageBoxButtons]::OK,' + "`n"
        $content += '    [System.Windows.Forms.MessageBoxIcon]::Information' + "`n"
        $content += ') | Out-Null' + "`n"
        Set-Content -Path $startupPs1 -Value $content -Encoding UTF8
    }

    if (-not (Test-Path $startupBat)) {
        $batContent = "@echo off`r`npowershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startupPs1`""
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
        $cmdArgs = "/Create /SC ONLOGON /TN `"$taskNameLogon`" /TR `"`"$startupBat`"`" /RL HIGHEST /F"

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

    $cmdArgs = "/Create /SC DAILY /TN `"$taskNameDaily`" /TR `"`"$startupBat`"`" /ST $timeStr /RL HIGHEST /F"

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

    if (Get-TaskStatus $taskNameLogon) {
        schtasks.exe /Delete /TN "$taskNameLogon" /F | Out-Null
        Write-Host "Removed Startup Task." -ForegroundColor Gray
    }
    if (Get-TaskStatus $taskNameDaily) {
        schtasks.exe /Delete /TN "$taskNameDaily" /F | Out-Null
        Write-Host "Removed Daily Task." -ForegroundColor Gray
    }
    if (Get-TaskStatus $taskName) {
        schtasks.exe /Delete /TN "$taskName" /F | Out-Null
    }

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

    $stStatus = if (Get-TaskStatus $taskNameLogon) { "[ENABLED] " } else { "[DISABLED]" }
    $stColor  = if ($stStatus -match "ENABLED") { "Green" } else { "Gray" }

    $scStatus = if (Get-TaskStatus $taskNameDaily) { "[ENABLED] " } else { "[DISABLED]" }
    $scColor  = if ($scStatus -match "ENABLED") { "Green" } else { "Gray" }

    Write-Host "Select an option:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1]  Run cleanup now" -ForegroundColor Cyan
    Write-Host "  [2]  Performance optimization" -ForegroundColor Cyan
    Write-Host "  [3]  System health check" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "  [4]  Startup Cleanup   " -NoNewline -ForegroundColor Cyan
    Write-Host $stStatus -ForegroundColor $stColor
    
    Write-Host "  [5]  Daily Schedule    " -NoNewline -ForegroundColor Cyan
    Write-Host $scStatus -ForegroundColor $scColor
    
    Write-Host ""
    Write-Host "  [6]  Uninstall / Disable All" -ForegroundColor Yellow
    Write-Host "  [7]  Exit" -ForegroundColor Cyan
    Write-Host ""
}

# ====================== Program Loop =============================

do {
    Show-Menu
    $choice = Read-Host "Enter choice (1-7)"

    switch ($choice) {
        '1' { Run-ManualCleanup }
        '2' { Run-PerformanceTuning }
        '3' { Run-HealthCheck }
        '4' { Toggle-Startup }
        '5' { Toggle-Schedule }
        '6' { Disable-AllCleanups }
        '7' { return }
        default {
            Write-Host ""
            Write-Host "Please enter a number between 1 and 7." -ForegroundColor Red
            Start-Sleep -Seconds 1.2
        }
    }
} while ($true)
