function New-SdClientUser {
    <#
    .SYNOPSIS
        Creates and configures a Microsoft Entra ID user.

    .DESCRIPTION
        Reads the UPN pattern, default licence and default groups from the
        client configuration. Returns a ticket note, an action summary and a
        temporary password when the user is created. Use -WhatIf to review the
        planned UPN, licence and group assignments.

    .EXAMPLE
        Connect-MgGraph -Scopes 'User.ReadWrite.All','GroupMember.ReadWrite.All','Organization.Read.All'
        New-SdClientUser -ClientCode ACME -FirstName Sarah -LastName McMillan `
            -JobTitle 'Conveyancer' -ConfigPath ./config/clients.json -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory)]
        [string]$ClientCode,

        [Parameter(Mandatory)]
        [string]$FirstName,

        [Parameter(Mandatory)]
        [string]$LastName,

        [string]$JobTitle,
        [string]$Department,
        [string]$MobilePhone,

        [Parameter(Mandatory)]
        [string]$ConfigPath,

        # Override the client's default licence SKU for this user only.
        [string]$LicenceSku
    )

    $client = Get-SdClientConfig -Path $ConfigPath -ClientCode $ClientCode
    Assert-SdGraphConnection -RequiredScopes @(
        'User.ReadWrite.All', 'GroupMember.ReadWrite.All', 'Organization.Read.All'
    ) | Out-Null

    # Build the UPN from the configured pattern and remove characters that are
    # not accepted by this module's local-part convention.
    $localPart = $client.upnPattern.
        Replace('{first}', $FirstName).
        Replace('{last}', $LastName).
        ToLower() -replace "[^a-z0-9._-]", ''
    if ([string]::IsNullOrWhiteSpace($localPart)) {
        throw 'The configured UPN pattern and supplied name produced an empty local part.'
    }
    $upn = '{0}@{1}' -f $localPart, $client.domain
    $displayName = '{0} {1}' -f $FirstName, $LastName
    $skuToAssign = if ($LicenceSku) { $LicenceSku } else { $client.defaultLicenceSku }

    $escapedUpn = $upn.Replace("'", "''")
    $existing = Get-MgUser -Filter "userPrincipalName eq '$escapedUpn'" -ErrorAction SilentlyContinue
    if ($existing) {
        throw "A user with UPN '$upn' already exists in this tenant. Agree a variation with the client (e.g. middle initial) and re-run with an adjusted -FirstName/-LastName."
    }

    if ($WhatIfPreference) {
        $plannedActions = [System.Collections.Generic.List[string]]::new()
        $plannedActions.Add("Create Entra ID user $upn")
        if ($skuToAssign) { $plannedActions.Add("Assign licence $skuToAssign") }
        foreach ($groupName in @($client.defaultGroups)) {
            if ($groupName) { $plannedActions.Add("Add to group '$groupName'") }
        }

        Write-Information 'WhatIf run complete. No tenant changes were made.' -InformationAction Continue
        return [pscustomobject]@{
            WhatIf            = $true
            UserPrincipalName = $upn
            DisplayName       = $displayName
            LicenceSku        = $skuToAssign
            DefaultGroups     = @($client.defaultGroups)
            PlannedActions    = $plannedActions.ToArray()
            Actions           = @()
            FailedActions     = @()
            TempPassword      = $null
            TicketNote        = $null
        }
    }

    $tempPassword = New-SdTempPassword
    $actions = [System.Collections.Generic.List[string]]::new()
    $failures = [System.Collections.Generic.List[string]]::new()

    # --- Create the user --------------------------------------------------
    if ($PSCmdlet.ShouldProcess($upn, 'Create Entra ID user')) {
        $body = @{
            AccountEnabled    = $true
            DisplayName       = $displayName
            GivenName         = $FirstName
            Surname           = $LastName
            UserPrincipalName = $upn
            MailNickname      = $localPart
            UsageLocation     = 'AU'   # required before an AU licence can be assigned
            PasswordProfile   = @{
                Password                      = $tempPassword
                ForceChangePasswordNextSignIn = $true
            }
        }
        if ($JobTitle)    { $body.JobTitle    = $JobTitle }
        if ($Department)  { $body.Department  = $Department }
        if ($MobilePhone) { $body.MobilePhone = $MobilePhone }

        $newUser = New-MgUser -BodyParameter $body -ErrorAction Stop
        $actions.Add("Created Entra ID user $upn (must change password at first sign-in)")
    }
    else {
        Write-Information "User creation was cancelled for $upn." -InformationAction Continue
        return
    }

    # --- Assign the licence -------------------------------------------------
    if ($skuToAssign -and $newUser) {
        try {
            $matchingSkus = @(Get-MgSubscribedSku -All -ErrorAction Stop | Where-Object SkuPartNumber -eq $skuToAssign)
            if ($matchingSkus.Count -eq 0) {
                throw "SKU '$skuToAssign' was not found in the tenant"
            }
            if ($matchingSkus.Count -gt 1) {
                throw "More than one SKU matched '$skuToAssign'"
            }

            $sku = $matchingSkus[0]
            if (($sku.PrepaidUnits.Enabled - $sku.ConsumedUnits) -lt 1) {
                throw "No $skuToAssign seats are available"
            }

            if ($PSCmdlet.ShouldProcess($upn, "Assign licence $skuToAssign")) {
                Set-MgUserLicense -UserId $newUser.Id `
                    -AddLicenses @(@{ SkuId = $sku.SkuId }) -RemoveLicenses @() -ErrorAction Stop | Out-Null
                $actions.Add("Assigned licence $skuToAssign")
            }
        }
        catch {
            $message = "LICENCE NOT ASSIGNED: $($_.Exception.Message)"
            Write-Warning $message
            $failures.Add($message)
        }
    }

    # --- Add default groups --------------------------------------------------
    foreach ($groupName in @($client.defaultGroups)) {
        if (-not $groupName) { continue }
        try {
            $escapedGroupName = $groupName.Replace("'", "''")
            $matchingGroups = @(Get-MgGroup -Filter "displayName eq '$escapedGroupName'" -ErrorAction Stop)
            if ($matchingGroups.Count -eq 0) {
                throw "Group '$groupName' was not found"
            }
            if ($matchingGroups.Count -gt 1) {
                throw "Group name '$groupName' is not unique"
            }

            $group = $matchingGroups[0]
            if ($newUser -and $PSCmdlet.ShouldProcess($upn, "Add to group '$groupName'")) {
                New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $newUser.Id -ErrorAction Stop
                $actions.Add("Added to group '$groupName'")
            }
        }
        catch {
            $message = "GROUP NOT ADDED: '$groupName' - $($_.Exception.Message)"
            Write-Warning $message
            $failures.Add($message)
        }
    }

    $status = if ($failures.Count -gt 0) { 'In progress' } else { 'Waiting on client' }
    $resolution = if ($failures.Count -gt 0) {
        'Account created. Licence or group follow-up remains; see troubleshooting steps.'
    }
    else {
        "Account created and configured from the $($client.code) client settings."
    }

    $note = New-SdTicketNote -Summary "New starter onboarding - $displayName" `
        -Client $client.name `
        -Issue "Onboard new starter $displayName ($JobTitle) for $($client.name)." `
        -Steps (@($actions.ToArray()) + @($failures.ToArray())) `
        -Resolution $resolution `
        -NextSteps 'Client to have the user enrol MFA at first sign-in (aka.ms/mfasetup)',
                   'Confirm mailbox has provisioned (can take a few minutes after licensing)',
                   'Book follow-up to confirm first-day sign-in went smoothly' `
        -Status $status

    [pscustomobject]@{
        UserPrincipalName = $upn
        DisplayName       = $displayName
        TempPassword      = $tempPassword
        Actions           = $actions.ToArray()
        FailedActions     = $failures.ToArray()
        Status            = $status
        TicketNote        = $note
    }
}
