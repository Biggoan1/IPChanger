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
    Connects as the CURRENT signed-in user (integrated auth, no prompt); pass -Credential
    only to use a different account. Nothing here runs elevated - the privilege lives
    entirely in the endpoint's virtual account.
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

# No credential prompt: connect as the CURRENT signed-in user (integrated auth). The
# endpoint authorises any authenticated user directly. -Credential is still honoured if
# supplied (e.g. testing as another account).
$conn = @{ ComputerName = $ComputerName; ConfigurationName = $EndpointName }
if ($Credential) { $conn.Credential = $Credential }

switch ($PSCmdlet.ParameterSetName) {
    'List'  { Invoke-Command @conn -ScriptBlock { Get-NetworkAdapter } }
    'Set'   {
        # Pass args positionally; the endpoint is NoLanguage, so the values are bound by
        # the server-side function's parameters (validated there). NoLanguage also means
        # the remote scriptblock must be a single plain command - an if/else inside it is
        # rejected with "syntax is not supported by this runspace" - so branch here.
        if ($Gateway) {
            Invoke-Command @conn -ScriptBlock {
                param($a,$ip,$p,$g) Set-TechnicianIP -Adapter $a -IPAddress $ip -PrefixLength $p -Gateway $g
            } -ArgumentList $Adapter, $IPAddress, $PrefixLength, $Gateway
        }
        else {
            Invoke-Command @conn -ScriptBlock {
                param($a,$ip,$p) Set-TechnicianIP -Adapter $a -IPAddress $ip -PrefixLength $p
            } -ArgumentList $Adapter, $IPAddress, $PrefixLength
        }
    }
    'Reset' { Invoke-Command @conn -ScriptBlock { param($a) Reset-TechnicianIP -Adapter $a } -ArgumentList $Adapter }
}
