#requires -Version 5.1
<#
.SYNOPSIS
    Registers (or removes) the TechIP JEA endpoint. Called by SetNet-Install.ps1,
    or run standalone from an elevated / SYSTEM (SCCM) context.
.DESCRIPTION
    Register  : lays the IPChangerJEA module (which carries RoleCapabilities\TechIP.psrc)
                into the machine module path so PowerShell can discover the role, ensures
                the transcript directory exists, validates and registers TechIP.pssc as a
                PSSessionConfiguration named "TechIP".
    Unregister: unregisters the endpoint and removes the module.

    Idempotent. Registration restarts WinRM.
.NOTES
    Requires elevation. Assumes WinRM is enabled with an auth method permitted and the
    "Disallow WinRM from storing RunAs credentials" policy (DisableRunAs) NOT set - JEA
    virtual accounts do not work while DisableRunAs=1. In this lab that is delivered by
    the JEA_WinRM_TechIP GPO; in prod, confirm the WinRM baseline permits it.
#>
param(
    [ValidateSet('Register','Unregister')]
    [string]$Action = 'Register',
    [string]$SourceRoot = $PSScriptRoot,
    [string]$EndpointName = 'TechIP'
)
$ErrorActionPreference = 'Stop'

$ModuleName    = 'IPChangerJEA'
$ModuleSource  = Join-Path $SourceRoot $ModuleName
$PsscSource    = Join-Path $SourceRoot 'TechIP.pssc'
$ModuleDest    = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules\$ModuleName"
$TranscriptDir = 'C:\ProgramData\IPChanger\JEA-Transcripts'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
if (-not (Test-Admin)) { throw "Must run elevated (registering a PSSessionConfiguration requires admin/SYSTEM)." }

if ($Action -eq 'Register') {
    Write-Host "Registering JEA endpoint '$EndpointName'..."

    # 1. module (role capability) into the machine module path
    if (-not (Test-Path $ModuleSource)) { throw "Module source not found: $ModuleSource" }
    if (Test-Path $ModuleDest) { Remove-Item $ModuleDest -Recurse -Force }
    Copy-Item $ModuleSource $ModuleDest -Recurse -Force
    Write-Host "  module -> $ModuleDest"

    # 2. transcript dir
    if (-not (Test-Path $TranscriptDir)) { New-Item $TranscriptDir -ItemType Directory -Force | Out-Null }
    Write-Host "  transcripts -> $TranscriptDir"

    # 3. validate the pssc before touching WinRM
    if (-not (Test-Path $PsscSource)) { throw "Session config not found: $PsscSource" }
    if (-not (Test-PSSessionConfigurationFile -Path $PsscSource)) {
        throw "TechIP.pssc failed Test-PSSessionConfigurationFile - not registering."
    }
    Write-Host "  TechIP.pssc validated"

    # 4. (re)register
    if (Get-PSSessionConfiguration -Name $EndpointName -EA SilentlyContinue) {
        Write-Host "  existing '$EndpointName' found - replacing"
        Unregister-PSSessionConfiguration -Name $EndpointName -Force -NoServiceRestart
    }
    Register-PSSessionConfiguration -Name $EndpointName -Path $PsscSource -Force | Out-Null
    Write-Host "  registered."

    $cfg = Get-PSSessionConfiguration -Name $EndpointName
    Write-Host "  RunAsVirtualAccount=$($cfg.RunAsVirtualAccount)  Permission=$($cfg.Permission)"
    Write-Host "Done. Technicians (NetOps) connect with:"
    Write-Host "  Invoke-Command -ComputerName localhost -ConfigurationName $EndpointName -Credential <xID> -ScriptBlock { Get-NetworkAdapter }"
}
else {
    Write-Host "Unregistering JEA endpoint '$EndpointName'..."
    if (Get-PSSessionConfiguration -Name $EndpointName -EA SilentlyContinue) {
        Unregister-PSSessionConfiguration -Name $EndpointName -Force
        Write-Host "  unregistered."
    } else { Write-Host "  '$EndpointName' not present." }
    if (Test-Path $ModuleDest) { Remove-Item $ModuleDest -Recurse -Force; Write-Host "  module removed." }
}
