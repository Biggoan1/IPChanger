function Sign-ScriptWithCodeSigningCert {
<#
.SYNOPSIS
    Sign one or more files (or whole folders) with the newest Code Signing cert in CurrentUser\My.
    Works in Windows PowerShell 5.1 and PowerShell 7 (Windows only - Authenticode is a Windows API).
    Dot-source this file, then call the function. Used by build.ps1 -Sign for the jea\ tree.
.EXAMPLE
    Sign-ScriptWithCodeSigningCert .\SetNet-Install.ps1
    Sign-ScriptWithCodeSigningCert .\jea -Recurse           # .ps1/.psd1/.psrc/.pssc under jea\
    Get-ChildItem .\jea -Recurse -Include *.psrc,*.pssc | Sign-ScriptWithCodeSigningCert
    Sign-ScriptWithCodeSigningCert .\IPChanger.exe -CertThumbprint AABBCC...
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [Alias('FullName', 'Path')]
        [string[]]$ScriptPath,
        [switch]$Recurse,
        [string]$CertThumbprint,
        [string]$TimestampServer = 'http://timestamp.digicert.com',
        [string[]]$Include = @('*.ps1','*.psm1','*.psd1','*.ps1xml','*.psrc','*.pssc','*.exe','*.dll','*.msi')
    )
    begin {
        if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') { throw 'Authenticode signing is Windows-only.' }
        Import-Module Microsoft.PowerShell.Security -ErrorAction SilentlyContinue
        $certs = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object HasPrivateKey
        if ($CertThumbprint) { $certs = $certs | Where-Object Thumbprint -eq $CertThumbprint }
        $cert = $certs | Sort-Object NotAfter -Descending | Select-Object -First 1
        if (-not $cert) { throw "No code-signing certificate (with private key) found in CurrentUser\My$(if($CertThumbprint){" matching $CertThumbprint"})." }
        if ($cert.NotAfter -lt (Get-Date)) { Write-Warning "Certificate expired $($cert.NotAfter) - signature will only be valid if timestamped before expiry." }
        Write-Host "Using certificate issued by: $($cert.Issuer)"
        Write-Host "Subject:    $($cert.Subject)"
        Write-Host "Thumbprint: $($cert.Thumbprint)"
        Write-Host "Expires:    $($cert.NotAfter)"
        $results = @()
    }
    process {
        foreach ($p in $ScriptPath) {
            $item = Get-Item -LiteralPath $p -ErrorAction Stop
            $files = if ($item.PSIsContainer) { Get-ChildItem -LiteralPath $item.FullName -File -Recurse:$Recurse -Include $Include } else { $item }
            foreach ($f in $files) {
                $sig = Set-AuthenticodeSignature -FilePath $f.FullName -Certificate $cert -TimestampServer $TimestampServer -HashAlgorithm SHA256 -ErrorAction Stop
                $ok = $sig.Status -eq 'Valid'
                Write-Host ("{0,-9} {1}" -f $sig.Status, $f.FullName) -ForegroundColor ($(if ($ok) {'Green'} else {'Red'}))
                if (-not $ok) { Write-Warning "  $($sig.StatusMessage)" }
                $results += $sig
            }
        }
    }
    end {
        $bad = @($results | Where-Object Status -ne 'Valid').Count
        Write-Host "Signed $($results.Count) file(s), $bad failure(s)."
        if ($bad) { throw "$bad file(s) failed to sign." }
    }
}
