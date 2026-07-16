# Geeks.Online Cleanup Tool

## What is this?
This is a simple, automated maintenance tool designed to keep your computer running smoothly by removing temporary junk files.

## Features

### 1. Manual Cleanup (Run Now)
A fast (typically 1-3 minute) cleanup that clears:
- **Temporary Files** for **every user account** (`%TEMP%`, `C:\Windows\Temp`)
- **Browser Caches** (Chrome, Edge, Brave, Firefox) for every account
- **App Caches** (Microsoft Teams, Remote Desktop, DirectX/NVIDIA shader caches, IE/legacy web cache)
- **Recycle Bin** (Empties it on all drives)
- **Prefetch Cache** (Helps system speed)
- **DNS Cache** (Flushes it)
- **Crash Dumps & Error Reports** (`MEMORY.DMP`, minidumps, WER)
- **Windows Logs, Thumbnails & Leftovers** (CBS/DISM/setup logs, Delivery Optimization, thumbnail/icon cache)
- **Windows Update Cache & Old Installations** (`SoftwareDistribution`, `Windows.old`)
- **Windows Disk Cleanup** — actually runs the built-in `cleanmgr` tool with **all cleanup categories** enabled, silently and time-boxed so it never runs long

> Personal files (Documents, Downloads, Pictures, etc.) are never touched — the Downloads-folder cleanup handler is explicitly disabled.

At the end it reports approximately how much disk space was freed.

### 2. Startup Cleanup
- Enables a background task that runs **every time you log in**.
- It silently cleans temporary files and the Recycle Bin.
- Shows a small popup notification when finished.

### 3. Daily Scheduled Cleanup
- Allows you to set a specific time (e.g., `7:00 PM`) for the cleanup to run automatically every day.
- Runs silently in the background.

### 4. Uninstall / Disable All
- Completely removes all scheduled tasks and cleanup scripts from the system.
- Useful if you want to stop all automatic maintenance.

## How to Use
1. Download and run `DailyCleanup.exe`.
2. Choose an option from the menu by typing the number (1-5) and pressing Enter.
3. To exit, select option **[5]**.

## Requirements
- Windows 10 or Windows 11
- Internet connection (to fetch the latest version)
