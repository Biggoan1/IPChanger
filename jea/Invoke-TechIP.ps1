#requires -Version 5.1
<#
.SYNOPSIS
    Thin client for the TechIP JEA endpoint - the cmdline path for a technician, and
    the same call the GUI makes. Connects to the local constrained endpoint and runs
    one of the three whitelisted functions as the NCO virtual account.
.EXAMPLE
    .\Invoke-TechIP.ps1 -List
.EXAMPLE
    .\Invoke-TechIP.ps1 -Set -Adapter 'Ethernet 2' -IPAddress 192.168.50.50 -PrefixLength 24
.EXAMPLE
    .\Invoke-TechIP.ps1 -Reset -Adapter 'Ethernet 2'
.NOTES
    Prompts for the technician's xID credential unless -Credential is supplied. Nothing
    here runs elevated - the privilege lives entirely in the endpoint's virtual account.
#>
[CmdletBinding(DefaultParameterSetName='List')]
param(
    [Parameter(ParameterSetName='List')]   [switch]$List,
    [Parameter(ParameterSetName='Set')]    [switch]$Set,
    [Parameter(ParameterSetName='Reset')]  [switch]$Reset,

    [Parameter(ParameterSetName='Set', Mandatory)]
    [Parameter(ParameterSetName='Reset', Mandatory)]
    [string]$Adapter,

    [Parameter(ParameterSetName='Set', Mandatory)] [string]$IPAddress,
    [Parameter(ParameterSetName='Set', Mandatory)] [int]$PrefixLength,
    [Parameter(ParameterSetName='Set')]            [string]$Gateway,

    [pscredential]$Credential,
    [string]$EndpointName = 'TechIP',
    [string]$ComputerName = 'localhost'
)
$ErrorActionPreference = 'Stop'

if (-not $Credential) {
    $Credential = Get-Credential -Message "Enter your privileged (xID) credential for the $EndpointName endpoint" -UserName "$env:USERDOMAIN\"
}
$conn = @{ ComputerName = $ComputerName; ConfigurationName = $EndpointName; Credential = $Credential }

switch ($PSCmdlet.ParameterSetName) {
    'List'  { Invoke-Command @conn -ScriptBlock { Get-NetworkAdapter } }
    'Set'   {
        # Pass args positionally; the endpoint is NoLanguage, so the values are bound by
        # the server-side function's parameters (validated there).
        Invoke-Command @conn -ScriptBlock {
            param($a,$ip,$p,$g)
            if ($g) { Set-TechnicianIP -Adapter $a -IPAddress $ip -PrefixLength $p -Gateway $g }
            else    { Set-TechnicianIP -Adapter $a -IPAddress $ip -PrefixLength $p }
        } -ArgumentList $Adapter, $IPAddress, $PrefixLength, $Gateway
    }
    'Reset' { Invoke-Command @conn -ScriptBlock { param($a) Reset-TechnicianIP -Adapter $a } -ArgumentList $Adapter }
}
