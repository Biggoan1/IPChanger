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
  `.gitignore`, `resumeVibing.ps1` (post-reboot orientation + session resume).

## Pending / next steps

1. **TEST** the merged app: run `.\Set-NetworkConfig.ps1` (self-elevates via UAC).
   Confirm the adapter list, then try DHCP toggle + Apply on a test adapter.
2. **BUILD** the exe: `.\build.ps1` ( add `-Sign` to sign with the code-signing cert ).
3. **TEST the installer:** `.\SetNet-Install.ps1 -Action Install` (and `-Action Uninstall`).
4. **RENAME** the exe `Set-NetworkConfig.exe` → `IPChanger.exe` once verified: flip the two
   `# TODO` markers in `build.ps1` (`-OutputExe`) and `SetNet-Install.ps1` (`$ExeName`).
5. **PUSH** when it all works: `git push -u origin main`.
   If the GitHub repo already has commits: `git pull --allow-unrelated-histories origin main` first.

## Open considerations (not yet decided)

- **Elevation vs. group:** the app elevates to full admin via UAC, yet the
  `Network Configuration Operators` group is meant to let *non-admins* change IP
  *without* elevation. Fine if operators are local admins; otherwise the UAC prompt
  blocks them. Revisit the elevation model if that's a real scenario.
- **Disabled adapters now appear:** applying a static IP to a *disabled* adapter will
  error (surfaced in the GUI); disconnected-but-enabled adapters work fine.

## Git / repo state

- Branch `main`; remote `origin` = https://github.com/Biggoan1/IPChanger.git
- Committed locally; **not pushed yet** (waiting on the test pass above).
- The compiled `.exe` is a build artifact and is **not** committed (see `.gitignore`).
