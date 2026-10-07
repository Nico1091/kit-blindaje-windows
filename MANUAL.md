# Manual of the hardening and privacy kit for Windows 11

## 1. What it is

The kit hardens Windows 11 Home or Pro in nine layers, reduces telemetry without breaking updates, locks down the firewall, resolves domain names on the PC itself without going through third parties, and adds a private browser, the Browser, that reaches the Internet through the Tor network. It is driven by double-click buttons. Every script offers a dry run, saves a backup before changing anything, and the ones that touch the network undo themselves after ten minutes unless the user confirms the connection still works.

The kit contains no credentials, keys, device addresses or data about anyone. Paths are worked out on each PC from the user's folder.

## 2. Package layout

```
kit-blindaje-windows\
├── INSTALL-KIT.bat          copies everything into place (the only install step)
├── MANUAL.md                this document
├── TERMS.md · LICENSE · SECURITY.md   terms of use, license, how to report a vulnerability
├── PROTECTION-GUIDE.md      technical detail of every measure
├── Run-All.ps1              orchestrates the full hardening
├── Install.ps1              registers the system launchers
├── Harden.ps1 · Restore.ps1 · Audit.ps1 · Audit-Admin.ps1
├── Movie-Grade.ps1          local DNS, random MAC, local error reports
├── Remaining-Telemetry.ps1 · Windows-Services.ps1 · Disable-Microsoft.ps1 · Disable-Edge.ps1
├── Setup-Firewall.ps1 · Network-Blocker.ps1 · Paranoia.ps1 · IP-Always-Hidden.ps1
├── Find-Backdoors.ps1 · Migrate-Launchers.ps1 · Checker.py
├── Setup-Browser.ps1 · Smiley-Browser.ps1 · Update-LibreWolf.ps1
├── lib\                     shared core (log, backups, auto-revert)
├── Browser\                 launcher, Tor engines, start page and configuration
└── buttons\                 the eleven double-click shortcuts
```

Backups, logs and reports are created on the user's PC, inside `%USERPROFILE%\Security`, and are never part of the package.

## 3. Requirements

- Windows 11 Home or Pro and an administrator account.
- Python 3.11 or later, for the Browser and the checker.
- For the Browser: WSL with an Ubuntu distribution and the `tor` package installed inside it (`sudo apt install tor`). LibreWolf is installed by the setup itself through `winget`.

## 4. Installation

1. Create a Windows restore point.
2. Double-click `INSTALL-KIT.bat`. It copies the kit to `%USERPROFILE%\Security` and the buttons to a "Hardening kit" folder on the Desktop. It does not ask for administrator rights or change any setting.
3. Open that Desktop folder and run **HOW IS MY PC** first.
4. If the report looks right to you, run **HARDEN MY PC**.

## 5. The buttons

| Button | What it does | Changes the PC |
|---|---|---|
| HOW IS MY PC | Audit with a score per area | No |
| CHECK MY PROTECTION | Checks DNS, firewall, Tor and Browser | No |
| WHAT WOULD IT BLOCK | Lists what ransomware folder protection would have blocked in the last 14 days | Only if you accept switching it to block |
| HARDEN MY PC | Applies the nine layers, with a ten-minute auto-revert | Yes |
| REPAIR WHAT WAS MISSED | Re-runs only the ports layer (for installs hardened before a firewall-rule bug was fixed) | Yes |
| SET UP FIREWALL | Inbound closed and minimal outbound | Yes |
| MOVIE-GRADE PROTECTION | Local DNS (Unbound), random MAC, local error reports | Yes |
| REMOVE MOVIE-GRADE PROTECTION | Undoes movie-grade protection | Yes |
| SET UP BROWSER | Installs and configures the Browser | Yes |
| UPDATE BROWSER | Updates LibreWolf and keeps the configuration | Yes |
| IF I LOSE INTERNET | Restores the firewall and services from the latest backup | Yes |

All of them ask for administrator permission on their own when they need it.

## 6. Manual use, without buttons

Open PowerShell as administrator and go to the kit folder:

```powershell
cd $env:USERPROFILE\Security
Set-ExecutionPolicy -Scope Process Bypass
```

Without `-Apply`, the scripts that support it only show what they would do.

| Task | Command |
|---|---|
| Dry run of the full hardening | `.\Run-All.ps1 -DryRun` |
| Full hardening | `.\Run-All.ps1` |
| Harden only some layers | `.\Harden.ps1 -Apply -Layers defender,ports,privacy` |
| Change the auto-revert delay | `.\Harden.ps1 -Apply -RevertMinutes 15` |
| Audit | `.\Audit.ps1` |
| Restore from a backup | `.\Restore.ps1 -ListBackups` then `.\Restore.ps1 -Backup <name>` |
| Emergency restore | `.\Restore.ps1 -Emergency` |
| Movie-grade protection | `.\Movie-Grade.ps1 -Apply` (DNS only: `-DnsOnly`) |
| Remove movie-grade protection | `.\Movie-Grade.ps1 -Revert` |
| Remaining telemetry | `.\Remaining-Telemetry.ps1 -Apply` |
| Windows services | `.\Windows-Services.ps1 -Apply` |
| Firewall | `.\Setup-Firewall.ps1` |
| Look for backdoors | `.\Find-Backdoors.ps1` |
| Set up the Browser | `.\Setup-Browser.ps1` |

Almost every script that changes something accepts `-Revert` to undo it: `Disable-Edge`, `Disable-Microsoft`, `Network-Blocker`, `Smiley-Browser`, `Setup-Firewall`, `IP-Always-Hidden`, `Paranoia`, `Windows-Services` and `Remaining-Telemetry`.

## 7. The Browser

The Browser is LibreWolf with its own configuration and a yellow smiley as its icon. It reaches the Internet through Tor, which runs inside WSL, and does not use your ISP's DNS. It deletes cookies and cache on close, except for the domains listed in `KEEP_SESSIONS` inside `Browser\launch_browser.pyw`, where you add the sites whose session you want to keep.

It ships with direct entry to Tor. To use WebTunnel bridges, paste them into `~/.smiley/bridges.sh` inside WSL and set `"entry": "bridge"` in `Browser\speed.json`. Sites that reject the whole Tor network go in `Browser\direct.txt` (they go out with your real IP, only those), and sites that block by country, in `Browser\chosen_exit.txt`, on the `countries:` line.

## 8. Warnings: consequences of using it

- **It changes system settings.** The kit touches the firewall, services, the registry and local policies. Every change leaves a backup, but if something fails the PC may lose Internet until you press **IF I LOSE INTERNET**.
- **Some features stop working.** File and printer sharing, casting to a TV, Wi-Fi Direct, Remote Desktop, Phone Link, the Xbox Game Bar and apps that open Edge on their own may fail or need to be re-enabled by hand.
- **Reducing telemetry has a price.** Microsoft may limit features or ask for extra verification on accounts that report little. That is why the kit does not block Microsoft domains, and even so the risk is not zero.
- **Tor is not for everything.** Many sites show captchas or block the Tor network. Banks, wallets and payment platforms may block or freeze an account accessed from Tor: do not use them from the Browser. Tor hides your IP, but it does not make anonymous someone who signs in with their name, and what is illegal stays illegal. Check that using Tor is legal in your country.
- **A random MAC** makes networks with MAC filtering or a captive portal treat the PC as new and ask you to sign in again.
- **The local DNS** depends on Unbound running. If it stops, pages will not open until it is restarted or removed with **REMOVE MOVIE-GRADE PROTECTION**.
- **Do not use it on work, school or third-party managed computers** without written permission from the administrator.
- **Back up your personal files.** The kit's backups cover the settings it changes, not your documents.
- **Your antivirus may flag the scripts.** Tools that change the firewall and registry often trigger Defender or SmartScreen warnings. Download only from this repository, read the scripts, and never disable your antivirus to run them.
- **No warranty and no liability.** The kit is provided as is. The author is not liable for any damage, data loss or account restriction. Whoever applies it accepts the consequences of the changes on their PC. The binding terms are in `TERMS.md` and the license in `LICENSE` (PolyForm Noncommercial 1.0.0).

## 9. Donations

The kit is free for personal use. If you want to support it, you can donate to these receiving addresses:

- **Bitcoin**, only on the **Bitcoin (BTC)** network: `1ED8zqpXYS4MspjZn29s2Bo4WQLgnMM5yi`
- **Ethereum**, only on the **Ethereum (ERC20)** network: `0x1e47c2a6f0401f4df82bf2c83238608a354da696`

Before donating, keep in mind:

- **Use exactly the network shown.** Anything sent on another network (BEP20, TRC20, Arbitrum or other), or any other coin, sent to these addresses is lost and cannot be recovered.
- **Copy the address from this official repository and check the first and last characters** before sending. Some malware swaps the copied address on the clipboard.
- **Donations are voluntary and non-refundable.** They do not buy support, a warranty or priority.
- **Nobody from the project will ever ask you** for seed phrases, private keys, passwords or verification codes. Anyone who does in the project's name is a scammer.
- The addresses belong to an exchange account. If one changes, the valid one will always be the one in this manual in the official repository.

## 10. Uninstall

1. Press **REMOVE MOVIE-GRADE PROTECTION** if you applied it.
2. In PowerShell as administrator, from `%USERPROFILE%\Security`, run `.\Restore.ps1 -ListBackups` and restore the backup from before hardening with `.\Restore.ps1 -Backup <name>`.
3. Remove the registered launchers with `.\Install.ps1 -Remove`.
4. Delete the `%USERPROFILE%\Security` folder and the "Hardening kit" folder on the Desktop.
