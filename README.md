# SdKit

SdKit is a small PowerShell module for common Level 1 and Level 2 service desk work in an Australian managed service provider environment.

I built it around a simple workflow: collect useful facts, make the next action clear, and leave a ticket note that another technician can understand later.

The sample clients are fictional. The commands are intended for lab use and should be reviewed against an organisation's access controls, change process and PSA before being used in production.

## What it covers

| Command | Use |
|---|---|
| `Invoke-SdTriage` | Collect workstation facts such as uptime, disk space, event log errors and printers |
| `Test-SdNetworkStack` | Check the local network, gateway, DNS, HTTPS and Microsoft 365 endpoints |
| `New-SdTicketNote` | Build a consistent PSA note for an incident, request or escalation |
| `Reset-SdAdAccount` | Inspect, unlock or reset an on-premises Active Directory account |
| `Get-SdUserSnapshot` | Review a Microsoft 365 user's account, licences, MFA methods, groups and devices |
| `New-SdClientUser` | Create a new Entra ID user using a client's naming and group conventions |
| `Disable-SdClientUser` | Disable a cloud user, revoke sessions and record offboarding actions |
| `Invoke-SdPcRunUp` | Apply a workshop PC baseline and produce a QA report |
| `Test-SdEssentialEight` | Check workstation signals that relate to the ACSC Essential Eight |
| `New-SdComputerName` | Build a client-compliant computer name within the 15-character NetBIOS limit |
| `Get-SdClientConfig` | Load and validate client-specific conventions from JSON |

All commands that collect diagnostics can return structured objects or a plain text note suitable for pasting into a PSA. Commands that change a machine or tenant support `-WhatIf` and confirmation prompts where appropriate.

## Quick start

From the repository root:

```powershell
Import-Module ./SdKit/SdKit.psd1

New-SdTicketNote -Summary 'Printer offline' `
    -Issue 'Reception printer offline since 9am.' `
    -Steps 'Power-cycled printer', 'Cleared the stuck print queue' `
    -Resolution 'Test page printed and the client confirmed printing was working.' `
    -Status Resolved
```

On an affected Windows workstation:

```powershell
Invoke-SdTriage -Client 'Acme Conveyancing' -AsTicketNote
Test-SdNetworkStack -InternalHost 'dc01.acme.example.com.au' -AsTicketNote
Test-SdEssentialEight -AsTicketNote
```

For a read-only Microsoft Graph snapshot, connect with the scopes required for the data you want:

```powershell
Connect-MgGraph -Scopes @(
    'User.Read.All',
    'UserAuthenticationMethod.Read.All',
    'Directory.Read.All',
    'DeviceManagementManagedDevices.Read.All',
    'AuditLog.Read.All'
)

Get-SdUserSnapshot -UserPrincipalName someone@acme.example.com.au -AsTicketNote
```

## Client configuration

Copy the sample files and keep the real files out of Git:

```powershell
Copy-Item ./config/clients.sample.json ./config/clients.json
Copy-Item ./config/runup-baseline.sample.json ./config/runup-baseline.json
```

The sample values are placeholders. Replace them with approved test tenant values before running any tenant or workstation changing command. Do not place real passwords, recovery keys, tokens or client secrets in this repository.

## Repository layout

```text
SdKit/
├── Public/          exported PowerShell commands
├── Private/         internal guards, formatters and helpers
├── SdKit.psd1       module manifest
└── SdKit.psm1       module loader

config/              sample JSON; real configuration is ignored
docs/                runbooks and ticket note standards
samples/             representative output using fictional data
tests/               Pester tests
.github/             continuous integration workflow
```

## Design decisions

### Ticket notes are part of the output

The module keeps the note format plain text so it can be reviewed before it is pasted into ConnectWise, Autotask, NinjaOne, Syncro or another PSA. See [ticket-note-standards.md](docs/ticket-note-standards.md) and [psa-integration.md](docs/psa-integration.md).

### Client detail stays in configuration

UPN patterns, computer naming conventions, licence SKUs and default groups belong in client configuration, not in the PowerShell functions. `Get-SdClientConfig` validates the required fields before another command uses them.

### Checks show their limits

`Test-SdEssentialEight` is a workstation quick check. It is not a formal Essential Eight maturity assessment. MFA, backups, privileged access and other organisation-level controls need to be checked in the relevant tenant, policy or service reports.

### Changes are reviewable

The tenant and workstation commands use `-WhatIf` or confirmation prompts. Temporary passwords are returned to the caller but are not written to ticket notes. Pass them to the user through an approved out-of-band method.

## Examples and runbooks

The [samples](samples) directory contains representative output for:

* workstation triage
* Active Directory account support
* a PC run-up report
* an Essential Eight quick check

The [docs](docs) directory contains runbooks for:

* network triage
* Active Directory support
* SharePoint and Teams support
* user onboarding and offboarding
* workshop PC run-up
* ticket notes and escalation handovers

## Testing

Install Pester 5 if it is not already available, then run:

```powershell
Invoke-Pester -Path ./tests/SdKit.Tests.ps1
```

The test suite covers module loading, ticket note formatting, computer naming, configuration validation, password generation, triage formatting, Active Directory guards and the cross-platform parts of the network check. Windows-only collectors still need a Windows lab or bench machine for full verification.

## Requirements

* PowerShell 5.1 or later for the module
* Pester 5 for tests
* Windows for workstation triage, PC run-up and the Essential Eight check
* RSAT and the ActiveDirectory module for `Reset-SdAdAccount`
* Microsoft Graph PowerShell SDK for the Microsoft 365 commands
* ExchangeOnlineManagement for mailbox conversion during offboarding
* `winget` on a workshop machine when installing the baseline application set

## Limitations

This is a portfolio project, not a complete PSA or RMM product. It does not store credentials, publish tickets, manage approvals or replace an organisation's change and access process. Test commands against a non-production tenant and a disposable workstation first.

The Essential Eight quick check follows the scope of the ACSC maturity model but deliberately reports several controls as manual checks. See the [official ACSC Essential Eight material](https://www.cyber.gov.au/business-government/asds-cyber-security-frameworks/essential-eight/essential-eight-maturity-model) before treating any result as assessment evidence.

## Licence

MIT. See [LICENSE](LICENSE).
