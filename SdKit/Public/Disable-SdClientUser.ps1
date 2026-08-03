function Disable-SdClientUser {
    <#
    .SYNOPSIS
        Disables a cloud user and records the offboarding actions.

    .DESCRIPTION
        Runs the following cloud-side offboarding steps:

          1. Disable the account (blocks new sign-ins immediately)
          2. Revoke refresh tokens (kills existing sessions on all devices)
          3. Scramble the password
          4. Remove group memberships (recorded first, for the ticket)
          5. Optionally convert the mailbox to shared (frees the licence
             while keeping the mail history) - needs an Exchange Online
             session; recorded as a manual step if one isn't loaded

        Every action lands in the ticket note, because offboarding is the
        one job where "what exactly was done, and when" gets asked months
        later. Supports -WhatIf.

    .EXAMPLE
        Disable-SdClientUser -UserPrincipalName sarah.m@acme.example.com.au -ConvertMailboxToShared -Confirm
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$UserPrincipalName,

        [string]$Client,

        # Convert the mailbox to shared so mail history survives after the
        # licence is reclaimed (shared mailboxes under 50 GB are free).
        [switch]$ConvertMailboxToShared,

        # Who requested the offboarding - goes in the ticket for the audit trail.
        [string]$RequestedBy
    )

    process {
        Assert-SdGraphConnection -RequiredScopes @(
            'User.ReadWrite.All', 'User.RevokeSessions.All', 'GroupMember.ReadWrite.All'
        ) | Out-Null

        $user = Get-MgUser -UserId $UserPrincipalName -Property 'id,displayName,userPrincipalName,accountEnabled,onPremisesSyncEnabled' -ErrorAction Stop

        # Hybrid identities must be disabled in on-prem AD or they'll sync
        # straight back to enabled. Stop early rather than half-do it.
        if ($user.OnPremisesSyncEnabled) {
            throw ("$($user.UserPrincipalName) is synced from on-premises AD. " +
                   'Disable the account in AD (and let it sync), then re-run this for the cloud-side steps.')
        }

        $actions = [System.Collections.Generic.List[string]]::new()
        $failures = [System.Collections.Generic.List[string]]::new()

        # --- 1. Disable sign-in ------------------------------------------------
        if (-not $user.AccountEnabled) {
            $actions.Add('Account was already disabled')
        }
        elseif ($PSCmdlet.ShouldProcess($user.UserPrincipalName, 'Disable account')) {
            try {
                Update-MgUser -UserId $user.Id -AccountEnabled:$false -ErrorAction Stop
                $actions.Add('Disabled the account (new sign-ins blocked)')
            }
            catch {
                $failures.Add("FAILED to disable the account: $($_.Exception.Message)")
            }
        }

        # --- 2. Kill existing sessions -----------------------------------------
        if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, 'Revoke sign-in sessions')) {
            try {
                Revoke-MgUserSignInSession -UserId $user.Id -ErrorAction Stop | Out-Null
                $actions.Add('Revoked sign-in sessions (token invalidation can take effect after a delay)')
            }
            catch {
                $failures.Add("FAILED to revoke sign-in sessions: $($_.Exception.Message)")
            }
        }

        # --- 3. Scramble the password -------------------------------------------
        if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, 'Reset password to random value')) {
            try {
                # Long random password nobody keeps, not even the desk.
                $scrambled = New-SdTempPassword -WordCount 5
                Update-MgUser -UserId $user.Id -PasswordProfile @{
                    Password                      = $scrambled
                    ForceChangePasswordNextSignIn = $true
                } -ErrorAction Stop
                $actions.Add('Password reset to a random value (not recorded anywhere)')
            }
            catch {
                $failures.Add("FAILED to reset the password: $($_.Exception.Message)")
            }
        }

        # --- 4. Record and remove group memberships ------------------------------
        $groups = @()
        try {
            $groups = @(Get-MgUserMemberOf -UserId $user.Id -All -ErrorAction Stop |
                Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' })
        }
        catch {
            $failures.Add("FAILED to enumerate group memberships: $($_.Exception.Message)")
        }
        foreach ($group in $groups) {
            $groupName = $group.AdditionalProperties.displayName
            if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, "Remove from group '$groupName'")) {
                try {
                    Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop
                    $actions.Add("Removed from group '$groupName'")
                }
                catch {
                    # Dynamic and role-assignable groups won't allow this -
                    # note it rather than fail the run.
                    $failure = "GROUP NOT REMOVED: '$groupName' - $($_.Exception.Message)"
                    $failures.Add($failure)
                }
            }
        }

        # --- 5. Mailbox conversion ------------------------------------------------
        if ($ConvertMailboxToShared) {
            if (Get-Command Set-Mailbox -ErrorAction SilentlyContinue) {
                if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, 'Convert mailbox to shared')) {
                    try {
                        Set-Mailbox -Identity $user.UserPrincipalName -Type Shared -ErrorAction Stop
                        $actions.Add('Converted mailbox to shared; confirm storage and retention requirements before removing the licence')
                    }
                    catch {
                        $failures.Add("FAILED to convert the mailbox to shared: $($_.Exception.Message)")
                    }
                }
            }
            else {
                if ($WhatIfPreference) {
                    Write-Verbose 'WhatIf: would convert the mailbox to shared through Exchange Online.'
                }
                else {
                    Write-Warning 'No Exchange Online session loaded (Connect-ExchangeOnline). Mailbox conversion recorded as a manual follow-up.'
                    $actions.Add('MANUAL FOLLOW-UP: convert mailbox to shared via Exchange Online, then reclaim the licence')
                }
            }
        }

        if ($WhatIfPreference) {
            Write-Information 'WhatIf run complete. No tenant changes were made.' -InformationAction Continue
            $plannedActions = @(
                'Disable account'
                'Revoke sign-in sessions'
                'Reset password to a random value'
                @($groups | ForEach-Object { "Remove from group '$($_.AdditionalProperties.displayName)'" })
                if ($ConvertMailboxToShared) { 'Convert mailbox to shared' }
            )
            return [pscustomobject]@{
                WhatIf            = $true
                UserPrincipalName = $user.UserPrincipalName
                DisplayName       = $user.DisplayName
                PlannedActions    = @($plannedActions)
                Actions           = @()
                FailedActions     = @()
                TicketNote        = $null
            }
        }

        $issueText = "Offboard departing user $($user.DisplayName) ($($user.UserPrincipalName))."
        if ($RequestedBy) { $issueText += " Requested by: $RequestedBy." }

        $nextSteps = [System.Collections.Generic.List[string]]::new()
        $nextSteps.Add('Confirm mailbox size, archive and retention requirements before reclaiming the licence')
        $nextSteps.Add('Confirm mail forwarding/delegate access requirements with the client')
        $nextSteps.Add('Confirm the tenant OneDrive retention period and transfer any required files before it ends')
        $nextSteps.Add('Remove the user from any third-party apps outside SSO (client to confirm the list)')
        if ($failures.Count -gt 0) {
            $nextSteps.Add('Review the failed actions above before closing the offboarding ticket')
        }

        $status = if ($failures.Count -gt 0) { 'Escalated' } else { 'In progress' }
        $note = New-SdTicketNote -Summary "User offboarding - $($user.DisplayName)" `
            -Client $Client `
            -Issue $issueText `
            -Steps (@($actions.ToArray()) + @($failures.ToArray())) `
            -NextSteps $nextSteps.ToArray() `
            -Status $status

        [pscustomobject]@{
            UserPrincipalName = $user.UserPrincipalName
            DisplayName       = $user.DisplayName
            Actions           = $actions.ToArray()
            FailedActions     = $failures.ToArray()
            Status            = $status
            TicketNote        = $note
        }
    }
}
