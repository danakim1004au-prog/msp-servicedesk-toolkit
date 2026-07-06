# SdKit — MSP Service Desk Toolkit

A PowerShell toolkit for the day-to-day work of a Level 1/2 service desk
at a managed services provider: workstation triage, layered network
diagnostics, standardised ticket notes, on-prem Active Directory
unlock/reset, Microsoft 365 user lifecycle, workshop PC run-ups and an
ACSC Essential Eight quick check.

Built the way a real desk works: every command finishes with a
**paste-ready PSA ticket note**, client-specific conventions live in
config (not in scripts), and anything that changes a tenant or a machine
supports `-WhatIf`.

> Portfolio project by Dana Kim. The sample clients are fictional; the
> workflows are the real ones an Australian MSP desk runs every day.

## Job match: Service Desk Officer / MSP L1–L2

This project is built to demonstrate the exact skill set an Adelaide MSP
Level 1/2 Service Desk Officer role asks for. Each requirement maps to
something concrete in this repo:

| Role requirement | Where it's demonstrated |
|---|---|
| **L1/L2 troubleshooting** (desktops, laptops, printers, peripherals) | [`Invoke-SdTriage`](SdKit/Public/Invoke-SdTriage.ps1) — hardware, disk, reboot, event-log and printer snapshot |
| **Microsoft 365 admin** (Exchange Online, SharePoint, Teams, Entra ID, Intune) | [`Get-SdUserSnapshot`](SdKit/Public/Get-SdUserSnapshot.ps1), [`New-SdClientUser`](SdKit/Public/New-SdClientUser.ps1), [`Disable-SdClientUser`](SdKit/Public/Disable-SdClientUser.ps1) + [SharePoint/Teams runbook](docs/runbook-sharepoint-teams.md) |
| **Windows Server, Active Directory** | [`Reset-SdAdAccount`](SdKit/Public/Reset-SdAdAccount.ps1) (unlock/reset + lockout-source lookup) + [AD support runbook](docs/runbook-ad-support.md) (domain join, secure channel, GPO, mapped drives) |
| **Basic networking** (DNS, DHCP, VPNs, switches, firewalls) | [`Test-SdNetworkStack`](SdKit/Public/Test-SdNetworkStack.ps1) 7-layer ladder + [server-side DNS/DHCP checklist](docs/runbook-ad-support.md#server-side-dns--dhcp-checklist) |
| **Building, imaging, configuring, deploying PCs** (run-ups, SOE) | [`Invoke-SdPcRunUp`](SdKit/Public/Invoke-SdPcRunUp.ps1) + [run-up runbook](docs/runbook-pc-runup.md) |
| **Documentation in a PSA/ticketing system** | Every command's `-AsTicketNote`; [ticket-note standards](docs/ticket-note-standards.md) + [PSA integration](docs/psa-integration.md) (ConnectWise / Autotask / NinjaOne / Syncro) |
| **Escalating to senior engineers** | [`New-SdTicketNote -Escalation`](SdKit/Public/New-SdTicketNote.ps1) handover format + [escalation guide](docs/escalation-guide.md) |
| **Translating tech-speak into plain English** | `PlainEnglish` field on every network check, written to read down the phone |
| **ACSC Essential Eight & SMB security** *(highly regarded)* | [`Test-SdEssentialEight`](SdKit/Public/Test-SdEssentialEight.ps1) |
| **IT project coordination** *(highly regarded)* | Onboarding/offboarding/run-up runbooks with pre-flight and close-out checklists |

## Example outputs

Real output from the toolkit — no need to run anything to see what a shift
with SdKit produces:

- 📋 [Workstation triage note](samples/sample-triage-ticket-note.txt) — paste-ready `Invoke-SdTriage` output with low-disk flags
- 🔑 [AD unlock/reset note](samples/sample-ad-ticket-note.txt) — `Reset-SdAdAccount` with lockout-source identified
- 🖥️ [PC run-up report](samples/sample-runup-report.md) — SOE build QA with outstanding items flagged
- 🛡️ [Essential Eight quick check](samples/sample-e8-quickcheck.txt) — workstation security signals with plain-English advice

## What's in the box

| Command | The ticket it answers |
|---|---|
| `Invoke-SdTriage` | "My computer is slow / broken" — one-command workstation snapshot with low-disk flags, pending reboot, event log sweep, printers |
| `Test-SdNetworkStack` | "The internet is down" — 7-layer ladder from adapter to M365 front doors, with plain-English explanations for the client |
| `New-SdTicketNote` | Every ticket — standardised issue/impact/steps/resolution notes, plus an escalation handover mode with a "ruled out" section |
| `Reset-SdAdAccount` | "I'm locked out / forgot my password" — on-prem AD unlock and reset, tells you which device caused the lockout (event 4740 on the PDC) |
| `Get-SdUserSnapshot` | "I can't sign in" — account state, licences, MFA methods, Intune devices and recent sign-in failures from Microsoft Graph |
| `New-SdClientUser` | "New starter Monday" — Entra ID user per client convention, licence (with seat-count check), default groups, temp password |
| `Disable-SdClientUser` | "Departing today" — disable, revoke sessions, scramble password, strip groups, convert mailbox to shared; audit-grade action log |
| `Invoke-SdPcRunUp` | Workshop bench — SOE build: rename, time zone, power plan, winget app set, debloat, TPM/BitLocker/disk QA, markdown report |
| `Test-SdEssentialEight` | "How exposed is this client?" — workstation-level Essential Eight signals, honest about what needs a tenant-level look |
| `New-SdComputerName` | Naming-convention names with the 15-character NetBIOS limit handled properly |
| `Get-SdClientConfig` | Strictly validated per-client config (UPN pattern, licence, groups, naming) |

## Quick start

```powershell
# From the repo root
Import-Module ./SdKit/SdKit.psd1

# Works anywhere, no tenant needed:
New-SdTicketNote -Summary 'Printer offline' -Issue 'Reception printer offline since 9am.' `
    -Steps 'Power-cycled printer','Cleared stuck spooler job' `
    -Resolution 'Test page printed, client confirmed.' -Status Resolved

# On a Windows machine:
Invoke-SdTriage -AsTicketNote
Test-SdNetworkStack -AsTicketNote
Test-SdEssentialEight -AsTicketNote

# Against a client tenant (read-only):
Connect-MgGraph -Scopes 'User.Read.All','UserAuthenticationMethod.Read.All','Directory.Read.All'
Get-SdUserSnapshot -UserPrincipalName someone@client.com.au -AsTicketNote
```

Set up the config once:

```powershell
Copy-Item ./config/clients.sample.json ./config/clients.json          # then fill in real clients
Copy-Item ./config/runup-baseline.sample.json ./config/runup-baseline.json
```

`clients.json` and `runup-baseline.json` are git-ignored — client
identifiers never land in the repo.

## Layout

```
SdKit/                  PowerShell module
  Public/               eleven exported commands, one file each
  Private/              formatters, Graph/AD guards, temp password generator
config/                 *.sample.json committed; real config git-ignored
docs/                   runbooks + desk standards
  ticket-note-standards.md
  escalation-guide.md
  psa-integration.md            (ConnectWise / Autotask / NinjaOne / Syncro)
  runbook-ad-support.md         (AD unlock/reset, domain join, GPO, DNS/DHCP)
  runbook-sharepoint-teams.md
  runbook-network-triage.md
  runbook-pc-runup.md
  runbook-user-onboarding.md
  runbook-user-offboarding.md
samples/                example outputs (triage, AD, run-up report, E8 check)
tests/                  Pester 5 suite (21 tests) for the cross-platform logic
```

## Design notes

- **Ticket notes are the product.** Every diagnostic ends in `-AsTicketNote`
  because work that isn't documented didn't happen — see
  [docs/ticket-note-standards.md](docs/ticket-note-standards.md).
- **Plain English is a feature.** Network checks carry a `PlainEnglish`
  field per layer, written to be read down the phone to a client.
- **Safe by default.** Tenant- and machine-changing commands support
  `-WhatIf`/`-Confirm`; offboarding refuses to half-handle hybrid
  identities; passwords are never written to tickets or logs.
- **Config over code.** UPN patterns, naming conventions, licence SKUs and
  default groups are per-client JSON, validated strictly with error
  messages that name the client and the field.
- **Honest checks.** The Essential Eight sweep marks tenant-level
  strategies as ManualCheck rather than pretending a registry read
  settles MFA or backups.

## Testing

```powershell
Invoke-Pester -Path ./tests
```

The suite covers the pure logic (note formats, naming/NetBIOS limits,
config validation, password generation) and runs on macOS/Linux/Windows —
the Windows-only collectors are exercised on a bench machine or lab VM.

## Requirements

- PowerShell 5.1+ (module) / PowerShell 7+ (tests)
- Windows for `Invoke-SdTriage`, `Invoke-SdPcRunUp`, `Test-SdEssentialEight`
  and the Windows layers of `Test-SdNetworkStack`
- RSAT / the `ActiveDirectory` module for `Reset-SdAdAccount` (run from a
  domain-joined admin box or jump host)
- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/powershell/microsoftgraph/)
  for the M365 commands; ExchangeOnlineManagement for mailbox conversion;
  Microsoft.Online.SharePoint.PowerShell / MicrosoftTeams for the
  SharePoint/Teams runbook
- `winget` on the bench machine for app installs

## Licence

MIT — see [LICENSE](LICENSE).
