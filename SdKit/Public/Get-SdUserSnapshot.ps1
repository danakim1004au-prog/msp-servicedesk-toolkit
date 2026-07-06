function Get-SdUserSnapshot {
    <#
    .SYNOPSIS
        Everything you need for a "user can't sign in" ticket, in one call.

    .DESCRIPTION
        Pulls the classic first-call facts from Microsoft Graph:

          - Account enabled/disabled and last password change
          - Assigned licences
          - Registered MFA methods (the usual culprit after a new phone)
          - Group memberships
          - Intune-managed devices and their compliance state
          - Recent sign-in failures with the error codes, where the
            session has audit log access

        Requires an existing Connect-MgGraph session against the client's
        tenant. Read-only — safe to run while the client is on the phone.

    .EXAMPLE
        Connect-MgGraph -Scopes 'User.Read.All','UserAuthenticationMethod.Read.All','Directory.Read.All','DeviceManagementManagedDevices.Read.All'
        Get-SdUserSnapshot -UserPrincipalName sarah.m@acmeconvey.com.au -AsTicketNote
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$UserPrincipalName,

        # Emit a paste-ready ticket note instead of the snapshot object.
        [switch]$AsTicketNote
    )

    process {
        Assert-SdGraphConnection -RequiredScopes @(
            'User.Read.All', 'UserAuthenticationMethod.Read.All', 'Directory.Read.All'
        ) | Out-Null

        Write-Verbose "Fetching account state for $UserPrincipalName..."
        $user = Get-MgUser -UserId $UserPrincipalName -Property `
            'id,displayName,userPrincipalName,accountEnabled,jobTitle,department,lastPasswordChangeDateTime,onPremisesSyncEnabled' `
            -ErrorAction Stop

        Write-Verbose 'Fetching licences...'
        $licences = @(Get-MgUserLicenseDetail -UserId $user.Id -ErrorAction SilentlyContinue |
            ForEach-Object { $_.SkuPartNumber })

        # Map Graph's auth method OData types to names a tech recognises.
        Write-Verbose 'Fetching MFA methods...'
        $methodNames = @{
            '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' = 'Microsoft Authenticator'
            '#microsoft.graph.phoneAuthenticationMethod'                  = 'Phone (SMS/call)'
            '#microsoft.graph.fido2AuthenticationMethod'                  = 'FIDO2 security key'
            '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod' = 'Windows Hello for Business'
            '#microsoft.graph.softwareOathAuthenticationMethod'           = 'Software OTP token'
            '#microsoft.graph.emailAuthenticationMethod'                  = 'Email (SSPR only)'
            '#microsoft.graph.passwordAuthenticationMethod'               = 'Password'
            '#microsoft.graph.temporaryAccessPassAuthenticationMethod'    = 'Temporary Access Pass'
        }
        $mfaMethods = @(Get-MgUserAuthenticationMethod -UserId $user.Id -ErrorAction SilentlyContinue |
            ForEach-Object {
                $type = $_.AdditionalProperties.'@odata.type'
                if ($methodNames.ContainsKey($type)) { $methodNames[$type] } else { $type }
            } | Where-Object { $_ -ne 'Password' })

        Write-Verbose 'Fetching group memberships...'
        $groups = @(Get-MgUserMemberOf -UserId $user.Id -All -ErrorAction SilentlyContinue |
            ForEach-Object { $_.AdditionalProperties.displayName } |
            Where-Object { $_ } | Sort-Object)

        # Intune devices — scope may not be granted, so degrade gracefully.
        Write-Verbose 'Fetching Intune devices...'
        $devices = @()
        try {
            $devices = @(Get-MgUserManagedDevice -UserId $user.Id -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{
                    Name       = $_.DeviceName
                    OS         = ('{0} {1}' -f $_.OperatingSystem, $_.OsVersion)
                    Compliance = $_.ComplianceState
                    LastSync   = if ($_.LastSyncDateTime) { $_.LastSyncDateTime.ToLocalTime().ToString($script:SdDateFormat) } else { 'unknown' }
                }
            })
        }
        catch {
            Write-Verbose "Intune device lookup unavailable in this session: $($_.Exception.Message)"
        }

        # Recent failed sign-ins tell you *why* (error code) — worth having
        # even though the scope isn't always granted to the desk.
        Write-Verbose 'Fetching recent sign-in failures...'
        $signInFailures = @()
        if (Get-Command Get-MgAuditLogSignIn -ErrorAction SilentlyContinue) {
            try {
                $filter = "userPrincipalName eq '$($user.UserPrincipalName)' and status/errorCode ne 0"
                $signInFailures = @(Get-MgAuditLogSignIn -Filter $filter -Top 5 -ErrorAction Stop | ForEach-Object {
                    [pscustomobject]@{
                        When    = $_.CreatedDateTime.ToLocalTime().ToString($script:SdDateFormat)
                        App     = $_.AppDisplayName
                        Error   = $_.Status.ErrorCode
                        Reason  = $_.Status.FailureReason
                    }
                })
            }
            catch {
                Write-Verbose "Sign-in log unavailable (needs AuditLog.Read.All): $($_.Exception.Message)"
            }
        }

        $snapshot = [pscustomobject]@{
            DisplayName        = $user.DisplayName
            UserPrincipalName  = $user.UserPrincipalName
            AccountEnabled     = $user.AccountEnabled
            JobTitle           = $user.JobTitle
            Department         = $user.Department
            SyncedFromAD       = [bool]$user.OnPremisesSyncEnabled
            LastPasswordChange = if ($user.LastPasswordChangeDateTime) { $user.LastPasswordChangeDateTime.ToLocalTime().ToString($script:SdDateFormat) } else { 'unknown' }
            Licences           = $licences
            MfaMethods         = $mfaMethods
            Groups             = $groups
            Devices            = $devices
            SignInFailures     = $signInFailures
        }

        if (-not $AsTicketNote) { return $snapshot }

        # --- Ticket note ----------------------------------------------------
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine(('=== M365 USER SNAPSHOT — {0} ===' -f $snapshot.UserPrincipalName))
        [void]$sb.AppendLine(('Captured:       {0}' -f (Get-Date -Format $script:SdDateFormat)))
        [void]$sb.AppendLine(('Name:           {0} ({1}, {2})' -f $snapshot.DisplayName, $snapshot.JobTitle, $snapshot.Department))
        [void]$sb.AppendLine(('Account:        {0}' -f $(if ($snapshot.AccountEnabled) { 'Enabled' } else { 'DISABLED' })))
        [void]$sb.AppendLine(('Identity source: {0}' -f $(if ($snapshot.SyncedFromAD) { 'Synced from on-prem AD (fix password/attributes in AD!)' } else { 'Cloud-only (Entra ID)' })))
        [void]$sb.AppendLine(('Password set:   {0}' -f $snapshot.LastPasswordChange))
        [void]$sb.AppendLine(('Licences:       {0}' -f $(if ($licences) { $licences -join ', ' } else { 'NONE — no licence, no mailbox' })))
        [void]$sb.AppendLine(('MFA methods:    {0}' -f $(if ($mfaMethods) { $mfaMethods -join ', ' } else { 'NONE registered — expect sign-in trouble' })))
        if ($devices.Count -gt 0) {
            [void]$sb.AppendLine('Intune devices:')
            foreach ($device in $devices) {
                [void]$sb.AppendLine(('  {0} — {1}, {2}, last sync {3}' -f $device.Name, $device.OS, $device.Compliance, $device.LastSync))
            }
        }
        if ($signInFailures.Count -gt 0) {
            [void]$sb.AppendLine('Recent sign-in failures:')
            foreach ($failure in $signInFailures) {
                [void]$sb.AppendLine(('  {0}  {1} — error {2}: {3}' -f $failure.When, $failure.App, $failure.Error, $failure.Reason))
            }
        }
        return $sb.ToString()
    }
}
