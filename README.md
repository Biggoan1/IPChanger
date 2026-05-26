# IPChanger — Network Configuration Tool

A small Windows Forms GUI that lets members of the **Network Configuration Operators**
group change IPv4 settings (IP address, subnet/CIDR, gateway, DNS) on a selected
physical network adapter, or switch the adapter back to DHCP.

## What it does

- Lists **all physical adapters** (connected or not), excluding Wi-Fi and WWAN/cellular.
- Validates IP address, subnet mask, and gateway input.
- Reads the currently selected adapter's settings into the form.
- Applies a static configuration, or enables DHCP.
- Gated to members of the `Network Configuration Operators` group.
- **Self-elevating**: launches, prompts for UAC, and runs elevated. (This replaces the
  old separate `Launch-NetworkConfig` launcher — it's now one app.)

## Requirements

- Windows 10/11, PowerShell 5.1+
- Membership in the local `Network Configuration Operators` group
- Administrative elevation (the app requests it via UAC)
- To build: the [`ps2exe`](https://github.com/MScholtes/PS2EXE) module
- To sign: a code-signing certificate in `Cert:\CurrentUser\My` (or `LocalMachine\My`)

## Project layout

| File | Purpose |
|------|---------|
| `Set-NetworkConfig.ps1` | The app: self-elevation + the WinForms GUI and all network logic. |
| `SetNet-Install.ps1` | Install/uninstall script. Copies the exe to `C:\Program Files\IPChanger` and creates Desktop + Start Menu shortcuts. |
| `build.ps1` | Compiles `Set-NetworkConfig.ps1` to an exe with ps2exe and (optionally) signs the exe + installer. |

> The compiled `.exe` is a build artifact and is **not** committed (see `.gitignore`).

## Build

```powershell
# Compile only
.\build.ps1

# Compile and sign the exe + installer (uses newest code-signing cert in your store)
.\build.ps1 -Sign

# Sign with a specific certificate and set the version
.\build.ps1 -Sign -CertThumbprint <THUMBPRINT> -Version 4.0.1.0
```

Output: `Set-NetworkConfig.exe` next to the script.

## Install / uninstall

Ship `Set-NetworkConfig.exe` and `SetNet-Install.ps1` together, then run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\SetNet-Install.ps1 -Action Install
powershell.exe -ExecutionPolicy Bypass -File .\SetNet-Install.ps1 -Action Uninstall
```

- Installs to: `C:\Program Files\IPChanger`
- Shortcuts: Public Desktop and All-Users Start Menu, named **Network Configuration Tool**
- Logs: `C:\ProgramData\IPChanger\Logs`

## Renaming the exe to `IPChanger.exe`

The exe is currently named `Set-NetworkConfig.exe` so functionality can be verified
against the prior versions. To switch the final name to `IPChanger.exe`, update the
two `# TODO` markers:

- `build.ps1` → `-OutputExe`
- `SetNet-Install.ps1` → `$ExeName`
