# Hardening and privacy kit for Windows 11

Nine-layer hardening for Windows 11 Home or Pro, telemetry reduction that does not break updates, a strict firewall, local name resolution with no third parties, and a private browser ("Browser") that reaches the Internet through the Tor network. Everything runs from double-click buttons. No change is applied without a prior backup, and the ones that touch the network undo themselves after ten minutes unless you confirm you still have Internet.

## What it includes

| Button (`buttons` folder) | What it does |
|---|---|
| HOW IS MY PC | Read-only audit with a score per area; changes nothing |
| HARDEN MY PC | Applies the nine layers: Defender, ports, locks, privacy, stealth, virtual machines, drivers, credentials and ransomware |
| WHAT WOULD IT BLOCK | Lists the programs that ransomware folder protection would have blocked, and offers to switch it from watch to block |
| SET UP FIREWALL | Blocks inbound traffic and lets out only what is needed |
| MOVIE-GRADE PROTECTION | Local name resolution (Unbound), random MAC and error reports kept on the PC |
| REMOVE MOVIE-GRADE PROTECTION | Undoes the above |
| SET UP BROWSER | Installs and configures the private browser |
| UPDATE BROWSER | Updates LibreWolf and keeps its configuration |
| CHECK MY PROTECTION | Verifies that everything is still in place |
| REPAIR WHAT WAS MISSED | Re-runs only the ports layer, for installs hardened before a firewall-rule bug was fixed |
| IF I LOSE INTERNET | Restores the firewall and services from the latest backup |

The full guide, with every measure, its command and how to undo it, is in `PROTECTION-GUIDE.md`.

## Requirements

- Windows 11 Home or Pro, with an administrator account.
- Python 3.11 or later, for the Browser and the checker.
- For the Browser: WSL with an Ubuntu distribution and the `tor` package installed inside it (`sudo apt install tor`). LibreWolf is installed with `winget` during setup.

## Installation

1. Create a Windows restore point.
2. Double-click `INSTALL-KIT.bat`. It copies the kit to `%USERPROFILE%\Security` and the buttons to a "Hardening kit" folder on the Desktop, without changing any setting.
3. Run **HOW IS MY PC** first and read the report.
4. If you agree, run **HARDEN MY PC**. The buttons ask for administrator permission on their own.

## Good to know first

- Defender stays on. The kit reinforces it; it does not replace it.
- Windows telemetry is reduced, but Microsoft domains are not blocked: doing so can break updates and activation.
- The Browser ships with direct entry to Tor. Bridges (WebTunnel) are optional: paste them into `~/.smiley/bridges.sh` inside WSL and set `"entrada": "puente"` in `Browser\speed.json`.
- Sites that must go out without Tor go in `Browser\direct.txt`, and sites that block by country, in `Browser\chosen_exit.txt`.
- Configuration keys inside `speed.json` and a few internal names are still in Spanish; the comments next to them explain each one.

## Warnings: consequences of using it

Read this before pressing any button other than HOW IS MY PC.

- **It changes system settings.** It touches the firewall, Windows services, the registry and local policies. Every change leaves a backup, but if something goes wrong you may lose Internet until you press **IF I LOSE INTERNET**.
- **Some features stop working.** File and printer sharing, casting to a TV, Wi-Fi Direct, Remote Desktop, Phone Link, the Xbox Game Bar and apps that open Edge on their own (widgets, help) may fail or need to be re-enabled by hand.
- **Reducing telemetry has a price.** Microsoft may limit features or ask for extra verification on accounts that report little. That is why the kit does not block Microsoft domains, and even so the risk is not zero.
- **Tor is not for everything.** Many sites show captchas or block the Tor network. Banks, wallets and payment platforms may block or freeze an account accessed from Tor: do not use them from the Browser. Tor hides your IP; it does not make you anonymous if you sign in with your name, and whatever is illegal stays illegal. Check that using Tor is legal where you live.
- **A random MAC** makes networks with MAC filtering or a captive portal (hotels, universities) treat you as a new device and ask you to sign in again.
- **Local name resolution** depends on Unbound running. If it stops, pages will not open until it is restarted or removed with **REMOVE MOVIE-GRADE PROTECTION**.
- **Do not use it on work, school or otherwise managed computers** without written permission from the administrator: it may violate their policies and take the PC out of their management.
- **Create a Windows restore point** before you start.

## License and donations

Free for personal use on your own computers. You may modify it for yourself, but not sell it. Provided as is, with no warranty of any kind: you accept the consequences of the changes you apply.

If it helped you, you can support the project with a donation:

- **Bitcoin**, only on the **Bitcoin (BTC)** network: `1ED8zqpXYS4MspjZn29s2Bo4WQLgnMM5yi`
- **Ethereum**, only on the **Ethereum (ERC20)** network: `0x1e47c2a6f0401f4df82bf2c83238608a354da696`

Use exactly that network: anything sent on another network (BEP20, TRC20, Arbitrum or other) is lost and cannot be recovered. Check the first and last characters after pasting the address, because some malware swaps it on the clipboard. Donations are voluntary, non-refundable and do not buy support or a warranty. Only **receiving** addresses are published: nobody from this project will ever ask you for seed phrases, keys or passwords, and anyone who does in the project's name is a scammer.

Full details are in `MANUAL.md` (installation, buttons, manual use, warnings) and `COMMANDS.md` (every script and option explained).
