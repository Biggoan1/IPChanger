#requires -Version 5.1

<#
.SYNOPSIS
    Installer / uninstaller for the IPChanger Network Configuration Tool.
.DESCRIPTION
    Install   : copies the signed app exe into C:\Program Files\IPChanger and
                creates public Desktop and Start Menu shortcuts.
    Uninstall : removes the shortcuts and the install folder.

    Intended to run from an SCCM/MECM deployment. Run the matching Action:
        powershell.exe -ExecutionPolicy Bypass -File .\SetNet-Install.ps1 -Action Install
        powershell.exe -ExecutionPolicy Bypass -File .\SetNet-Install.ps1 -Action Uninstall
.NOTES
    Author: Network Operations
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Uninstall')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'

# ---- Settings (single source of truth) ------------------------------------
$AppName      = 'IPChanger'
$ExeName      = 'IPChanger.exe'
$ShortcutName = 'Network Configuration Tool.lnk'
$InstallDir   = Join-Path $env:ProgramFiles $AppName          # C:\Program Files\IPChanger
$IconLocation = "$env:SystemRoot\System32\Shell32.dll,17"

# Shortcut targets
$TargetExe         = Join-Path $InstallDir $ExeName
$DesktopShortcut   = Join-Path $env:PUBLIC "Desktop\$ShortcutName"
$StartMenuDir      = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
$StartMenuShortcut = Join-Path $StartMenuDir $ShortcutName

# ---- Logging ---------------------------------------------------------------
$LogDir  = Join-Path $env:ProgramData "$AppName\Logs"
$LogFile = ($MyInvocation.MyCommand.Name -replace '\.ps1$', '.log')
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
Start-Transcript -Path (Join-Path $LogDir $LogFile) -Append

function New-AppShortcut {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Target,
        [string]$WorkingDir,
        [string]$Icon
    )
    $wsh = New-Object -ComObject WScript.Shell
    $sc  = $wsh.CreateShortcut($Path)
    $sc.TargetPath = $Target
    if ($WorkingDir) { $sc.WorkingDirectory = $WorkingDir }
    if ($Icon)       { $sc.IconLocation     = $Icon }
    $sc.Save()
}

try {
    switch ($Action) {

        'Install' {
            Write-Host "Action=Install  ->  $InstallDir"

            New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null

            # Copy the app exe from the package folder next to this script.
            $sourceExe = Join-Path $PSScriptRoot $ExeName
            if (-not (Test-Path $sourceExe)) {
                throw "Source executable not found next to installer: $sourceExe"
            }
            Copy-Item -Path $sourceExe -Destination $InstallDir -Force -Verbose

            if (-not (Test-Path $TargetExe)) {
                throw "Install verification failed: $TargetExe is not present"
            }

            New-AppShortcut -Path $DesktopShortcut   -Target $TargetExe -WorkingDir $InstallDir -Icon $IconLocation
            New-AppShortcut -Path $StartMenuShortcut -Target $TargetExe -WorkingDir $InstallDir -Icon $IconLocation

            Write-Host 'Install Complete'
        }

        'Uninstall' {
            Write-Host 'Action=Uninstall'

            foreach ($lnk in @($DesktopShortcut, $StartMenuShortcut)) {
                if (Test-Path $lnk) { Remove-Item -Path $lnk -Force -Verbose }
            }

            if (Test-Path $InstallDir) {
                Remove-Item -Path $InstallDir -Recurse -Force -Verbose
            }

            Write-Host 'Uninstall Complete'
        }
    }
}
catch {
    Write-Error "FAILED: $($_.Exception.Message)"
    throw
}
finally {
    Stop-Transcript
}
