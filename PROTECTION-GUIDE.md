---
title: PC protection guide
system: Windows 11 Home or Pro
version: 1.4
---

# PC protection guide

## 1. Purpose and scope

This document gathers in one place the security and privacy configuration the kit applies: reducing the telemetry of Windows and installed programs, keeping error reports local, the firewall, name resolution with no third parties, and the "Browser", which reaches the Internet only through the Tor network. For each measure it states what it does, why it was chosen, the exact command that applies it and how to undo it. The last part collects the mistakes made while building it, because they explain several decisions that would otherwise look arbitrary.

The whole system lives in `%USERPROFILE%\Security\`. Every script works as a dry run or saves a backup before changing anything, and almost all accept `-Revert`. Backups are in `Security\Backups\`.

## 2. Principles behind the configuration

The decisions in this document follow six rules. No information should go out to third-party services: that is why third-party DNS resolvers (Quad9, Mullvad and similar) were rejected, as was any VPN, proxy or blocker that depends on someone else's server. Nothing should use resources in the background without explicit permission. Error reports are kept on the PC itself, so the user decides whether to send them. Microsoft domains are not blocked and telemetry is not forced below what Windows Home allows, because a measure like that can get Windows activation or the Microsoft account blocked. The IP address must always stay hidden in the Browser, with no exceptions, and the browser cannot have a direct fallback path. Finally, everything is delivered as a double-click button, not as an instruction that has to be typed.

There is a limit worth keeping in mind from the start: on Windows 11 Home, telemetry cannot be taken to zero. The value `AllowTelemetry = 0` is written to the registry, but only the Enterprise and Education editions honour it; on Home the effective minimum is "Required". What can be done is to turn off the services that collect it and everything optional.

## 3. Quick start

To set up the PC from scratch, or repair it after a major Windows update, press the buttons in this order. Each one elevates itself and can be repeated safely.

1. `HOW IS MY PC.bat`: read-only audit, to see the starting point.
2. `HARDEN MY PC.bat`: base hardening in nine layers (Defender, ports, locks, privacy, stealth, virtual machines, drivers, credentials and ransomware).
3. `MOVIE-GRADE PROTECTION.bat`: local DNS with Unbound, local error reports, random MAC per network.
4. `SET UP FIREWALL.bat`: the whole firewall in one pass.
5. `SET UP BROWSER.bat`: browser, Edge disabled, Tor always on and the firewall lock.
6. `CHECK MY PROTECTION.bat`: final check in about thirty seconds.

If Internet is lost after any of them, `IF I LOSE INTERNET.bat` puts the network back to the backed-up state. The firewall and Browser scripts also carry their own ten-minute auto-revert.

## 4. Windows and program telemetry

### 4.1 Collection services

`DiagTrack` (Connected User Experiences and Telemetry) and `dmwappushservice` are stopped and disabled. Check with:

```powershell
Get-Service DiagTrack, dmwappushservice | Select-Object Name, Status, StartType
```

`Windows-Services.ps1` also turns off `MapsBroker` (offline maps), `TrkWks` (distributed link tracking), `PcaSvc` (compatibility assistant, which reports to Microsoft) and `WSearch` (the search indexer, whose index can take several gigabytes). The indexer is genuine Microsoft software; it is turned off for resource use and privacy, not because it is malicious. A major update may re-enable it: `HOW IS MY PC.bat` warns when that happens, and it is enough to run the script again.

```powershell
Stop-Service WSearch -Force; Set-Service WSearch -StartupType Disabled
```

### 4.2 Remaining telemetry (`Remaining-Telemetry.ps1`)

This script turns off about forty items. In Office, the policies `sendtelemetry=3`, `qmenable=0`, feedback and the OSM agent, plus `usercontentdisabled=2` and `downloadcontentdisabled=2` in `HKCU\Software\Policies\Microsoft\Office\16.0\common\privacy`. In Edge, sixteen policies in `HKLM\SOFTWARE\Policies\Microsoft\Edge`, among them `DiagnosticData=0`, `PersonalizationReportingEnabled=0`, `CopilotPageContext=0` and `TrackingPrevention=3`. Five collection scheduled tasks: `MareBackup`, `Autochk\Proxy`, `Device`, `Device User` and `MapsToastTask`. Per user, the variables `POWERSHELL_TELEMETRY_OPTOUT=1` and `DOTNET_CLI_TELEMETRY_OPTOUT=1`; in VS Code, `telemetry.telemetryLevel = off`; in Claude Code, `DISABLE_TELEMETRY` and `DISABLE_ERROR_REPORTING`. Undo with `Remaining-Telemetry.ps1 -Revert`.

### 4.3 Microsoft extras (`Disable-Microsoft.ps1`)

It disables `WSAIFabricSvc`, `whesvc` and `InventorySvc`, seven Office tasks, Click to Do, CrossDeviceResume and the welcome notices, and uninstalls the new Outlook and the Teams add-in. `ClickToRunSvc` and the two Office update tasks are kept on purpose, because Word depends on them.

PC makers (Intel, ASUS, Dell, HP, Lenovo and others) often ship their own telemetry services. The kit does not touch them, because they differ on every machine; `Find-Backdoors.ps1` and `HOW IS MY PC.bat` list what starts with Windows so you can decide.

### 4.4 Extra privacy (`Paranoia.ps1`)

It turns off activity history and the cloud clipboard, peer-to-peer Delivery Optimization (`DODownloadMode=0`), Find my device, Recall and Copilot, online speech recognition and the language list Windows exposes to web pages. On the local network it disables LLMNR, mDNS, NetBIOS on every adapter and proxy auto-discovery (WPAD). Defender stops uploading samples without asking (`Set-MpPreference -SubmitSamplesConsent 2`) and keeps protecting just the same. IPv6 switches to random temporary addresses:

```powershell
netsh interface ipv6 set privacy state=enabled
netsh interface ipv6 set global randomizeidentifiers=enabled
```

The script records the original value of each of its 29 settings before changing it, and `-Revert` puts them back.

## 5. Windows error reports

Reports are generated, but not sent. `Movie-Grade.ps1` sets, in `HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting`, `ForceQueue=1` (keep them queued locally) and, in its `Consent` subkey, `DefaultConsent=1` (always ask), and enables `LocalDumps` so that dumps of programs that crash stay on disk. The `WerSvc` service is set to manual. The Reliability Monitor (`perfmon /rel`) shows them, and they can be sent to Microsoft one by one from there if you wish.

## 6. Network stack

These are hardening commands for the TCP/IP stack; the kit leaves the original values in its backup.

```powershell
netsh interface ipv4 set global icmpredirects=disabled
netsh interface ipv6 set global icmpredirects=disabled
netsh interface ipv4 set global sourceroutingbehavior=drop
netsh interface ipv6 set global sourceroutingbehavior=drop
netsh interface isatap set state disabled
netsh interface 6to4 set state disabled
netsh interface teredo set state disabled
```

ICMP redirects would let a third party divert traffic; source routing lets a packet dictate its own path; ISATAP, 6to4 and Teredo are tunnels that are not used. The registry also gets `DisableIPSourceRouting=2`, `EnableICMPRedirect=0` and `PerformRouterDiscovery=0`, the last one only for IPv4: IPv6 router discovery is left alone, because the PC's public IPv6 address comes from it.

## 7. Name resolution: Unbound

The PC does not ask any outside DNS. Unbound, installed as a service, resolves recursively from the root servers and only answers on `127.0.0.1` and `::1`; any other address gets `refuse`. The Wi-Fi and Ethernet adapters point to those two addresses. The configuration is in `C:\Program Files\Unbound\service.conf` and includes query minimisation (`qname-minimisation`), DNSSEC validation and hidden identity and version.

The ad and malware blocker works at this same level: `Network-Blocker.ps1` adds a `block.conf` (for example the StevenBlack list, around 75,000 domains, answered with `always_nxdomain`) through an `include:` line. Before restarting the service it validates the configuration with `unbound-checkconf` and, if that fails, restores the previous one. It deliberately excludes Microsoft domains and the domains whose session the Browser keeps. After any change:

```powershell
Restart-Service unbound; ipconfig /flushdns
```

It is worth understanding the real scope. Unbound stops a DNS provider from building up your history, but its queries to authoritative servers travel unencrypted, so your ISP could see them. That does not affect the Browser, which resolves names inside Tor (section 9); it does affect every other program on the PC.

## 8. Firewall

### 8.1 Expected state

All three profiles are on, with inbound blocked by default, outbound allowed and blocked connections logged in `C:\Windows\System32\LogFiles\Firewall\pfirewall.log`. The rules `Sentinel-Hardening-Local-Subnet`, `Sentinel-No-Ping-IPv4`, `Sentinel-No-Ping-IPv6`, the four `Sentinel-VM-Isolated-*` and the Browser lock exist. `HOW IS MY PC.bat` reports any that are missing.

### 8.2 What `Setup-Firewall.ps1` does

It runs from `SET UP FIREWALL.bat`, in five steps.

**Step 0, backup.** Exports the whole policy with `netsh advfirewall export` to `Backups\` and registers a ten-minute auto-revert task that re-imports it as SYSTEM.

**Step 1, profiles.** Applies the central command of the whole configuration and switches any network marked private to "Public":

```powershell
Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True `
  -DefaultInboundAction Block -DefaultOutboundAction Allow -NotifyOnListen True `
  -LogBlocked True -LogAllowed False -LogMaxSizeKilobytes 32767
```

**Step 2, inbound sweep.** Disables, without deleting them, the inbound rules for network discovery, Wi-Fi Direct, wireless projection, Delivery Optimization, connected devices, cast to device, Teredo, mDNS, file and printer sharing, AllJoyn, remote assistance and desktop, remote event monitor, Windows Media Player sharing and remote administration. Also those of programs that only listen on the PC itself (development tools, local servers and similar), because the firewall does not filter loopback and those rules only add surface. Game rules are moved out of the public profile. It never touches "Core Networking", DHCP or IPHTTPS: a broad rule that reached DHCP would leave the PC without an IP address.

**Step 3, own rules.** Creates or recreates:

```powershell
New-NetFirewallRule -DisplayName 'Sentinel-No-Ping-IPv4' -Direction Inbound -Action Block -Protocol ICMPv4 -IcmpType 8 -Profile Any
New-NetFirewallRule -DisplayName 'Sentinel-No-Ping-IPv6' -Direction Inbound -Action Block -Protocol ICMPv6 -IcmpType 128 -Profile Any
New-NetFirewallRule -DisplayName 'Sentinel-Hardening-Local-Subnet' -Direction Inbound -Action Block -RemoteAddress LocalSubnet -Profile Public,Private
```

Only echo is blocked: ICMP types 3 and 11 still pass, because without them path MTU discovery breaks and some pages stop loading. The local subnet rule stops any device on the home network from starting a connection to this PC; replies to what the PC itself asks for are not affected. If VMware's VMnet1 and VMnet8 adapters exist, they are blocked in both directions. Last, the Browser lock (section 9.4).

**Step 4, services that open ports.** Stops and disables WinRM, LanmanServer, SSDP, UPnP, Remote Registry, Remote Access, Remote Desktop and its helper services, Media Player sharing, function discovery resource publication, link-layer topology, CDPSvc, the peer-to-peer services and `iphlpsvc`, and denies remote desktop and assistance in the registry. LanmanWorkstation is kept: it is the client, without which other people's shared folders cannot be reached. Port 445 may keep showing as listening until the next restart, because the `srv2.sys` driver stays loaded; that is not a fault.

**Step 5, check.** Tests Internet with a direct TCP connection to port 443 of three public addresses, and resolution through Unbound. If there is no Internet, it restores immediately. If there is, it asks you to type `YES` after opening a page; only then is the auto-revert removed. Closing the window without answering means everything is undone after ten minutes. To go back later:

```powershell
powershell -ExecutionPolicy Bypass -File %USERPROFILE%\Security\Setup-Firewall.ps1 -Revert
```

## 9. The Browser

### 9.1 Architecture

The Browser is LibreWolf with its own look (yellow smiley, title "Browser"). No page goes out directly from the browser: the firewall lock stops `librewolf.exe` from talking to any public address, so it can only reach three local gates. A routing filter, written into the browser settings, decides which one each request uses according to the main page that was opened.

1. **Regular Tor**, for everything by default, through the circuit race (127.0.0.1:9070, section 9.7) and, if that fails, directly through 127.0.0.1:9050. A Tor engine in Ubuntu (WSL) enters the network directly or through a WebTunnel bridge, which to your ISP looks like an HTTPS connection to an ordinary page; it then crosses three relays, and each site gets its own circuit and its own exit IP.
2. **Tor with chosen exit (127.0.0.1:9055)**, for sites that block by country rather than for being Tor. It is a second engine with the same entry that only exits through relays in the countries allowed in `Browser\chosen_exit.txt` (`countries:` line). Some web application firewalls reject IPs by country ("Unauthorized Geo IP"); with this engine those sites open and the IP stays hidden.
3. **Protected direct gate (127.0.0.1:9060)**, only for sites that reject the whole Tor network and that you authorize in `Browser\direct.txt`. Through this gate the site sees your real IP. The gate only listens on the PC, checks that the main page is authorized, accepts HTTPS only, refuses any home-network or reserved destination and logs refusals in `Browser\puerta.log`. Only the site's own servers go direct; whatever the page loads from third parties (ads, analytics, other providers) still goes through Tor. On those sites the time and language are your real ones, because a local IP with a foreign time zone is a common anti-fraud alert.

On Windows, Smart App Control blocks the Tor Browser libraries, which is why the engines live in Linux. They reach Windows through `wslrelay`, which only listens on the PC itself: nobody on the local network can reach those ports.

### 9.2 Pieces and where they live

On Windows, inside `Security\Browser\`:

- `launch_browser.pyw` opens the browser, clears cookies and cache except those in the `CONSERVAR` list, writes `route.pac` and the site lists into the preferences, and starts the engines and the gate if missing. A lock file (`.lanzador.lock`) stops two launchers from clearing or opening at once; the browser only counts as open if its profile is in use; and if clearing fails the launcher logs it in `lanzador.log` and opens anyway.
- `tor_watchdog.pyw` checks the four services (9050, 9055, 9060 and 9070) every thirty seconds and restarts whatever goes down. Every two minutes it also opens a test connection through each engine and, after three failures in a row, restarts that engine, because a dead bridge leaves the port open with no way out. Every six hours it asks for a bridge renewal, and logs what it does in `vigia.log`. It is started at sign-in by the task `Browser - Tor always`.
- `direct_gate.py` is the gate and `race.py` the circuit race; `speed.json` holds the target and speed parameters.
- `direct.txt` and `chosen_exit.txt` are the two site lists; `tor-browser.sh` and `tor-chosen.sh` are the Windows copies of the two engines.
- `from_edge.pyw` receives whatever Windows used to send to Edge; `import_edge.py` imports bookmarks, history and passwords from Edge.
- `home.html` is the start page, with DuckDuckGo HTML by default, and `weak-tls.html` the "weak connection blocked" notice.

In the program folder are `defaults\pref\browser.js`, `distribution\policies.json` and the icons; in the profile, `~\.librewolf\librewolf.overrides.cfg`, with the settings and the `lockPref` locks.

In Ubuntu, inside `~/.smiley/`: `tor-browser.sh` (main engine), `tor-chosen.sh` (chosen-exit engine), and optionally `bridges.sh` (bridge management: `aplicar`, `renovar`, `rescatar`, `probar`) with `puentes.txt` (the bridges in use), which you provide yourself. Both engines keep a site's circuit while any of its connections is still open (`KeepAliveIsolateSOCKSAuth`, as in Tor Browser), and with bridges they switch to all of them if the first does not connect within 45 seconds.

### 9.3 Browser settings

**Routing.** Besides the filter described, the PAC file, name resolution through the proxy, direct fallback when the proxy fails (`failover_direct=false`), WebRTC limited to the proxy and HTTP/3 off are all locked with `lockPref`.

**TLS.** Minimum 1.2 and maximum 1.3. The TLS hello is identical to Firefox's, with its seventeen ciphers, so its JA4 fingerprint is that of any Firefox of the same version. Removing ciphers from the hello, or a "TLS 1.3 only" mode, leaves a fingerprint that is not Firefox's, and anti-bot systems score that mismatch as a sign of an automated program. Protection is therefore applied after the hello: the "TLS vigilado" (watched TLS) block cuts any connection in which the server picks a weak cipher (CBC, or RSA key exchange without forward secrecy) or a version older than 1.2, and the tab shows "Weak connection blocked". Exceptions go in `smiley.tls_debil_permitido`, empty by default. Strict certificate pinning, CRLite revocation, HTTPS-only mode, safe renegotiation, downgrade detection and the ban on TLS 1.0 and 1.1 remain on.

**Location and accounts.** On pages that go through Tor, the "Ubicacion oculta" (hidden location) block presents a generic language and the time zone `Atlantic/Reykjavik` (UTC) to the page, frames and workers. The account sites in `CONSERVAR` (mail, study, banking, work, AI tools) see the real time and keep the same IP during the session: they do not get an automatic new circuit, and what they load from third parties travels on a separate circuit. Sites in `direct.txt` also see the real time.

**Cache.** LibreWolf ships with the disk cache off, and clearing every site's cache on each start meant every session downloaded the full code of each page through Tor again. The disk cache is on, capped at 512 MB, and the launcher only clears the cache of sites not in `CONSERVAR`.

**Cookies and notices.** Cookies are deleted on close, except for the domains in `CONSERVAR`, which keep their session. History, bookmarks and passwords are kept. Cookie banners are hidden with uBlock Origin, configured by policy with the `fanboy-cookiemonster`, `ublock-cookies-easylist` and `adguard-cookies` lists; the change takes effect on the second start. Updated terms-of-service notices and the rules some chat channels impose before you can type are **hidden** without accepting them: the "Avisos ocultos" (hidden notices) block looks for those exact phrases every second, takes the smallest block containing the text and an accept button, and hides it with `display:none`. It deletes nothing, clicks nothing and never touches a block with more content, such as the chat column. It does not touch sign-up forms or footers either. If a channel requires accepting its rules before you can type, its chat may not send messages.

### 9.4 What `Setup-Browser.ps1` does

It runs from `SET UP BROWSER.bat` and only adds what is missing. First it checks the requirements: Python, the pieces in `Browser\`, LibreWolf (installed with winget if absent) and its digital signature, and that Unbound is running. Then it restores `browser.js`, without which none of the privileged settings run; the smiley icons; and `policies.json` from `Backups\` if it differs, since a LibreWolf update may overwrite it. It checks that the overrides contain the proxy, remote resolution and the TLS version.

Next it disables Edge without uninstalling it. It closes its processes and redirects its executable through the *Image File Execution Options* key:

```powershell
$ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe'
Set-ItemProperty $ifeo Debugger '"...\pythonw.exe" "%USERPROFILE%\Security\Browser\from_edge.pyw"'
```

From then on, anything Windows sends to Edge, a link or a PDF, opens in the Browser, maximized and in front. It applies eighteen Edge policies (no startup boost, no background mode, no diagnostic data, no Copilot or sidebar), removes its shortcuts while keeping a copy, pins the Browser to the taskbar and removes Bing from Start menu search. WebView2 is left alone, because other apps (WhatsApp, Windows search) use it.

Then it creates the firewall lock: an outbound rule that stops `librewolf.exe` from talking to any public IPv4 address or to `2000::/3` on IPv6. In testing, a forced direct connection was blocked in under 200 ms.

After that it checks the engine exists in WSL, registers the task `Browser - Tor always` if missing (at sign-in, without privileges, restart every minute), restarts it so the latest watchdog runs, waits up to four minutes for 9050 to open and confirms the exit through Tor:

```powershell
curl.exe --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip
```

Finally it installs `tor-chosen.sh` in Ubuntu and waits for the chosen-exit engine (9055) and the direct gate (9060) to listen. If anything fails, the final summary lists it.

### 9.5 Measured performance

With a profile already in use (full cache and uBlock lists downloaded), live-stream sites connected their chat in about 5 to 9 seconds and started video in about 6 to 10 seconds at 720p; a geo-filtered portal opened through the chosen exit in 1.7 to 5.3 seconds across five different circuits. A single Tor circuit delivers about 0.7 MB/s; three at once, about 1.4 MB/s, with a lot of variation depending on the exit. Tests with a freshly created profile exaggerate the times, because uBlock downloads all its lists before letting anything through.

Routing each site's video over its own circuit was tested and discarded: some players (Twitch, "Error #2000") fail if the video comes from a different IP than the page. The setting stays off (`smiley.pesado`).

### 9.6 Known limits

Some sites reject the whole Tor network (some government portals, some shops, Stack Overflow) and would only open through the direct gate, which requires your authorization site by site. Google asks for a captcha. A site that only offers CBC ciphers and also rejects Tor would need the direct gate plus a "TLS vigilado" exception. Mojeek does not answer through Tor, which is why DuckDuckGo HTML is used. If the browser is opened any way other than through the launcher, pages do not load: that is the intended behaviour, not a fault.

### 9.7 Speed: target, circuit race and tuning

Speed is governed by a measurable target and parameters, not by guesswork. Everything lives in `Browser\speed.json`. The `objetivo` block sets the response-time target, measured as seconds to the page's first byte when opening a new site: median of 1.5 s or less, the slowest 10 % at 4 s or less, and at most 2 % of responses over 10 s. The `carrera` and `navegador` blocks hold the parameters of each optimization.

Four pieces act on response time. The **circuit race** (`Browser\race.py`, 127.0.0.1:9070) sits between the browser and Tor: on the first connection to each site it sends the browser's TLS hello over two circuits at once and keeps the first one whose server answers. After that, the whole site stays on that circuit, because some sites fail if the same site goes out through different IPs; the site's other connections wait for the winner instead of competing. If the race does not answer, the browser falls back to Tor without it, and there is never a direct exit. The **automatic new circuit** switches a site to a new circuit when its page takes longer than `lento_ms` (7 s) to answer, and retries over another circuit a request that did not answer within `atasco_ms` (12 s), at most twice a minute; Ctrl+Shift+L does it by hand. Text is shown after 200 ms even if the page's font has not arrived (`fuentes_ms`). And open connections are kept for ten minutes so the TLS hello is not repeated when returning to a site.

On account sites the automatic new circuit does not act: webmail used to change exit IP several times per session, because Tor retires a site's circuit when a request hangs fifteen seconds at the exit, and what the page loaded from third parties travelled over that same circuit. Also, after ten minutes Tor stopped using a circuit for new connections even while the site was still open, until the engines adopted `KeepAliveIsolateSOCKSAuth`. On account sites, Ctrl+Shift+L still gives a new circuit by hand.

Tuning showed the limit is physical. The best configuration, two circuits at once in "saludo" mode, gave a median of 2.4 s, a p90 of 4.2 s and 4.2 % slow responses; Tor alone, over the same test, gave 2.5 s, 8.8 s and 9.9 %. The race cuts long waits by more than half, but does not lower the median. Three Tor settings were discarded with data: two bridges with Conflux made response worse; Tor does not accept a `CircuitStreamTimeout` below 10 s; and restricting relays to one region prevented connecting. Opening a new site takes about three round trips over four hops (entry and three relays), 0.6 to 0.8 s each, and with a shared public bridge, when that bridge saturates no circuit escapes it.

## 10. Mistakes made and lessons

This section collects the failures found during construction. Several were silent and only surfaced when reviewing the result.

**The first hardening left 78 rules open without warning.** `Get-NetFirewallRule -DisplayName X -Direction Inbound` is not a filter but a PowerShell error, because those parameters belong to different sets; an empty `catch` turned it into a zero. Also, Spanish Windows group names carry accents and the ASCII code matched none of them. Since then, queries use a single criterion, filtering is done with `Where-Object` comparing without accents, and no `catch` around a count may stay silent. The same review found that `-EnableInsecureGuestLogons` does not exist in `Set-SmbServerConfiguration` and voided the whole command; SMB settings are applied one at a time. `REPAIR WHAT WAS MISSED.bat` re-runs the ports layer for installs hardened before this fix.

**The anti-ping rules were missing.** The firewall script now creates them and checks each rule separately.

**Hardening overwrote the local DNS.** `Harden.ps1` set Cloudflare's DNS even while Unbound was running, and DoH never actually activated: queries travelled unencrypted until it was fixed.

**Ten-second Wi-Fi drops.** Unbound's `private-address: fd00::/8` line removed the IPv6 answer for `dns.msftncsi.com`; Windows believed there was no Internet and reset the driver. Fixed with `private-domain: "msftncsi.com"`.

**Configurations emptied by accident.** `[regex]::Replace(text, pattern, replacement, 1)` treats the 1 as an option, not a limit, and replaced every brace in a VS Code `settings.json`; it was restored from backup. `New-Item -Force` on an existing registry key leaves it empty; `Smiley-Browser.ps1` and `Disable-Edge.ps1` used it on existing keys and were fixed to create the key only if missing. A backup rewritten on every pass ends up storing already-hardened values as originals; `Paranoia.ps1` merges instead of rewriting.

**Mandatory TLS 1.3 broke some sites.** Firefox has no per-site TLS version exception; the fix was TLS 1.2 with the "TLS vigilado" protection described in section 9.3.

**Tor stopped starting.** A clean-up left `UseBridges 1` with no `Bridge` line, and Tor refuses to start in that state. The built-in bridges were saturated (obfs4), dead (default WebTunnel bridges, one with an expired certificate) or went through Microsoft Azure (meek). The direct entry is now the default, and bridges are optional.

**Windows traps that cost time.** A UTF-8 `.ps1` without BOM breaks accented characters in PowerShell 5, which is why the scripts are written in ASCII. Filtering processes by `CommandLine -match` without restricting the name catches the console itself and closes it. `netsh wlan show interfaces` needs the location permission the hardening closes. Quick Edit mode freezes the elevated console if you click in it; Esc releases it. Microsoft's connectivity check fails on networks that inspect TLS, so every Internet test uses raw TCP to port 443.

**Mistakes while building the routing.** The first version of the notices block clicked "Accept", when the goal was to accept nothing. The second removed nodes from the page: React sites can break when nodes are removed from outside, and it also climbed up to the first fixed layer, which can be a whole chat column. Since then the block only hides, and never a block with more content than the notice itself. Trimming ciphers from the TLS hello to "harden" TLS 1.2 changed the browser's fingerprint and made it look like an automated program; the Firefox hello was restored and protection moved to after the hello. The first version of that protection cut the page without showing anything; now it explains what happened. Routing video over its own circuit broke a video player; a `curl` test had suggested otherwise, and the lesson is to test with the real browser. Long texts typed into a Bash console got cut or lost backslashes: changes are applied from patch files.

**Mistakes during speed testing.** An interrupted diagnostic test left `SafeLogging 0` in the Tor engine in use, and for about two hours its local log recorded the names of the sites visited; the line was removed and those names were deleted from the log. Since then diagnostics run on a separate test Tor, never on the one in use. A `pkill -f` command killed itself because its own command line contained the searched text; use `pgrep -f "[t]ext"`. And lowering `CircuitStreamTimeout` was proposed without first checking Tor accepted that value: the log showed it raises it to 10 s.

**Mistakes in the audit.** A supposed memory leak in the notices block was announced as serious and a controlled test ruled it out: Firefox already cut the timers when the page disconnected. Since then, before calling something a fault, it is reproduced with a test that also fails without the fix. The audit did find three real defects. The launcher died without opening the browser if the session file was missing, and since it runs windowless nobody saw the error. The direct gate tried a single address with a twenty-second timeout. And the launcher counted any `librewolf.exe`, including test ones, as the Browser being open. It was also checked that `parent.lock` stays in the profile with the browser closed: the reliable signal is that Windows will not let it be opened.

**A request that was declined.** Disguising the Tor exit IP as one's own machine, to waste the time of whoever scanned it, was declined. That IP belongs to a volunteer who runs the relay: turning it into a decoy directs scans at a third party who did not authorize it, and nothing configured on this PC changes what that relay shows.

## 11. What to review after updates

Every major update should be followed by a review. After updating LibreWolf (with `UPDATE BROWSER.bat`, with the Browser closed), press `SET UP BROWSER.bat`. After a major Windows update, press `HOW IS MY PC.bat` and `SET UP FIREWALL.bat`. After updating your PC maker's drivers, check that their telemetry services have not come back to Automatic. The task `Sentinel-Daily-Restore-Point` creates a restore point every day at 13:00; remove it with `Install.ps1 -Remove` if you do not want it.

## 12. Available buttons

| Button in `buttons\` | Function |
|---|---|
| `HOW IS MY PC` | Read-only audit with a score per area |
| `HARDEN MY PC` | Base hardening in nine layers |
| `WHAT WOULD IT BLOCK` | What folder protection would have blocked; offers to switch it to block |
| `REPAIR WHAT WAS MISSED` | Re-runs the ports layer only |
| `MOVIE-GRADE PROTECTION` / `REMOVE MOVIE-GRADE PROTECTION` | Local DNS, local error reports, random MAC |
| `SET UP FIREWALL` | Full firewall with 10-minute auto-revert |
| `SET UP BROWSER` | Browser, Edge disabled, Tor always on, chosen exit, direct gate and lock |
| `UPDATE BROWSER` | Updates LibreWolf verifying the signature and restores the custom parts |
| `CHECK MY PROTECTION` | Checks TLS, ads, connections, telemetry, the three Browser exits and the direct gate |
| `IF I LOSE INTERNET` | Restores network and firewall from the backup |
