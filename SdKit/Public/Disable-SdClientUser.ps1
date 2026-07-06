function Disable-SdClientUser {
    <#
    .SYNOPSIS
        Offboards a departing user — security first, then tidy-up.

    .DESCRIPTION
        Runs the departure steps in the order that matters when someone has
        just walked out the door:

          1. Disable the account (blocks new sign-ins immediately)
          2. Revoke refresh tokens (kills existing sessions on all devices)
          3. Scramble the password
          4. Remove group memberships (recorded first, for the ticket)
          5. Optionally convert the mailbox to shared (frees the licence
             while keeping the mail history) — needs an Exchange Online
             session; recorded as a manual step if one isn't loaded

        Every action lands in the ticket note, because offboarding is the
        one job where "what exactly was done, and when" gets asked months
        later. Supports -WhatIf.

    .EXAMPLE
        Disable-SdClientUser -UserPrincipalName sarah.m@acmeconvey.com.au -ConvertMailboxToShared -Confirm
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$UserPrincipalName,

        [string]$Client,

        # Convert the mailbox to shared so mail history survives after the
        # licence is reclaimed (shared mailboxes under 50 GB are free).
        [switch]$ConvertMailboxToShared,

        # Who requested the offboarding — goes in the ticket for the audit trail.
        [string]$RequestedBy
    )

    process {
        Assert-SdGraphConnection -RequiredScopes @(
            'User.ReadWrite.All', 'GroupMember.ReadWrite.All'
        ) | Out-Null

        $user = Get-MgUser -UserId $UserPrincipalName -Property 'id,displayName,userPrincipalName,accountEnabled,onPremisesSyncEnabled' -ErrorAction Stop

        # Hybrid identities must be disabled in on-prem AD or they'll sync
        # straight back to enabled. Stop early rather than half-do it.
        if ($user.OnPremisesSyncEnabled) {
            throw ("$($user.UserPrincipalName) is synced from on-premises AD. " +
                   'Disable the account in AD (and let it sync), then re-run this for the cloud-side steps.')
        }

        $actions = [System.Collections.Generic.List[string]]::new()

        # --- 1. Disable sign-in ------------------------------------------------
        if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, 'Disable account')) {
            Update-MgUser -UserId $user.Id -AccountEnabled:$false -ErrorAction Stop
            $actions.Add('Disabled the account (new sign-ins blocked)')
        }

        # --- 2. Kill existing sessions -----------------------------------------
        if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, 'Revoke sign-in sessions')) {
            Revoke-MgUserSignInSession -UserId $user.Id -ErrorAction Stop | Out-Null
            $actions.Add('Revoked refresh tokens (existing sessions will drop within the hour)')
        }

        # --- 3. Scramble the password -------------------------------------------
        if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, 'Reset password to random value')) {
            # Long random password nobody keeps — not even the desk.
            $scrambled = New-SdTempPassword -WordCount 5
            Update-MgUser -UserId $user.Id -PasswordProfile @{
                Password                      = $scrambled
                ForceChangePasswordNextSignIn = $true
            } -ErrorAction Stop
            $actions.Add('Password reset to a random value (not recorded anywhere)')
        }

        # --- 4. Record and remove group memberships ------------------------------
        $groups = @(Get-MgUserMemberOf -UserId $user.Id -All -ErrorAction SilentlyContinue |
            Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' })
        foreach ($group in $groups) {
            $groupName = $group.AdditionalProperties.displayName
            if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, "Remove from group '$groupName'")) {
                try {
                    Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop
                    $actions.Add("Removed from group '$groupName'")
                }
                catch {
                    # Dynamic and role-assignable groups won't allow this —
                    # note it rather than fail the run.
                    $actions.Add("GROUP NOT REMOVED: '$groupName' — $($_.Exception.Message)")
                }
            }
        }

        # --- 5. Mailbox conversion ------------------------------------------------
        if ($ConvertMailboxToShared) {
            if (Get-Command Set-Mailbox -ErrorAction SilentlyContinue) {
                if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, 'Convert mailbox to shared')) {
                    Set-Mailbox -Identity $user.UserPrincipalName -Type Shared -ErrorAction Stop
                    $actions.Add('Converted mailbox to shared — licence can now be reclaimed')
                }
            }
            else {
                Write-Warning 'No Exchange Online session loaded (Connect-ExchangeOnline). Mailbox conversion recorded as a manual follow-up.'
                $actions.Add('MANUAL FOLLOW-UP: convert mailbox to shared via Exchange Online, then reclaim the licence')
            }
        }

        if ($actions.Count -eq 0) {
            Write-Host 'WhatIf run complete — nothing was changed in the tenant.' -ForegroundColor Cyan
            return
        }

        $issueText = "Offboard departing user $($user.DisplayName) ($($user.UserPrincipalName))."
        if ($RequestedBy) { $issueText += " Requested by: $RequestedBy." }

        $note = New-SdTicketNote -Summary "User offboarding — $($user.DisplayName)" `
            -Client $Client `
            -Issue $issueText `
            -Steps $actions.ToArray() `
            -NextSteps 'Reclaim/unassign the licence once mailbox conversion is confirmed',
                       'Confirm mail forwarding/delegate access requirements with the client',
                       'Check for files in OneDrive that the team needs before the 30-day retention lapses',
                       'Remove the user from any third-party apps outside SSO (client to confirm the list)' `
            -Status 'In progress'

        [pscustomobject]@{
            UserPrincipalName = $user.UserPrincipalName
            DisplayName       = $user.DisplayName
            Actions           = $actions.ToArray()
            TicketNote        = $note
        }
    }
}
