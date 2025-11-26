# Geeks.Online Cleanup Tool

## What is this?
This is a simple, automated maintenance tool designed to keep your computer running smoothly by removing temporary junk files.

## Features

### 1. Manual Cleanup (Run Now)
Instantly cleans up:
- **Temporary Files** (`%TEMP%`, `C:\Windows\Temp`)
- **Recycle Bin** (Empties it)
- **Prefetch Cache** (Helps system speed)
- **Windows Disk Cleanup** (Runs the built-in Windows tool silently)

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
