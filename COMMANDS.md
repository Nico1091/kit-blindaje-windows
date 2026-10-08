# Command guide

Every script in the kit, what it does, whether it changes the PC and what each option means. All of them run from PowerShell opened as administrator, in the kit folder:

```powershell
cd $env:USERPROFILE\Security
Set-ExecutionPolicy -Scope Process Bypass
```

The second line allows running the scripts in that window only; once it is closed, the policy goes back to normal.

General rule: scripts that have the `-Apply` option change nothing unless it is passed; they only show what they would do. Those with `-Revert` undo their own changes from the backup they saved when applying.

---

## Main hardening

### Run-All.ps1
Runs the full hardening in the right order: checks there is Internet before starting, audits, applies the nine layers of `Harden.ps1`, registers the daily restore point and asks at the end whether the connection still works. This is what the **HARDEN MY PC** button runs.

- `-DryRun`: goes through the whole process without changing anything.
- `-RevertMinutes <n>`: minutes the auto-revert waits before undoing network changes if nobody confirms the connection. Default: 10.

```powershell
.\Run-All.ps1 -DryRun
.\Run-All.ps1
```

### Harden.ps1
Applies the hardening by layers, with a prior backup, a connectivity check after each layer and a timed auto-revert. Without `-Apply` it changes nothing.

The nine layers are: `defender` (Defender at maximum, controlled folder access, attack surface reduction rules), `ports` (strict firewall and closing WinRM and the SMB server), `locks` (UAC at maximum, Windows Script Host off, PowerShell 2 removed, no USB autorun), `privacy` (telemetry at minimum, location closed), `stealth` (the PC stops announcing itself on the network and answering ping), `vm` (virtual machines stop seeing the local network), `drivers` (blocks vulnerable drivers used by ransomware), `credentials` (no plain-text passwords in memory, modern TLS only) and `ransomware` (protected folders and restore points).

- `-Apply`: really applies.
- `-Layers <list>`: applies only the given layers, comma-separated.
- `-RevertMinutes <n>`: network auto-revert delay. Default: 10.
- `-NoPrompt`: does not ask for intermediate confirmations.
- `-RandomizeMAC`: also changes the Wi-Fi MAC. Disconnects and reconnects the network.
- `-CutMicrosoftProbe`: turns off Windows' connectivity check. The privacy gain is minimal and the network icon will show "no Internet" even while browsing works.
- `-Orchestrated`: used by `Run-All.ps1` when calling it; no need to type it by hand.
- `-BlockOutbound`: declared but not used by the code yet. It has no effect.

```powershell
.\Harden.ps1
.\Harden.ps1 -Apply
.\Harden.ps1 -Apply -Layers defender,credentials,ransomware
```

### Restore.ps1
Undoes what `Harden.ps1` did. With no options, it lists the backups and fully restores the latest one: firewall, registry and services.

- `-Emergency`: restores only the network, fast and without questions. This is what the **IF I LOSE INTERNET** button runs.
- `-ListBackups`: lists the available backups without restoring any.
- `-Backup <name>`: restores a specific backup.
- `-NoPrompt`: does not ask for confirmation.

```powershell
.\Restore.ps1 -ListBackups
.\Restore.ps1 -Backup <name>
.\Restore.ps1 -Emergency
```

### Audit.ps1
Reviews the security state, scores it by area and writes a report to `Reports\`. Read only: it never changes anything. This is what **HOW IS MY PC** runs.

- `-Cfa`: adds the controlled folder access block log.
- `-Days <n>`: how many days back to review that log.

**WHAT WOULD IT BLOCK** runs `Audit.ps1 -Cfa -Days 14` and then offers to switch folder protection from audit to block.

```powershell
.\Audit.ps1
.\Audit.ps1 -Cfa -Days 7
```

### Install.ps1
Registers the kit's only scheduled task: a daily restore point at 13:00. It installs no monitoring or background processes.

- `-Remove`: deletes that task.

---

## Privacy and telemetry

### Movie-Grade.ps1
Local protection with almost no resource use. Installs Unbound to resolve domain names on the PC itself, querying the root servers directly with no third-party DNS. It also sets a random MAC per Wi-Fi network and keeps error reports on the PC instead of sending them. Without `-Apply` it changes nothing. It does not block Microsoft domains: activation, the Store and Windows Update keep working.

- `-Apply`: applies, with network auto-revert.
- `-Revert`: puts the network and settings back as they were.
- `-DnsOnly`: only rewrites the Unbound configuration, without touching the MAC or the adapter's DNS.
- `-RevertMinutes <n>`: auto-revert delay. Default: 10.
- `-NetworkOnly` and `-Auto`: used by the automatic auto-revert. No need to type them.

```powershell
.\Movie-Grade.ps1
.\Movie-Grade.ps1 -Apply
.\Movie-Grade.ps1 -Revert
```

### Remaining-Telemetry.ps1
Turns off the telemetry left after hardening, using only official switches. Per user: Office, Windows tips and suggestions, PowerShell 7, .NET, VS Code and Claude Code. Per machine: Edge policies and diagnostic tasks. It does not block domains or touch activation, the Store or Windows Update. Without `-Apply` it changes nothing.

- `-Apply` / `-Revert`.
- `-UserOnly`: applies only the per-user part, which does not need administrator rights.

### Windows-Services.ps1
Turns off services almost nobody uses: offline maps, distributed link tracking, the program compatibility assistant and the search indexer, which keeps an index with the names and contents of your files. Without `-Apply` it changes nothing.

- `-Apply` / `-Revert`.

### Disable-Microsoft.ps1
Turns off Windows AI, remaining telemetry and Office extras without touching Word or its security patches. The previous state is backed up.

- `-Revert`: restores what was turned off.

### Disable-Edge.ps1
Makes Edge unusable without uninstalling it: when something tries to open it, the Browser opens instead. WebView2 is left alone, because other applications use it.

- `-Revert`: brings Edge back.

### Paranoia.ps1
Closes what was still leaving the PC towards Microsoft, the Internet or the local network: activity history, cloud clipboard and similar services. It does not touch base telemetry or block Microsoft domains.

- `-Revert`: restores the original state from its backup.

---

## Network and firewall

### Setup-Firewall.ps1
Configures the whole firewall in one pass: inbound closed, surplus rules disabled, remote assistance off and the Browser lock. It exports the configuration before touching anything and can be repeated safely. This is what **SET UP FIREWALL** runs.

- `-Revert`: imports the configuration exported before the change.
- `-NoPause`: does not wait for a key press at the end.

### Network-Blocker.ps1
Blocks ads and malware domains in the local DNS (Unbound) for the whole PC. It does not include Microsoft domains or the sites whose session the Browser keeps. Requires movie-grade protection to be applied.

- `-List <file>`: list of domains to block, in Unbound format. Required when applying.
- `-Revert`: removes the block.

### IP-Always-Hidden.ps1
Puts a lock on the firewall: LibreWolf can only talk to the PC itself, where the Tor entry is, and to the local network. If a setting failed or the browser tried to go out directly, the firewall cuts it and the IP stays hidden.

- `-Revert`: removes the lock.

---

## Browser

### Setup-Browser.ps1
Sets up the whole Browser in one pass: installs LibreWolf, applies its configuration and the smiley icon, disables and redirects Edge, copies the Tor engines to WSL, keeps the Tor exit always on and sets the firewall lock. This is what **SET UP BROWSER** runs.

- `-NoPause`: does not wait for a key press at the end.

### Smiley-Browser.ps1
Puts the smiley icon on the Browser window and stops Start menu search from sending what you type to Bing.

- `-Revert`: removes it.

### Update-LibreWolf.ps1
Downloads the latest official LibreWolf release and puts back the custom parts the installer may delete: the Browser configuration, the policies and the icons. This is what **UPDATE BROWSER** runs.

- `-NoPause`: does not wait for a key press at the end.

### Checker.py
Verifies that everything is still in place: local DNS, Tor engines, direct gate, circuit race and real exit through Tor. Read only. This is what **CHECK MY PROTECTION** runs.

```powershell
python .\Checker.py
```

### Speed tests (Browser	ests)
Measure before changing anything in `speed.json`. The test Tor never touches the Browser engines. See `TOR-PERFORMANCE.md` for the method and what was learned.

- `tor_test.py` (inside WSL): starts a test Tor on port 19060 with a named candidate: `same`, `bridge2`, `conflux2_latency`, `conflux2_throughput`, `exit_region`, `middle_region`, `middle_exit_region`. `REGION` (default `us,ca`) sets the countries.
- `ab_tor.py CANDIDATE [rounds]`: the engine (9050) against the candidate, at the same time and with the same 24 pages. Run `same` first as the A/A control.
- `ab_ports.py A B [rounds]`: two running ports against each other, for example `9070 9050` to check that the circuit race still helps.

```powershell
cd .\Browser	ests
python .b_tor.py same
python .b_tor.py middle_region
python .b_ports.py 9070 9050
```

### Browser configuration files
- `Browser\launch_browser.pyw`, list `KEEP_SESSIONS`: domains whose session is kept on close.
- `Browser\direct.txt`: sites that reject the whole Tor network and go out with your real IP. Only those sites.
- `Browser\chosen_exit.txt`: sites that block by country; they go through Tor, but only through relays in the countries on the `countries:` line.
- `Browser\speed.json`: Tor entry (`direct` or `bridge`) and speed parameters; each block has an `_about` note.

After changing any of them, close and reopen the Browser.

---

## Diagnostics

### Find-Backdoors.ps1
Looks for backdoors and persistence mechanisms: accounts, authorized SSH keys, authentication packages, startup entries, tasks and services. Read only. Leaves its report in `Reports\`. As administrator it sees everything; without rights it skips what is protected.

### Audit-Admin.ps1
Repeats the digital-signature audit including the system's protected processes, which do not show their path without rights. Leaves its report in `Reports\`.

### Migrate-Launchers.ps1
Replaces known `.vbs` launchers with shortcuts that do not need Windows Script Host, so the `locks` layer can turn it off without breaking them. If it finds none of those launchers, it does nothing. Without `-Apply` it only shows what it would do.
