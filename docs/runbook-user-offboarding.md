# Runbook — User Offboarding (Microsoft 365)

Security first, tidy-up second. `Disable-SdClientUser` runs the cloud-side
steps in the right order; this runbook wraps the judgement calls around it.

## Triage the request

- **Who's asking?** Offboarding requests must come from an authorised
  client contact (owner, practice manager, HR) — not the departing user,
  and not a colleague. Verify against the PSA authorised-contacts list
  and record the requester in the ticket.
- **Friendly or hostile?** For an amicable departure at end of week,
  schedule it. For a termination effective immediately, drop what you're
  doing — the disable-and-revoke steps are minutes that matter.
- **Hybrid check.** If the account syncs from on-prem AD, disable it in
  AD first; the tool will refuse to half-do a hybrid offboard and tell
  you the same.

## The run

```powershell
Connect-MgGraph -Scopes 'User.ReadWrite.All','GroupMember.ReadWrite.All'
Connect-ExchangeOnline   # needed for the mailbox conversion step

Import-Module ./SdKit/SdKit.psd1

$result = Disable-SdClientUser -UserPrincipalName sarah.m@acme.example.com.au `
    -Client 'Acme Conveyancing' -RequestedBy 'J. Smith (Practice Manager)' `
    -ConvertMailboxToShared -Confirm

$result.TicketNote
```

Order of operations (and why it matters):

1. **Disable the account** — blocks new sign-ins immediately.
2. **Revoke sessions** — kills tokens already on phones and laptops;
   disabling alone doesn't log anyone out.
3. **Scramble the password** — belt and braces, and covers apps with
   legacy auth.
4. **Strip group memberships** — recorded in the note first, because
   "what did she have access to?" is a question you'll get later.
5. **Convert mailbox to shared** — keeps the mail history visible to the
   team without paying for a licence.

## Client decisions to capture (don't guess)

- Mail: forward to a colleague, auto-reply, or just shared-mailbox access?
- OneDrive: who needs the files? (Manager gets access by default policy in
  many tenants — confirm, don't assume, and remember the 30-day clock.)
- Mobile: company device to be wiped/returned, or personal device to have
  the work profile removed?
- Third-party apps outside SSO: the client owns this list; prompt them
  for it and record their answer.

## Close-out checklist

- [ ] Account disabled, sessions revoked, password scrambled
- [ ] Groups recorded and removed
- [ ] Mailbox converted to shared; licence reclaimed
- [ ] Mail-flow decision implemented and noted
- [ ] OneDrive access arranged before retention lapses
- [ ] Devices handled (wipe/retire in Intune as applicable)
- [ ] Ticket note pasted with requester recorded
