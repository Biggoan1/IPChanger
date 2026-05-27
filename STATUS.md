# Status — where things stand

_Last updated: 2026-05-27_

Snapshot of the IPChanger 4.0 work so anyone (or future me) can pick up cold.
For what the app is and how to build/install it, see [README.md](README.md).

## Done

- **Merged the launcher into the app.** `Set-NetworkConfig.ps1` now self-elevates
  (relaunches via UAC when not already admin); the old `Launch-NetworkConfig.ps1` is gone.
- **Adapter list changes:** shows **all physical adapters** (connected or not) and
  excludes **Wi-Fi**, **WWAN/cellular**, and **Hyper-V/VMware vEthernet** switches.
- **Installer** (`SetNet-Install.ps1`) targets **`C:\Program Files\IPChanger`** with
  public Desktop + All-Users Start Menu shortcuts; logs to `C:\ProgramData\IPChanger\Logs`.
- **Scaffolding:** `build.ps1` (ps2exe + Authenticode signing), `README.md`,
  `.gitignore`, `resumeVibing.ps1` (post-reboot orientation + session resume), `LICENSE` (MIT).
- **Naming/metadata:** ps2exe compiles `Set-NetworkConfig.ps1` → **`IPChanger.exe`**;
  metadata/copyright is `Biggoan1` (no employer branding); gear/plug icon embedded.
- **Apply fix:** static apply now disables DHCP first (fixes the PolicyStore/Dhcp error).
- **Gateway auto-fill:** gateway = network + 1 (e.g. `x.x.x.1` for /24) as IP/CIDR change.
- **Versioning:** `VERSION` file is the single source; pre-commit hook auto-bumps the patch;
  `build.ps1` stamps it; the app shows it bottom-right so you can confirm the running build.
- **Pushed** to GitHub (`origin/main`).

## Build / deploy workflow

The build is **not** run on the dev machine. To ship: copy the source to USB, then in prod
run `.\build.ps1 -Sign` — that compiles `IPChanger.exe` (reading `VERSION`) and signs it with
the code-signing cert. Then `.\SetNet-Install.ps1 -Action Install` deploys it to
`C:\Program Files\IPChanger`. Confirm the version shown on the form matches `VERSION`.

## Pending / next steps

1. **TEST** with a freshly built exe (verify the version label changed) on a real adapter:
   static Apply, Enable DHCP, and the gateway auto-fill.
2. **SIGN + install** at the prod move per the workflow above.

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
