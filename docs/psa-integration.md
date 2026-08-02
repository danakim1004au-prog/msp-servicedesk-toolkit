# PSA / Ticketing Integration

SdKit's ticket notes are written to drop straight into whatever PSA the MSP
runs. This doc shows how the `-AsTicketNote` output maps onto the common
platforms — ConnectWise Manage, Datto Autotask, NinjaOne and Syncro — and a
worked end-to-end desk workflow.

The design choice is deliberate: **generate a clean, plain-text note and let
the tech paste it**, rather than binding to one vendor's API. A note that
pastes cleanly into any PSA (and into an email, and into a handover chat)
beats a brittle integration that breaks on the next API version — and it
means the toolkit is useful on day one at a shop running *any* PSA.

## The note → PSA field mapping

Every SdKit note carries a header block and titled sections. They line up
with PSA fields like this:

| SdKit note element | ConnectWise Manage | Autotask | NinjaOne | Syncro |
|---|---|---|---|---|
| `Summary` line | Ticket **Summary** | Ticket **Title** | Ticket **Subject** | Ticket **Subject** |
| Header (client/contact) | Company / Contact | Account / Contact | Organization / Contact | Customer / Contact |
| `Status` | Status (map to board) | Status | Status | Status |
| `Time spent` | **Time Entry** (billable) | Time Entry | Time Entry | Timer / Time log |
| ISSUE + IMPACT | Initial **Description** | Ticket Description | Description | Initial issue |
| STEPS / RESOLUTION | **Internal/Discussion** note | Ticket Note | Ticket Comment | Comment (public/private) |
| `-Escalation` handover | Note + reassign to Tier 2/3 board | Note + reassign queue | Note + reassign | Note + reassign |

**Public vs internal:** paste ISSUE/IMPACT into the client-visible field
and STEPS into the internal note — SdKit already writes STEPS in tech terms
and IMPACT in plain English, so the split is natural.

## Worked example — end-to-end desk workflow

A "can't sign in" call, ConnectWise-style, start to finish:

```powershell
Import-Module ./SdKit/SdKit.psd1

# 1. Pull the facts while the client is on the phone (read-only).
Connect-MgGraph -Scopes 'User.Read.All','UserAuthenticationMethod.Read.All','Directory.Read.All','DeviceManagementManagedDevices.Read.All','AuditLog.Read.All'
$snapshot = Get-SdUserSnapshot -UserPrincipalName jsmith@acme.example.com.au -AsTicketNote

# 2. It's an on-prem AD lockout — unlock, reset, find the source.
$fix = Reset-SdAdAccount -Identity jsmith -Unlock -ResetPassword -Client 'Acme Conveyancing'

# 3. Build the closing note and put it on the clipboard to paste into CW.
$fix.TicketNote | Set-Clipboard
#   -> paste into the ticket's Discussion tab
#   -> add a Time Entry for the minutes spent (the note's header reminds you)
#   -> hand $fix.TempPassword to the user by phone, close as Resolved
```

Escalation path, same clean handover into a Tier 2/3 board:

```powershell
New-SdTicketNote -Summary 'ACME-HV01 host BSOD x2 today' -Escalation -EscalateTo 'Tier 3 board' `
    -Client 'Acme Conveyancing' `
    -Issue 'Hyper-V host blue-screened twice; RDS users dropped.' `
    -Steps 'Collected minidumps','Checked storage controller firmware' `
    -RuledOut 'Not Windows Update — last patch 3 weeks ago, stable since' `
    -NextSteps 'Dump analysis; suspect NIC driver' | Set-Clipboard
#   -> paste into a new note, reassign the ticket to the Tier 3 board
```

## If you *do* want API automation later

The clean-note approach is the sensible default, but each PSA exposes an API
if a shop wants to auto-log notes from a script:

- **ConnectWise Manage** — REST API, `POST /service/tickets/{id}/notes`
  (public/internal flag), plus `/time/entries` for time.
- **Autotask** — REST API, `TicketNotes` and `TimeEntries` entities.
- **NinjaOne** — REST API with ticketing endpoints; also runs scripts on
  endpoints via its RMM, so SdKit commands could be pushed as NinjaOne
  scripts and the output captured.
- **Syncro** — REST API, `POST /tickets/{id}/comment`, and RMM scripting
  similar to Ninja.

A thin `Publish-SdTicketNote -Platform ConnectWise -TicketId 12345` wrapper
around `Invoke-RestMethod` would be the natural next iteration — kept out of
v1 on purpose so the toolkit stays PSA-agnostic and credential-free.

## Why plain-text-first is the right call

- **Portable.** Same note works at a ConnectWise shop and a Syncro shop.
- **No secrets.** No stored PSA API keys to leak; nothing to rotate.
- **Reviewable.** The tech reads the note before it's logged — an API that
  auto-posts can quietly log a half-finished note.
- **Resilient.** PSA API versions change; copy-paste doesn't.
