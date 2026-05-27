# IPChanger — Network Configuration Tool

A small Windows Forms GUI that lets members of the **Network Configuration Operators**
group change IPv4 settings (IP address, subnet/CIDR, gateway, DNS) on a selected
physical network adapter, or switch the adapter back to DHCP.

## What it does

- Lists **all physical adapters** (connected or not), excluding Wi-Fi, WWAN/cellular, and Hyper-V/VMware vEthernet switches.
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
| `build.ps1` | Compiles `Set-NetworkConfig.ps1` to an exe with ps2exe, embeds the icon, and (optionally) signs the exe + installer. |
| `Make-Icon.ps1` | Generates `IPChanger.ico` (re-run to tweak the icon design). |
| `IPChanger.ico` | App icon embedded into the exe; the installer's shortcuts inherit it. |
| `VERSION` | Single source of truth for the app version (auto-bumped by the git pre-commit hook). |
| `hooks/pre-commit` | Git hook that increments `VERSION` on each commit. Install with `cp hooks/pre-commit .git/hooks/`. |

See **[STATUS.md](STATUS.md)** for current state and next steps (a handoff briefing).

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

Output: `IPChanger.exe` next to the script (compiled from `Set-NetworkConfig.ps1`).

## Install / uninstall

Ship `IPChanger.exe` and `SetNet-Install.ps1` together, then run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\SetNet-Install.ps1 -Action Install
powershell.exe -ExecutionPolicy Bypass -File .\SetNet-Install.ps1 -Action Uninstall
```

- Installs to: `C:\Program Files\IPChanger`
- Shortcuts: Public Desktop and All-Users Start Menu, named **Network Configuration Tool** (using the exe's embedded icon)
- Logs: `C:\ProgramData\IPChanger\Logs`
- On install/uninstall, removes leftovers from older versions (`C:\Distrib\*.exe`, the
  `Apps\NetCfg` folder, and old Desktop / Start Menu shortcuts). `C:\Distrib` and its
  `\logs` are left untouched.

## Versioning

The version lives in `VERSION` (e.g. `4.0.2`). The git `pre-commit` hook bumps the patch
number on every commit, `build.ps1` stamps it into the exe, and the app displays it in the
bottom-right corner of the window — so you can always confirm which build you're running.
On a fresh clone, install the hook once: `cp hooks/pre-commit .git/hooks/pre-commit`.

## License

[MIT](LICENSE) © 2026 Biggoan1
