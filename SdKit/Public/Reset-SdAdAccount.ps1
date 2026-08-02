function Reset-SdAdAccount {
    <#
    .SYNOPSIS
        The bread-and-butter AD ticket: unlock and/or reset an on-prem account.

    .DESCRIPTION
        Handles the single most common Level 1 call — "I'm locked out" /
        "I've forgotten my password" — the proper way:

          - Finds the account and reports whether it's actually locked,
            disabled or expired (users say "locked out" for all three)
          - Looks up WHERE it locked out: queries the PDC emulator for the
            most recent 4740 lockout event so you can tell the client which
            device (old phone, mapped drive with stale creds) did it
          - Unlocks the account
          - Optionally resets the password to a readable temp value and
            forces a change at next logon
          - Produces a paste-ready ticket note, and never writes the
            password into it

        Requires the ActiveDirectory module (RSAT) and rights to reset the
        account. Supports -WhatIf so you can confirm the target first.

    .EXAMPLE
        Reset-SdAdAccount -Identity jsmith -Unlock -Client 'Acme Conveyancing'

    .EXAMPLE
        Reset-SdAdAccount -Identity jsmith -Unlock -ResetPassword -Confirm
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        # sAMAccountName, UPN or distinguished name of the account.
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Identity,

        [string]$Client,

        # Clear the lockout. The usual first move on a lockout ticket.
        [switch]$Unlock,

        # Reset the password to a readable temp value (must change at logon).
        [switch]$ResetPassword,

        # Skip the "where did it lock out" lookup (needs Security log access
        # on the PDC emulator, which the desk doesn't always have).
        [switch]$SkipLockoutSource
    )

    process {
        Assert-SdAdModule

        $user = Get-ADUser -Identity $Identity -Properties `
            'LockedOut', 'Enabled', 'AccountExpirationDate', 'PasswordExpired', 'PasswordLastSet', 'DisplayName' `
            -ErrorAction Stop

        $actions   = [System.Collections.Generic.List[string]]::new()
        $findings  = [System.Collections.Generic.List[string]]::new()

        # --- Report the real state (users conflate all three) ---------------
        $findings.Add("Enabled: $($user.Enabled)")
        $findings.Add("Locked out: $($user.LockedOut)")
        if ($user.PasswordExpired)       { $findings.Add('Password is EXPIRED') }
        if ($user.AccountExpirationDate) { $findings.Add("Account expires: $($user.AccountExpirationDate.ToString($script:SdDateFormat))") }
        $findings.Add("Password last set: $(if ($user.PasswordLastSet) { $user.PasswordLastSet.ToString($script:SdDateFormat) } else { 'never' })")

        # A disabled account looks like a lockout to the user but isn't one —
        # flag it rather than silently "unlocking" nothing.
        if (-not $user.Enabled) {
            $findings.Add('NOTE: account is DISABLED — unlocking will not let them sign in. Confirm with the client before enabling.')
        }

        # --- Where did it lock out? -----------------------------------------
        if ($user.LockedOut -and -not $SkipLockoutSource) {
            try {
                $pdc = (Get-ADDomain -ErrorAction Stop).PDCEmulator
                # Event 4740 on the PDC emulator carries the caller computer
                # in the account-lockout audit record.
                $lockoutEvent = Get-WinEvent -ComputerName $pdc -FilterHashtable @{
                    LogName = 'Security'; Id = 4740
                } -MaxEvents 25 -ErrorAction Stop |
                    Where-Object { $_.Properties[0].Value -eq $user.SamAccountName } |
                    Select-Object -First 1
                if ($lockoutEvent) {
                    $source = $lockoutEvent.Properties[1].Value
                    $findings.Add("Lockout source: '$source' at $($lockoutEvent.TimeCreated.ToString($script:SdDateFormat)) - check that device for a stale saved password (Wi-Fi, mapped drive, phone email).")
                }
            }
            catch {
                # Not fatal — the unlock still works, we just can't say why.
                $pdcLabel = if ($pdc) { $pdc } else { 'the PDC emulator' }
                $findings.Add("Lockout source lookup unavailable (needs Security log access on PDC $pdcLabel): $($_.Exception.Message)")
            }
        }

        # --- Unlock ----------------------------------------------------------
        if ($Unlock -and $user.LockedOut) {
            if ($PSCmdlet.ShouldProcess($user.SamAccountName, 'Unlock AD account')) {
                Unlock-ADAccount -Identity $user.SamAccountName -ErrorAction Stop
                $actions.Add('Unlocked the account')
            }
        }
        elseif ($Unlock) {
            $actions.Add('Unlock requested but account was not locked — no change made')
        }

        # --- Password reset --------------------------------------------------
        $tempPassword = $null
        if ($ResetPassword) {
            if ($PSCmdlet.ShouldProcess($user.SamAccountName, 'Reset password and force change at next logon')) {
                $tempPassword = New-SdTempPassword
                $secure = New-Object System.Security.SecureString
                foreach ($character in $tempPassword.ToCharArray()) {
                    $secure.AppendChar($character)
                }
                $secure.MakeReadOnly()
                Set-ADAccountPassword -Identity $user.SamAccountName -NewPassword $secure -Reset -ErrorAction Stop
                Set-ADUser -Identity $user.SamAccountName -ChangePasswordAtLogon $true -ErrorAction Stop
                $actions.Add('Reset password and set must-change-at-next-logon')
            }
        }

        if ($actions.Count -eq 0 -and $WhatIfPreference) {
            Write-Information 'WhatIf run complete. Nothing was changed in AD.' -InformationAction Continue
            return
        }

        $note = New-SdTicketNote -Summary "AD account support — $($user.DisplayName)" `
            -Client $Client `
            -Issue "Account assistance for $($user.SamAccountName) ($($user.DisplayName))." `
            -Steps ($findings + $actions).ToArray() `
            -Resolution $(if ($actions.Count -gt 0) { ($actions -join '; ') } else { 'Investigated only — see steps.' }) `
            -NextSteps $(if ($tempPassword) {
                    @('Hand the temp password to the user out-of-band (phone/password manager) — NOT by email',
                      'Have them clear saved passwords on the device that caused the lockout')
                } else {
                    @('If it locks again, chase the lockout source device for a stale saved credential')
                }) `
            -Status $(if ($actions.Count -gt 0) { 'Resolved' } else { 'In progress' })

        [pscustomobject]@{
            SamAccountName = $user.SamAccountName
            DisplayName    = $user.DisplayName
            WasLockedOut   = $user.LockedOut
            Enabled        = $user.Enabled
            # Present only when a reset ran; hand over out-of-band, never in the note.
            TempPassword   = $tempPassword
            Actions        = $actions.ToArray()
            TicketNote     = $note
        }
    }
}
