# Runbook — New Starter Onboarding (Microsoft 365)

The standard path for "we've got someone starting Monday" tickets, using
`New-SdClientUser`.

## Gather first (saves the second phone call)

From the client contact, before touching the tenant:

- Full legal name (and preferred name if different — display name follows
  preferred, UPN follows the client's pattern)
- Job title and department
- Start date
- Mobile number (for MFA and the account record)
- Who they mirror: "set her up like Jess" is the most common spec you'll
  get — pull Jess's groups with `Get-SdUserSnapshot` and confirm the list
  with the client rather than blindly copying
- Any extras: shared mailbox access, distribution lists, line-of-business
  app licences

## The build

```powershell
# Read-only + write scopes for user lifecycle work
Connect-MgGraph -Scopes 'User.ReadWrite.All','Group.ReadWrite.All','Directory.Read.All','Organization.Read.All'

Import-Module ./SdKit/SdKit.psd1

# Dry run: confirm the UPN the pattern produces before creating anything.
New-SdClientUser -ClientCode ACME -FirstName Sarah -LastName McMillan `
    -JobTitle 'Conveyancer' -MobilePhone '04xx xxx xxx' `
    -ConfigPath ./config/clients.json -WhatIf

# Then for real:
$result = New-SdClientUser -ClientCode ACME -FirstName Sarah -LastName McMillan `
    -JobTitle 'Conveyancer' -MobilePhone '04xx xxx xxx' `
    -ConfigPath ./config/clients.json

$result.TicketNote   # paste into the PSA
```

The command creates the user (usage location AU, must-change password),
assigns the client's default licence — warning you if the tenant has no
spare seats — and adds the default groups. Everything it did or couldn't
do lands in the ticket note.

## Handover rules

- **Temp password goes out-of-band.** Phone the contact or use the
  password manager share. Never email username and password together.
- **MFA before day one.** Send the enrolment link (aka.ms/mfasetup) via
  the client contact; a new starter locked out at 9am Monday is a bad
  first impression for everyone.
- **Confirm the mailbox provisioned.** It can lag a few minutes behind
  licensing. Send a test email before closing the loop with the client.

## Close-out checklist

- [ ] Ticket note pasted, time entered
- [ ] Temp password handed over securely (note *how* in the ticket, not *what*)
- [ ] Licence assigned (or purchase raised and noted)
- [ ] Extras done: shared mailboxes, DLs, LOB apps
- [ ] Follow-up task booked for the start date to confirm first sign-in
