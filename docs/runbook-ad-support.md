# Runbook — Windows Server & Active Directory Support

The on-prem half of an SMB fleet still runs on Active Directory, and the
desk lives in it: lockouts, password resets, domain joins, mapped drives
and Group Policy. `Reset-SdAdAccount` automates the most common ticket;
this runbook covers the surrounding server-side work with the actual
commands.

Everything here runs from a domain-joined admin box or jump host with RSAT
(the `ActiveDirectory` PowerShell module) installed.

## Account lockout / password reset (the #1 L1 ticket)

Users say "locked out" for a lockout, a disabled account, an expired
password *and* an expired account. Check which it actually is first —
`Reset-SdAdAccount` reports all four and does the unlock/reset in one go:

```powershell
Import-Module ./SdKit/SdKit.psd1

# Investigate + unlock, and find WHERE it locked out:
Reset-SdAdAccount -Identity jsmith -Unlock -Client 'Acme Conveyancing'

# Forgotten password — unlock and reset with a must-change temp password:
$r = Reset-SdAdAccount -Identity jsmith -Unlock -ResetPassword -Confirm
$r.TicketNote        # paste into the PSA
$r.TempPassword      # hand over by phone / password manager — never email
```

**Chase the lockout source.** Repeat lockouts are almost always a stale
saved credential after a password change — a phone's mail app, a mapped
drive, cached Wi-Fi, or a lingering RDP session. The command queries event
**4740** on the PDC emulator to name the offending device. Manually:

```powershell
$pdc = (Get-ADDomain).PDCEmulator
Get-WinEvent -ComputerName $pdc -FilterHashtable @{ LogName='Security'; Id=4740 } -MaxEvents 20 |
    Where-Object { $_.Properties[0].Value -eq 'jsmith' } |
    Select-Object TimeCreated, @{n='Caller';e={$_.Properties[1].Value}}
```

Fix the source device, or the account will lock again within the hour.

## Domain join / rejoin

Joining a freshly run-up machine (see [runbook-pc-runup.md](runbook-pc-runup.md)):

```powershell
# Join and drop the computer object into the right OU in one step:
$ou = 'OU=Workstations,OU=Acme,DC=acme,DC=local'
Add-Computer -DomainName 'acme.local' -OUPath $ou -Credential (Get-Credential) -Restart
```

**"Trust relationship between this workstation and the primary domain
failed"** — the machine's secure channel password is out of sync (common
after a restore or a long time offline). Don't rejoin blindly; repair it:

```powershell
# Confirm the secure channel is actually broken:
Test-ComputerSecureChannel -Verbose

# Repair without leaving/rejoining (keeps the same computer object & SID):
Test-ComputerSecureChannel -Repair -Credential (Get-Credential)
# or
Reset-ComputerMachinePassword -Credential (Get-Credential)
```

## Mapped drives not connecting

Work top-down:

1. **Name resolves?** `Test-Connection fileserver` then
   `nslookup fileserver.acme.local` — a DNS miss looks like a "drive down".
2. **Share reachable?** `Test-NetConnection fileserver -Port 445` (SMB).
   A blocked 445 is usually a firewall/AV change, not the server.
3. **Mapping present?** `Get-SmbMapping` and `net use`. Reconnect:
   `New-SmbMapping -LocalPath 'S:' -RemotePath '\\fileserver\shared'`.
4. **Stale credentials?** `cmdkey /list` — a saved credential for the
   server after a password change fails silently. Clear it with
   `cmdkey /delete:fileserver` and let it re-prompt.
5. **Delivered by GPO?** If the drive maps via Group Policy Preferences,
   fix it there, not with a manual `net use` that GP will overwrite next
   refresh.

## Group Policy troubleshooting

```powershell
# What actually applied to this user/computer, and what got filtered out:
gpresult /h "$env:TEMP\gpresult.html" ; Invoke-Item "$env:TEMP\gpresult.html"
gpresult /r /scope computer

# Force a refresh instead of waiting ~90 min:
gpupdate /force
```

Common culprits: WMI filter excluding the machine, the policy linked to the
wrong OU, security-group filtering the user isn't in, or slow-link
detection skipping the policy on VPN. `gpresult /h` shows "Denied" reasons
in plain sight — read those before touching the policy itself.

## Server-side DNS / DHCP checklist

When a whole site reports "internet down" and `Test-SdNetworkStack` points
at DHCP (APIPA addresses) or DNS, check the servers:

**DHCP (on the DHCP server):**

```powershell
Get-DhcpServerv4Scope                                   # scopes present & active?
Get-DhcpServerv4ScopeStatistics -ScopeId 192.168.10.0   # is the pool exhausted?
Get-DhcpServerv4Lease -ScopeId 192.168.10.0 | Measure-Object   # lease count sanity
```
- Pool exhausted → temporary devices camping on leases, or the scope is too
  small. Shorten lease duration or widen the range.
- Scope inactive / server not authorised in AD → activate/authorise.
- Two DHCP servers answering (rogue router handing out leases) → the
  classic cause of intermittent wrong-subnet addresses.

**DNS (on the DC/DNS server):**

```powershell
dcdiag /test:dns                        # DC-side DNS health
Get-DnsServerForwarder                  # forwarders sane (not pointing at a dead resolver)?
Resolve-DnsName outlook.office365.com -Server 127.0.0.1   # can the server itself resolve out?
Get-DnsServerScavenging                 # stale records causing wrong answers?
```
- Clients using the router (not the DC) for DNS → internal names fail,
  logins and shares break. Fix the DHCP-issued DNS server option.
- Forwarder pointing at a decommissioned resolver → external names fail
  while internal ones work.

## Escalate when

- AD replication is failing (`repadmin /replsummary` shows errors) — DC
  health is L3 territory
- FSMO role holder is down, or you're considering seizing a role
- A GPO change would hit a whole site — get it reviewed, test on one OU first
- Anything that smells like AD compromise (unexpected new admin accounts,
  Kerberoasting alerts) → straight up, immediately
