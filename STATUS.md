# Status — where things stand

_Last updated: 2026-05-26_

Snapshot of the IPChanger 4.0 work so anyone (or future me) can pick up cold.
For what the app is and how to build/install it, see [README.md](README.md).

## Done

- **Merged the launcher into the app.** `Set-NetworkConfig.ps1` now self-elevates
  (relaunches via UAC when not already admin); the old `Launch-NetworkConfig.ps1` is gone.
- **Adapter list changes:** shows **all physical adapters** (connected or not) and
  excludes **Wi-Fi** and **WWAN/cellular**.
- **Installer** (`SetNet-Install.ps1`) targets **`C:\Program Files\IPChanger`** with
  public Desktop + All-Users Start Menu shortcuts; logs to `C:\ProgramData\IPChanger\Logs`.
- **Scaffolding:** `build.ps1` (ps2exe + Authenticode signing), `README.md`,
  `.gitignore`, `resumeVibing.ps1` (post-reboot orientation + session resume), `LICENSE` (MIT).
- **Built & named:** ps2exe compiles `Set-NetworkConfig.ps1` → **`IPChanger.exe`** (v4.0.1.0,
  unsigned). Exe metadata is `Biggoan1` (no employer branding).
- **Pushed** to GitHub (`origin/main`).

## Pending / next steps

1. **TEST the installer:** `.\SetNet-Install.ps1 -Action Install` → confirm it lands in
   `C:\Program Files\IPChanger` with Desktop + Start Menu shortcuts; then `-Action Uninstall`.
2. **SIGN at the prod move:** `.\build.ps1 -Sign` (or sign the moved exe) with the
   code-signing cert. The exe is currently **unsigned**.

## Open considerations (not yet decided)

- **Elevation vs. group:** the app elevates to full admin via UAC, yet the
  `Network Configuration Operators` group is meant to let *non-admins* change IP
  *without* elevation. Fine if operators are local admins; otherwise the UAC prompt
  blocks them. Revisit the elevation model if that's a real scenario.
- **Disabled adapters now appear:** applying a static IP to a *disabled* adapter will
  error (surfaced in the GUI); disconnected-but-enabled adapters work fine.

## Git / repo state

- Branch `main`; remote `origin` = https://github.com/Biggoan1/IPChanger.git
- Pushed and in sync with `origin/main`.
- The compiled `.exe` is a build artifact and is **not** committed (see `.gitignore`).
