#requires -Version 5.1

<#
.SYNOPSIS
    Builds (and optionally signs) the IPChanger app exe from Set-NetworkConfig.ps1 with ps2exe.
.DESCRIPTION
    1. Ensures the ps2exe module is available (installs to CurrentUser if missing).
    2. Compiles the GUI script to a windowed (no-console) exe with version metadata.
    3. Optionally Authenticode-signs the exe AND the installer with a code-signing
       certificate, timestamped against a public TSA.

    The build machine needs the ps2exe module and, for signing, your code-signing
    certificate in Cert:\CurrentUser\My (or LocalMachine\My).
.PARAMETER Sign
    Sign the exe and installer after compiling. Off by default so the build works
    on machines without the cert.
.PARAMETER CertThumbprint
    Thumbprint of the signing cert. If omitted, the newest code-signing cert in the
    certificate store is used.
.PARAMETER Version
    Version stamped into the exe (e.g. 4.0.0.0).
.EXAMPLE
    .\build.ps1
    .\build.ps1 -Sign
    .\build.ps1 -Sign -CertThumbprint AABBCC...  -Version 4.0.1.0
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$OutputExe,
    [string]$Installer,
    [string]$Version       = '4.0.0.0',
    [switch]$Sign,
    [string]$CertThumbprint,
    [string]$TimestampUrl  = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'

# Resolve this script's directory (don't rely on $PSScriptRoot inside param defaults).
$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Source)    { $Source    = Join-Path $root 'Set-NetworkConfig.ps1' }
# TODO: change to 'IPChanger.exe' after testing (keep in sync with $ExeName in SetNet-Install.ps1).
if (-not $OutputExe) { $OutputExe = Join-Path $root 'Set-NetworkConfig.exe' }
if (-not $Installer) { $Installer = Join-Path $root 'SetNet-Install.ps1' }

# ---- Ensure ps2exe is available -------------------------------------------
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host 'ps2exe module not found - installing to CurrentUser scope...'
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe

# ---- Compile ---------------------------------------------------------------
Write-Host "Compiling`n  $Source`n-> $OutputExe"
Invoke-ps2exe `
    -InputFile   $Source `
    -OutputFile  $OutputExe `
    -noConsole `
    -title       'Network Configuration Tool' `
    -product     'IPChanger' `
    -description 'Network Configuration Tool' `
    -company     'Biggoan1' `
    -copyright   "(c) $(Get-Date -Format yyyy) Biggoan1" `
    -version     $Version
    # Add -requireAdmin above to embed a UAC manifest (shield icon + prompt before
    # launch). The script also self-elevates, so this is optional.

if (-not (Test-Path $OutputExe)) { throw "Build failed: $OutputExe was not produced." }
Write-Host "Built $OutputExe"

# ---- Sign (optional) -------------------------------------------------------
function Get-SigningCert {
    param([string]$Thumbprint)

    if ($Thumbprint) {
        $cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
                Where-Object { $_.Thumbprint -eq $Thumbprint } | Select-Object -First 1
        if (-not $cert) { throw "No certificate with thumbprint '$Thumbprint' in CurrentUser\My or LocalMachine\My." }
        return $cert
    }

    $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
            Sort-Object NotAfter -Descending | Select-Object -First 1
    if (-not $cert) {
        $cert = Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue |
                Sort-Object NotAfter -Descending | Select-Object -First 1
    }
    if (-not $cert) { throw 'No code-signing certificate found. Pass -CertThumbprint or import your cert.' }
    return $cert
}

if ($Sign) {
    $cert = Get-SigningCert -Thumbprint $CertThumbprint
    Write-Host "Signing with: $($cert.Subject)  [$($cert.Thumbprint)]"

    foreach ($file in @($OutputExe, $Installer)) {
        if (-not (Test-Path $file)) { Write-Warning "Skipping signing (not found): $file"; continue }
        $result = Set-AuthenticodeSignature -FilePath $file -Certificate $cert `
                                            -TimestampServer $TimestampUrl -HashAlgorithm SHA256
        if ($result.Status -ne 'Valid') {
            throw "Signing failed for $file : $($result.Status) - $($result.StatusMessage)"
        }
        Write-Host "Signed: $file"
    }
}
else {
    Write-Host 'Skipping signing (-Sign not specified).'
}

Write-Host "`nDone."
