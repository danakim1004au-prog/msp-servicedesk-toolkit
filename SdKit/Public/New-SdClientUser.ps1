function New-SdClientUser {
    <#
    .SYNOPSIS
        Onboards a new starter for a managed client — the standard way, every time.

    .DESCRIPTION
        Reads the client's config (UPN pattern, default licence, default
        groups), creates the Entra ID user with an Australian usage location,
        assigns the licence, adds the default groups, and finishes with a
        ready-to-paste ticket note and a temp password to hand over securely.

        Supports -WhatIf so you can sanity-check the UPN and groups before
        touching the tenant — worth doing on a client you haven't onboarded
        for before.

    .EXAMPLE
        Connect-MgGraph -Scopes 'User.ReadWrite.All','Group.ReadWrite.All','Directory.ReadWrite.All','Organization.Read.All'
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
        'User.ReadWrite.All', 'Group.ReadWrite.All', 'Organization.Read.All'
    ) | Out-Null

    # Build the UPN from the client's pattern, e.g. "{first}.{last}".
    # Lower-case and stripped of spaces/apostrophes (O'Brien, van der Berg).
    $localPart = $client.upnPattern.
        Replace('{first}', $FirstName).
        Replace('{last}', $LastName).
        ToLower() -replace "[\s']", ''
    $upn = '{0}@{1}' -f $localPart, $client.domain
    $displayName = '{0} {1}' -f $FirstName, $LastName

    # UPN clash check — duplicate names happen more than you'd think.
    $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
    if ($existing) {
        throw "A user with UPN '$upn' already exists in this tenant. Agree a variation with the client (e.g. middle initial) and re-run with an adjusted -FirstName/-LastName."
    }

    $tempPassword = New-SdTempPassword
    $actions = [System.Collections.Generic.List[string]]::new()

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
        Write-Information "WhatIf: would create user '$displayName' as $upn" -InformationAction Continue
        $newUser = $null
    }

    # --- Assign the licence -------------------------------------------------
    $skuToAssign = if ($LicenceSku) { $LicenceSku } else { $client.defaultLicenceSku }
    if ($skuToAssign -and $newUser) {
        $sku = Get-MgSubscribedSku -All | Where-Object SkuPartNumber -eq $skuToAssign
        if (-not $sku) {
            Write-Warning "Licence SKU '$skuToAssign' not found in this tenant — assign manually and note it in the ticket."
            $actions.Add("LICENCE NOT ASSIGNED: SKU '$skuToAssign' not found in tenant")
        }
        elseif (($sku.PrepaidUnits.Enabled - $sku.ConsumedUnits) -lt 1) {
            # Classic MSP moment: the client is out of licences. Flag it
            # rather than fail the whole onboarding.
            Write-Warning "No spare '$skuToAssign' licences (all $($sku.PrepaidUnits.Enabled) in use). Raise a licence purchase with the client's account manager."
            $actions.Add("LICENCE NOT ASSIGNED: no spare $skuToAssign seats — purchase required")
        }
        elseif ($PSCmdlet.ShouldProcess($upn, "Assign licence $skuToAssign")) {
            Set-MgUserLicense -UserId $newUser.Id `
                -AddLicenses @(@{ SkuId = $sku.SkuId }) -RemoveLicenses @() -ErrorAction Stop | Out-Null
            $actions.Add("Assigned licence $skuToAssign")
        }
    }

    # --- Add default groups --------------------------------------------------
    foreach ($groupName in @($client.defaultGroups)) {
        if (-not $groupName) { continue }
        $group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue
        if (-not $group) {
            Write-Warning "Default group '$groupName' not found in tenant — add manually if it's been renamed."
            $actions.Add("GROUP NOT ADDED: '$groupName' not found")
            continue
        }
        if ($newUser -and $PSCmdlet.ShouldProcess($upn, "Add to group '$groupName'")) {
            try {
                New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $newUser.Id -ErrorAction Stop
                $actions.Add("Added to group '$groupName'")
            }
            catch {
                # Dynamic groups reject manual adds — that's fine, membership
                # will sort itself out from the user's attributes.
                Write-Warning "Could not add to '$groupName': $($_.Exception.Message)"
                $actions.Add("GROUP NOT ADDED: '$groupName' — $($_.Exception.Message)")
            }
        }
    }

    if (-not $newUser) {
        Write-Information 'WhatIf run complete. Nothing was changed in the tenant.' -InformationAction Continue
        return
    }

    $note = New-SdTicketNote -Summary "New starter onboarding — $displayName" `
        -Client $client.name `
        -Issue "Onboard new starter $displayName ($JobTitle) for $($client.name)." `
        -Steps $actions.ToArray() `
        -Resolution "Account created and configured per the $($client.code) onboarding standard." `
        -NextSteps 'Client to have the user enrol MFA at first sign-in (aka.ms/mfasetup)',
                   'Confirm mailbox has provisioned (can take a few minutes after licensing)',
                   'Book follow-up to confirm first-day sign-in went smoothly' `
        -Status 'Waiting on client'

    [pscustomobject]@{
        UserPrincipalName = $upn
        DisplayName       = $displayName
        # Handed over out-of-band (phone or password manager) — never email
        # the password together with the username.
        TempPassword      = $tempPassword
        Actions           = $actions.ToArray()
        TicketNote        = $note
    }
}
