# Ticket Note Standards

Clean ticket notes are the difference between an MSP that scales and one
that lives in one tech's head. These are the standards SdKit's
`New-SdTicketNote` bakes in, written down so the *why* survives too.

## Why we bother

- **The next tech reads it cold.** Sick days, leave, escalations — if the
  note only makes sense to the person who wrote it, it's not a note.
- **Clients read them.** Many PSA portals expose notes. Write like the
  practice manager is reading, because sometimes she is.
- **Disputes get settled by notes.** "When was that changed, and who asked
  for it?" comes up months later. The note is the answer or it isn't.
- **Time entries follow notes.** A clear note justifies the time billed.

## The structure

Every note follows the same skeleton (produced by `New-SdTicketNote`):

| Section | What goes in it |
|---|---|
| Header | Summary, date (dd/MM/yyyy), client, contact, technician, status, time |
| ISSUE | What's wrong, in the client's terms, one or two sentences |
| IMPACT | Who is affected and how badly — this drives priority |
| TROUBLESHOOTING STEPS | Numbered, in the order you did them |
| RULED OUT | (Escalations) What you've eliminated, so nobody re-checks it |
| CAUSE | Root cause once known — "unknown" is an acceptable answer |
| RESOLUTION | What fixed it and how you verified the fix |
| NEXT STEPS | Anything outstanding, owned and dated |

## Golden rules

1. **Never put credentials in a ticket.** Not passwords, not MFA codes,
   not recovery keys. Use the password manager and reference it.
2. **Plain English for anything the client will read.** "The computer
   couldn't get a network address from the server" beats "DHCP lease
   acquisition failure on the NIC".
3. **Verify, then say how you verified.** "Fixed" is weaker than
   "test page printed, client confirmed".
4. **Write the note before the next call.** Ten minutes later half of it
   is gone; by day's end it's fiction.
5. **Timestamps and names on client-side commitments.** "Client will
   confirm by Friday (Sarah, 03/07)" is actionable; "waiting on client"
   forever is not.

## Good vs bad, same job

**Bad:**

> fixed outlook issue

**Good:**

```
=== TICKET NOTE — Outlook prompting for password ===
Date:        01/07/2026 10:42
Client:      Acme Conveyancing
Contact:     Sarah M
Technician:  dana.kim
Status:      Resolved
Time spent:  25 min

ISSUE
  Outlook repeatedly prompting for credentials since this morning.
IMPACT
  Single user; cannot send or receive email.
TROUBLESHOOTING STEPS
  1. Confirmed account not locked in Entra ID
  2. Cleared cached credentials in Credential Manager
  3. Recreated Outlook profile
CAUSE
  Stale credentials cached after last password change.
RESOLUTION
  Profile recreated, mail flow confirmed with test message both ways.
```

Same fix. Only one of them survives contact with next month.
