#requires -Version 5.1

<#
.SYNOPSIS
    Network Configuration GUI Tool
.DESCRIPTION
    Allows users in the Network Configuration Operators group to change IP settings
    when run with elevation.
.NOTES
    Author: Network Operations
    Requires: Network Configuration Operators group membership and elevation
#>

# ---------------------------------------------------------------------------
# Self-elevation
# ---------------------------------------------------------------------------
# Changing IP settings requires elevation. When this app is launched without
# administrative rights it relaunches itself through UAC and exits the original
# (non-elevated) instance. This replaces the old separate Launch-NetworkConfig
# launcher and works both as a .ps1 (during testing) and as the ps2exe .exe.
$currentIdentity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)

if (-not $currentPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $thisProcess = [System.Diagnostics.Process]::GetCurrentProcess()
    # Run as a script -> host is powershell/pwsh; compiled -> host is the app exe itself.
    $runningAsScript = $thisProcess.ProcessName -in @('powershell', 'pwsh', 'powershell_ise')
    try {
        if ($runningAsScript) {
            Start-Process -FilePath $thisProcess.MainModule.FileName -Verb RunAs -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                '-File', "`"$PSCommandPath`""
            )
        }
        else {
            Start-Process -FilePath $thisProcess.MainModule.FileName -Verb RunAs
        }
    }
    catch {
        # User dismissed the UAC prompt (or elevation failed) - nothing to do.
    }
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Function to validate IP address format
function Test-IPAddress {
    param([string]$IP)
    
    if ([string]::IsNullOrWhiteSpace($IP)) {
        return $false
    }
    
    $octets = $IP.Split('.')
    if ($octets.Count -ne 4) {
        return $false
    }
    
    foreach ($octet in $octets) {
        $num = 0
        if (-not [int]::TryParse($octet, [ref]$num)) {
            return $false
        }
        if ($num -lt 0 -or $num -gt 255) {
            return $false
        }
    }
    
    return $true
}

# Function to validate subnet mask
function Test-SubnetMask {
    param([string]$Subnet)
    
    if (-not (Test-IPAddress $Subnet)) {
        return $false
    }
    
    # Convert to binary and validate it's a valid subnet mask
    $octets = $Subnet.Split('.')
    $binaryString = ""
    
    foreach ($octet in $octets) {
        $binaryString += [Convert]::ToString([int]$octet, 2).PadLeft(8, '0')
    }
    
    # Valid subnet mask must be contiguous 1s followed by contiguous 0s
    if ($binaryString -notmatch '^1+0*$') {
        return $false
    }
    
    return $true
}

# Function to check group membership
function Test-GroupMembership {
    param([string]$GroupName)
    
    try {
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
        
        # Check if user is in the specified group
        $groupSid = (New-Object System.Security.Principal.NTAccount($GroupName)).Translate([System.Security.Principal.SecurityIdentifier])
        
        foreach ($group in $currentUser.Groups) {
            if ($group.Value -eq $groupSid.Value) {
                return $true
            }
        }
        
        return $false
    }
    catch {
        return $false
    }
}

# Function to convert subnet mask to prefix length
function ConvertTo-PrefixLength {
    param([string]$SubnetMask)
    $octets = $SubnetMask.Split('.')
    $binaryString = ""
    foreach ($octet in $octets) {
        $binaryString += [Convert]::ToString([int]$octet, 2).PadLeft(8, '0')
    }
    return ($binaryString.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}

# Function to convert CIDR prefix to subnet mask
function ConvertTo-SubnetMask {
    param([int]$PrefixLength)

    if ($PrefixLength -lt 0 -or $PrefixLength -gt 32) {
        return $null
    }

    $binaryString = ('1' * $PrefixLength).PadRight(32, '0')
    $octets = @()

    for ($i = 0; $i -lt 4; $i++) {
        $octetBinary = $binaryString.Substring($i * 8, 8)
        $octets += [Convert]::ToInt32($octetBinary, 2)
    }

    return $octets
}

# Function to check if adapter is using DHCP
function Test-AdapterDHCP {
    param([string]$AdapterName)

    try {
        $adapter = Get-NetAdapter | Where-Object { $_.Name -eq $AdapterName }
        if (-not $adapter) {
            return $false
        }

        $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ipConfig) {
            return $ipConfig.PrefixOrigin -eq "Dhcp"
        }
        return $true
    }
    catch {
        return $false
    }
}

# Function to set adapter to DHCP
function Set-AdapterToDHCP {
    param([string]$AdapterName)

    try {
        $adapter = Get-NetAdapter | Where-Object { $_.Name -eq $AdapterName }
        if (-not $adapter) {
            throw "Network adapter '$AdapterName' not found"
        }

        # Remove static IP configuration
        $adapter | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        $adapter | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

        # Set to DHCP
        $adapter | Set-NetIPInterface -Dhcp Enabled -ErrorAction Stop
        $adapter | Set-DnsClientServerAddress -ResetServerAddresses -ErrorAction Stop

        # Force DHCP renewal by restarting the adapter
        $adapter | Restart-NetAdapter -Confirm:$false -ErrorAction Stop

        return $true
    }
    catch {
        throw $_.Exception.Message
    }
}

# Function to apply network settings (already running elevated)
function Set-NetworkConfiguration {
    param(
        [string]$AdapterName,
        [string]$IPAddress,
        [string]$SubnetMask,
        [string]$Gateway,
        [string]$PrimaryDNS,
        [string]$SecondaryDNS
    )

    try {
        # Get the network adapter
        $netAdapter = Get-NetAdapter | Where-Object { $_.Name -eq $AdapterName }

        if (-not $netAdapter) {
            throw "Network adapter '$AdapterName' not found"
        }

        # Turn DHCP off on this interface FIRST. New-NetIPAddress writes a persistent static
        # IP, which Windows rejects while DHCP is still enabled ("Inconsistent parameters
        # PolicyStore PersistentStore and Dhcp Enabled") - lease or no lease. Let a real
        # failure here surface rather than masking it and hitting the confusing error later.
        Set-NetIPInterface -InterfaceIndex $netAdapter.InterfaceIndex -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop

        # Remove existing IP configuration
        $netAdapter | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        $netAdapter | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

        # Set new IP address and subnet mask
        $netAdapter | New-NetIPAddress -IPAddress $IPAddress -PrefixLength (ConvertTo-PrefixLength $SubnetMask) -DefaultGateway $Gateway -ErrorAction Stop

        # Set DNS servers
        $dnsServers = @()
        if ($PrimaryDNS) { $dnsServers += $PrimaryDNS }
        if ($SecondaryDNS) { $dnsServers += $SecondaryDNS }

        if ($dnsServers.Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceIndex $netAdapter.InterfaceIndex -ServerAddresses $dnsServers
        }

        return $true
    }
    catch {
        throw $_.Exception.Message
    }
}

# Helper function to create IP octet input group
function New-IPOctetGroup {
    param(
        [int]$X,
        [int]$Y,
        [int]$StartTabIndex
    )

    $controls = @()

    for ($i = 0; $i -lt 4; $i++) {
        $textBox = New-Object System.Windows.Forms.TextBox
        $textBox.Location = New-Object System.Drawing.Point(($X + ($i * 42)), $Y)
        $textBox.Size = New-Object System.Drawing.Size(35, 20)
        $textBox.MaxLength = 3
        $textBox.TabIndex = $StartTabIndex + $i
        $textBox.TextAlign = "Center"

        # Add validation and auto-advance
        $textBox.Add_KeyPress({
            param($sender, $e)
            # Check for period - advance to next field
            if ($e.KeyChar -eq '.') {
                $form.SelectNextControl($sender, $true, $true, $true, $true)
                $e.Handled = $true
                return
            }
            # Only allow digits and backspace
            if (-not [char]::IsDigit($e.KeyChar) -and $e.KeyChar -ne [char]8) {
                $e.Handled = $true
            }
        })

        $textBox.Add_KeyDown({
            param($sender, $e)
            # Backspace at the beginning moves to previous field
            if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Back) {
                if ($sender.SelectionStart -eq 0 -and $sender.Text.Length -eq 0) {
                    $form.SelectNextControl($sender, $false, $true, $true, $true)
                    $e.Handled = $true
                    $e.SuppressKeyPress = $true
                }
            }
        })

        $textBox.Add_TextChanged({
            param($sender, $e)
            # Auto-advance to the next box when 3 digits are entered - but only when the
            # user is actually typing in THIS box. Without the Focused check, programmatic
            # fills (CIDR -> subnet mask, or reading an adapter's config) would trip the
            # advance and steal focus (e.g. the CIDR field tabbing away after one digit).
            if ($sender.Focused -and $sender.Text.Length -eq 3) {
                $form.SelectNextControl($sender, $true, $true, $true, $true)
            }
        })

        $controls += $textBox

        # Add dot label between octets (except after last one)
        if ($i -lt 3) {
            $dotLabel = New-Object System.Windows.Forms.Label
            $dotLabel.Location = New-Object System.Drawing.Point(($X + 35 + ($i * 42)), ($Y + 2))
            $dotLabel.Size = New-Object System.Drawing.Size(7, 20)
            $dotLabel.Text = "."
            $controls += $dotLabel
        }
    }

    return $controls
}

# Resolve the app version to show on the form. Compiled exe -> its embedded FileVersion
# (what was built/signed in prod); running as a .ps1 -> the VERSION file next to the script.
function Get-AppVersion {
    try {
        $proc = [System.Diagnostics.Process]::GetCurrentProcess()
        if ($proc.ProcessName -notin @('powershell', 'pwsh', 'powershell_ise')) {
            $fv = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($proc.MainModule.FileName).FileVersion
            if ($fv) { return $fv }
        }
    }
    catch { }
    $vf = Join-Path $PSScriptRoot 'VERSION'
    if (Test-Path $vf) { return (Get-Content $vf -Raw).Trim() }
    return 'dev'
}

# Auto-fill the default gateway from the entered IP + CIDR: gateway = network address + 1
# (e.g. 10.100.1.25 /24 -> 10.100.1.1). Suppressed while an adapter's real config is being read.
$script:suppressGatewayAutofill = $false
function Update-GatewayFromNetwork {
    if ($script:suppressGatewayAutofill) { return }
    if (-not $ipOctets -or -not $gatewayOctets -or -not $textCidr) { return }

    $ipParts = @()
    foreach ($c in $ipOctets) { if ($c -is [System.Windows.Forms.TextBox]) { $ipParts += $c.Text } }
    $ip = $ipParts -join '.'
    if (-not (Test-IPAddress $ip)) { return }

    $cidr = 0
    if (-not [int]::TryParse($textCidr.Text, [ref]$cidr)) { return }
    if ($cidr -lt 1 -or $cidr -gt 30) { return }   # only networks with a usable host range

    $mask = ConvertTo-SubnetMask -PrefixLength $cidr
    if (-not $mask) { return }

    $ipB = $ip.Split('.') | ForEach-Object { [int]$_ }
    $gw  = @(
        ($ipB[0] -band $mask[0]),
        ($ipB[1] -band $mask[1]),
        ($ipB[2] -band $mask[2]),
        (($ipB[3] -band $mask[3]) + 1)
    )
    $i = 0
    foreach ($c in $gatewayOctets) {
        if ($c -is [System.Windows.Forms.TextBox]) { $c.Text = $gw[$i++].ToString() }
    }
}

# Check group membership before showing GUI
if (-not (Test-GroupMembership -GroupName "Network Configuration Operators")) {
    [void][System.Windows.Forms.MessageBox]::Show(
        "You are not a member of the 'Network Configuration Operators' group.`n`nAccess denied.",
        "Authorization Required",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Network Configuration Tool"
$form.Size = New-Object System.Drawing.Size(400, 420)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
$form.KeyPreview = $true

$tabIndex = 0

# Network Adapter Selection
$labelAdapter = New-Object System.Windows.Forms.Label
$labelAdapter.Location = New-Object System.Drawing.Point(20, 25)
$labelAdapter.Size = New-Object System.Drawing.Size(120, 22)
$labelAdapter.Text = "Network Adapter:"
$form.Controls.Add($labelAdapter)

$comboAdapter = New-Object System.Windows.Forms.ComboBox
$comboAdapter.Location = New-Object System.Drawing.Point(145, 23)
$comboAdapter.Size = New-Object System.Drawing.Size(220, 22)
$comboAdapter.DropDownStyle = "DropDownList"
$comboAdapter.FlatStyle = "Flat"
$comboAdapter.TabIndex = $tabIndex++

# Populate network adapters.
# Show ALL physical adapters (connected or not); exclude Wi-Fi, WWAN/cellular, and
# Hyper-V / VMware vEthernet switch adapters (explicit, on top of -Physical).
Get-NetAdapter -Physical | Where-Object {
    $_.PhysicalMediaType -ne "Native 802.11" -and          # exclude Wi-Fi
    $_.PhysicalMediaType -ne "Wireless WAN" -and           # exclude WWAN / cellular
    $_.InterfaceDescription -notmatch "Mobile Broadband|WWAN|Cellular" -and
    $_.InterfaceDescription -notmatch "vEthernet|Hyper-V|Virtual|VMware|VirtualBox|TAP-Windows" -and
    $_.Name -notmatch "vEthernet|VMware"
} | Sort-Object Name | ForEach-Object {
    $comboAdapter.Items.Add($_.Name) | Out-Null
}

if ($comboAdapter.Items.Count -gt 0) {
    $comboAdapter.SelectedIndex = 0
}
$form.Controls.Add($comboAdapter)

# IP Address
$labelIP = New-Object System.Windows.Forms.Label
$labelIP.Location = New-Object System.Drawing.Point(20, 70)
$labelIP.Size = New-Object System.Drawing.Size(120, 22)
$labelIP.Text = "IP Address:"
$form.Controls.Add($labelIP)

$ipOctets = New-IPOctetGroup -X 145 -Y 68 -StartTabIndex $tabIndex
$tabIndex += 4
$ipOctets | ForEach-Object { $form.Controls.Add($_) }

# When the IP changes, refresh the gateway guess (network + 1).
$ipOctets | Where-Object { $_ -is [System.Windows.Forms.TextBox] } | ForEach-Object {
    $_.Add_TextChanged({ Update-GatewayFromNetwork })
}

# CIDR Prefix (e.g., /24)
$labelCidrSlash = New-Object System.Windows.Forms.Label
$labelCidrSlash.Location = New-Object System.Drawing.Point(313, 70)
$labelCidrSlash.Size = New-Object System.Drawing.Size(10, 22)
$labelCidrSlash.Text = "/"
$form.Controls.Add($labelCidrSlash)

$textCidr = New-Object System.Windows.Forms.TextBox
$textCidr.Location = New-Object System.Drawing.Point(323, 68)
$textCidr.Size = New-Object System.Drawing.Size(30, 22)
$textCidr.MaxLength = 2
$textCidr.TabIndex = $tabIndex++
$textCidr.TextAlign = "Center"
$textCidr.BorderStyle = "FixedSingle"
$textCidr.Add_KeyPress({
    param($sender, $e)
    # Only allow digits
    if (-not [char]::IsDigit($e.KeyChar) -and $e.KeyChar -ne [char]8) {
        $e.Handled = $true
    }
})
$textCidr.Add_TextChanged({
    # Auto-calculate subnet mask from CIDR
    if ($textCidr.Text.Length -gt 0) {
        $cidr = 0
        if ([int]::TryParse($textCidr.Text, [ref]$cidr)) {
            $maskOctets = ConvertTo-SubnetMask -PrefixLength $cidr
            if ($maskOctets) {
                $octetIndex = 0
                foreach ($control in $subnetOctets) {
                    if ($control -is [System.Windows.Forms.TextBox]) {
                        $control.Text = $maskOctets[$octetIndex++].ToString()
                    }
                }
            }
        }
    }
    # Keep the default gateway in step with the network
    Update-GatewayFromNetwork
})
$form.Controls.Add($textCidr)

# Subnet Mask
$labelSubnet = New-Object System.Windows.Forms.Label
$labelSubnet.Location = New-Object System.Drawing.Point(20, 120)
$labelSubnet.Size = New-Object System.Drawing.Size(120, 22)
$labelSubnet.Text = "Subnet Mask:"
$form.Controls.Add($labelSubnet)

$subnetOctets = New-IPOctetGroup -X 145 -Y 118 -StartTabIndex $tabIndex
$tabIndex += 4
$subnetOctets | ForEach-Object { $form.Controls.Add($_) }

# Set default CIDR value after subnet octets are created
$textCidr.Text = "24"

# Default Gateway
$labelGateway = New-Object System.Windows.Forms.Label
$labelGateway.Location = New-Object System.Drawing.Point(20, 170)
$labelGateway.Size = New-Object System.Drawing.Size(120, 22)
$labelGateway.Text = "Default Gateway:"
$form.Controls.Add($labelGateway)

$gatewayOctets = New-IPOctetGroup -X 145 -Y 168 -StartTabIndex $tabIndex
$tabIndex += 4
$gatewayOctets | ForEach-Object { $form.Controls.Add($_) }

# Primary DNS
$labelDNS1 = New-Object System.Windows.Forms.Label
$labelDNS1.Location = New-Object System.Drawing.Point(20, 220)
$labelDNS1.Size = New-Object System.Drawing.Size(120, 22)
$labelDNS1.Text = "Primary DNS:"
$form.Controls.Add($labelDNS1)

$dns1Octets = New-IPOctetGroup -X 145 -Y 218 -StartTabIndex $tabIndex
$tabIndex += 4
$dns1Octets | ForEach-Object { $form.Controls.Add($_) }

# Secondary DNS
$labelDNS2 = New-Object System.Windows.Forms.Label
$labelDNS2.Location = New-Object System.Drawing.Point(20, 270)
$labelDNS2.Size = New-Object System.Drawing.Size(120, 22)
$labelDNS2.Text = "Secondary DNS:"
$form.Controls.Add($labelDNS2)

$dns2Octets = New-IPOctetGroup -X 145 -Y 268 -StartTabIndex $tabIndex
$tabIndex += 4
$dns2Octets | ForEach-Object { $form.Controls.Add($_) }

# Helper function to get IP from octet controls
function Get-IPFromOctets {
    param([array]$OctetControls)

    $octets = @()
    foreach ($control in $OctetControls) {
        if ($control -is [System.Windows.Forms.TextBox]) {
            $octets += $control.Text
        }
    }
    return $octets -join '.'
}

# DHCP Button
$buttonDHCP = New-Object System.Windows.Forms.Button
$buttonDHCP.Location = New-Object System.Drawing.Point(20, 315)
$buttonDHCP.Size = New-Object System.Drawing.Size(100, 35)
$buttonDHCP.Text = "Enable DHCP"
$buttonDHCP.FlatStyle = "Flat"
$buttonDHCP.BackColor = [System.Drawing.Color]::FromArgb(100, 180, 100)
$buttonDHCP.ForeColor = [System.Drawing.Color]::White
$buttonDHCP.FlatAppearance.BorderSize = 0
$buttonDHCP.Cursor = [System.Windows.Forms.Cursors]::Hand
$buttonDHCP.TabIndex = $tabIndex++
$buttonDHCP.Add_Click({
    try {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Switch to DHCP for adapter: $($comboAdapter.SelectedItem)?`n`nThis will remove the static IP configuration.",
            "Confirm DHCP",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $success = Set-AdapterToDHCP -AdapterName $comboAdapter.SelectedItem

            if ($success) {
                # Wait for adapter to restart and DHCP to obtain address
                Start-Sleep -Seconds 3

                [void][System.Windows.Forms.MessageBox]::Show(
                    "DHCP enabled successfully!",
                    "Success",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
                Update-DHCPButtonState
                Update-FormFromAdapter
            }
        }
    }
    catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Error: $($_.Exception.Message)",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
})
$form.Controls.Add($buttonDHCP)

# Apply Button
$buttonApply = New-Object System.Windows.Forms.Button
$buttonApply.Location = New-Object System.Drawing.Point(130, 315)
$buttonApply.Size = New-Object System.Drawing.Size(100, 35)
$buttonApply.Text = "Apply"
$buttonApply.FlatStyle = "Flat"
$buttonApply.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$buttonApply.ForeColor = [System.Drawing.Color]::White
$buttonApply.FlatAppearance.BorderSize = 0
$buttonApply.Cursor = [System.Windows.Forms.Cursors]::Hand
$buttonApply.TabIndex = $tabIndex++
$buttonApply.Add_Click({
    # Get IP addresses from octets
    $ipAddress = Get-IPFromOctets $ipOctets
    $subnetMask = Get-IPFromOctets $subnetOctets
    $gateway = Get-IPFromOctets $gatewayOctets
    $dns1 = Get-IPFromOctets $dns1Octets
    $dns2 = Get-IPFromOctets $dns2Octets

    # Validate all inputs
    $errors = @()

    if ([string]::IsNullOrWhiteSpace($comboAdapter.SelectedItem)) {
        $errors += "Please select a network adapter"
    }

    if (-not (Test-IPAddress $ipAddress)) {
        $errors += "Invalid IP address format"
    }

    if (-not (Test-SubnetMask $subnetMask)) {
        $errors += "Invalid subnet mask"
    }

    if (-not [string]::IsNullOrWhiteSpace($gateway) -and -not (Test-IPAddress $gateway)) {
        $errors += "Invalid gateway IP address"
    }

    # DNS is optional - no validation needed

    if ($errors.Count -gt 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            ($errors -join "`n"),
            "Validation Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    try {
        # Confirm before applying
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Apply the following configuration?`n`n" +
            "Adapter: $($comboAdapter.SelectedItem)`n" +
            "IP: $ipAddress`n" +
            "Subnet: $subnetMask`n" +
            "Gateway: $gateway`n" +
            "DNS1: $dns1`n" +
            "DNS2: $dns2",
            "Confirm Configuration",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            # Apply configuration
            $success = Set-NetworkConfiguration `
                -AdapterName $comboAdapter.SelectedItem `
                -IPAddress $ipAddress `
                -SubnetMask $subnetMask `
                -Gateway $gateway `
                -PrimaryDNS $dns1 `
                -SecondaryDNS $dns2

            if ($success) {
                [void][System.Windows.Forms.MessageBox]::Show(
                    "Network configuration applied successfully!",
                    "Success",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
                Update-DHCPButtonState
                Update-FormFromAdapter
            }
        }
    }
    catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Error: $($_.Exception.Message)",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
})
$form.Controls.Add($buttonApply)

# Cancel Button
$buttonCancel = New-Object System.Windows.Forms.Button
$buttonCancel.Location = New-Object System.Drawing.Point(240, 315)
$buttonCancel.Size = New-Object System.Drawing.Size(100, 35)
$buttonCancel.Text = "Cancel"
$buttonCancel.FlatStyle = "Flat"
$buttonCancel.BackColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
$buttonCancel.ForeColor = [System.Drawing.Color]::Black
$buttonCancel.FlatAppearance.BorderSize = 0
$buttonCancel.Cursor = [System.Windows.Forms.Cursors]::Hand
$buttonCancel.TabIndex = $tabIndex++
$buttonCancel.Add_Click({
    $form.Close()
})
$form.Controls.Add($buttonCancel)

# Version label (bottom-right corner) - lets you confirm which build you're running
$labelVersion = New-Object System.Windows.Forms.Label
$labelVersion.Text = "v$(Get-AppVersion)"
$labelVersion.Size = New-Object System.Drawing.Size(150, 15)
$labelVersion.Location = New-Object System.Drawing.Point(215, 360)
$labelVersion.TextAlign = "MiddleRight"
$labelVersion.ForeColor = [System.Drawing.Color]::Gray
$labelVersion.Font = New-Object System.Drawing.Font("Segoe UI", 7.5)
$form.Controls.Add($labelVersion)

# Function to populate form fields from adapter configuration
function Update-FormFromAdapter {
    if ($comboAdapter.SelectedItem) {
        # Don't let the IP/CIDR writes below trigger the gateway auto-fill - we want the
        # adapter's REAL gateway, which is set explicitly further down.
        $script:suppressGatewayAutofill = $true
        try {
            $adapter = Get-NetAdapter | Where-Object { $_.Name -eq $comboAdapter.SelectedItem }
            if ($adapter) {
                # Get IP configuration
                $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
                $gateway = Get-NetRoute -InterfaceIndex $adapter.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
                $dns = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

                if ($ipConfig) {
                    # Populate IP address octets
                    $ipParts = $ipConfig.IPAddress -split '\.'
                    $octetIndex = 0
                    foreach ($control in $ipOctets) {
                        if ($control -is [System.Windows.Forms.TextBox] -and $octetIndex -lt $ipParts.Count) {
                            $control.Text = $ipParts[$octetIndex++]
                        }
                    }

                    # Set CIDR
                    $textCidr.Text = $ipConfig.PrefixLength.ToString()

                    # Populate gateway
                    if ($gateway) {
                        $gwParts = $gateway.NextHop -split '\.'
                        $octetIndex = 0
                        foreach ($control in $gatewayOctets) {
                            if ($control -is [System.Windows.Forms.TextBox] -and $octetIndex -lt $gwParts.Count) {
                                $control.Text = $gwParts[$octetIndex++]
                            }
                        }
                    }

                    # Populate DNS
                    if ($dns.ServerAddresses) {
                        if ($dns.ServerAddresses.Count -gt 0 -and $dns.ServerAddresses[0] -ne "fec0:0:0:ffff::1" -and $dns.ServerAddresses[0] -ne "fec0:0:0:ffff::2" -and $dns.ServerAddresses[0] -ne "fec0:0:0:ffff::3") {
                            $dnsParts = $dns.ServerAddresses[0] -split '\.'
                            $octetIndex = 0
                            foreach ($control in $dns1Octets) {
                                if ($control -is [System.Windows.Forms.TextBox] -and $octetIndex -lt $dnsParts.Count) {
                                    $control.Text = $dnsParts[$octetIndex++]
                                }
                            }
                        }

                        if ($dns.ServerAddresses.Count -gt 1 -and $dns.ServerAddresses[1] -ne "fec0:0:0:ffff::1" -and $dns.ServerAddresses[1] -ne "fec0:0:0:ffff::2" -and $dns.ServerAddresses[1] -ne "fec0:0:0:ffff::3") {
                            $dnsParts = $dns.ServerAddresses[1] -split '\.'
                            $octetIndex = 0
                            foreach ($control in $dns2Octets) {
                                if ($control -is [System.Windows.Forms.TextBox] -and $octetIndex -lt $dnsParts.Count) {
                                    $control.Text = $dnsParts[$octetIndex++]
                                }
                            }
                        }
                    }
                }
            }
        }
        catch {
            # Silently fail - form will keep current values
        }
        finally {
            $script:suppressGatewayAutofill = $false
        }
    }
}

# Function to update DHCP button state
function Update-DHCPButtonState {
    if ($comboAdapter.SelectedItem) {
        $isDHCP = Test-AdapterDHCP -AdapterName $comboAdapter.SelectedItem
        $buttonDHCP.Enabled = -not $isDHCP
        if ($isDHCP) {
            $buttonDHCP.Text = "DHCP Active"
        } else {
            $buttonDHCP.Text = "Enable DHCP"
        }
    }
}

# Update DHCP button when adapter selection changes
$comboAdapter.Add_SelectedIndexChanged({
    Update-DHCPButtonState
})

# Initial update of DHCP button state
Update-DHCPButtonState

# Add keyboard shortcuts
$form.Add_KeyDown({
    param($sender, $e)

    # Enter key = Apply
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $buttonApply.PerformClick()
        $e.Handled = $true
    }

    # Escape key = Cancel
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $form.Close()
        $e.Handled = $true
    }
})

# Show the form
[void]$form.ShowDialog()
