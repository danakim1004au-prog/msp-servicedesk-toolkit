# Runbook — SharePoint Online & Teams Support

The M365 tickets that aren't about identity: "I can't get into the team
site", "a file's locked", "we need a new Team for the new project". These
lean on the SharePoint Online and Teams admin modules rather than Graph.

Connect first:

```powershell
# SharePoint Online admin (tenant admin URL, not a site URL)
Install-Module Microsoft.Online.SharePoint.PowerShell   # once
Connect-SPOService -Url https://acmeconvey-admin.sharepoint.com

# Teams admin
Install-Module MicrosoftTeams   # once
Connect-MicrosoftTeams
```

## "I can't access the team site / document library"

Ninety per cent of the time it's permissions, and the answer is *the group*,
not the site:

1. **Confirm the site and the user's expected access** with the client —
   who owns the site, what should this person see.
2. **Check membership of the backing M365 group.** A Team and its
   SharePoint site share one group; adding someone to the Team's members
   grants the site too. Don't hand out direct SharePoint permissions to fix
   a Teams membership problem — it drifts out of sync immediately.
   ```powershell
   Get-SPOSite -Identity https://acmeconvey.sharepoint.com/sites/settlements | fl Title,Owner,SharingCapability
   Get-SPOUser -Site https://acmeconvey.sharepoint.com/sites/settlements -LoginName jsmith@acmeconvey.com.au
   ```
3. **Sharing blocked?** If it's an external person, `SharingCapability` on
   the site (and the tenant) may forbid it. Change deliberately and note it
   — external sharing settings are a security control, not a nuisance.
4. **Recently offboarded owner?** A site whose only owner was just
   offboarded can strand the whole team — assign a new owner.

## "A file is locked / checked out / someone deleted it"

- **Checked out and stuck:** the library's version history and check-in
  status show who holds it; an admin can discard the check-out to release it
  (warn them they'll lose unsaved changes).
- **Deleted:** two-stage recycle bin. Site recycle bin first (93 days),
  then the site collection recycle bin. Restore from there before assuming
  it's gone.
- **"It won't sync":** OneDrive/SharePoint sync issues are usually path
  length, a file locked by an open app, or too many items — check the sync
  client status before blaming the service.

## "We need a new Team for the new project"

Treat it like a mini onboarding — decide the standard, then apply it:

```powershell
# Create the Team (creates the M365 group + SharePoint site together):
New-Team -DisplayName 'Project Aurora' -Visibility Private -Owner 'pm@acmeconvey.com.au'

# Add members:
Add-TeamUser -GroupId <id> -User jsmith@acmeconvey.com.au -Role Member
```

Confirm with the client: private vs public, who owns it (always ≥2 owners
so it can't be orphaned), naming convention, and whether guests are
allowed. Record the answers in the ticket.

## Common gotchas worth knowing

- **Team membership ≠ SharePoint permission drift.** Always manage access
  through the group/Team. Direct SPO permission grants are how a tenant
  ends up impossible to audit.
- **Guest access is a security decision.** External sharing surfaces in the
  Essential Eight conversation — loop it in, don't just toggle it.
- **Orphaned groups.** Owners leave; membership lingers. A periodic review
  of group/Team owners belongs on the client's cadence, and pairs naturally
  with the offboarding runbook.
- **Retention & deletion.** Deleting a Team deletes the group, the mailbox
  and the SharePoint site. Confirm retention/backup before deleting
  anything a client "doesn't need any more".

## Escalate when

- Tenant-wide sharing or retention policy changes are needed
- A site collection needs restoring from backup
- eDiscovery / legal hold is involved — that's a compliance workflow, not a
  desk fix
