function Test-SdEssentialEight {
    <#
    .SYNOPSIS
        Quick workstation sanity check against the ACSC Essential Eight.

    .DESCRIPTION
        A Level 1/2-friendly sweep of the local signals for each of the
        eight strategies. This is deliberately NOT a formal Essential Eight
        maturity assessment — several strategies (MFA, backups, privileged
        access) can only be judged at the tenant/organisation level. Where
        that's the case the check is marked ManualCheck with a pointer to
        what to look at, so the desk knows what to raise rather than
        pretending a registry read settles it.

        Useful on SMB client machines to spot the common gaps: macros wide
        open, no application control, users running as local admins, stale
        patching.

    .EXAMPLE
        Test-SdEssentialEight | Format-Table Strategy, Status, Finding

    .EXAMPLE
        Test-SdEssentialEight -AsTicketNote
    #>
    [CmdletBinding()]
    param (
        # Emit a paste-ready ticket note instead of the check objects.
        [switch]$AsTicketNote
    )

    if (-not $script:SdIsWindows) {
        throw 'Test-SdEssentialEight reads Windows-only signals and must run on the machine being checked.'
    }

    $checks = [System.Collections.Generic.List[pscustomobject]]::new()
    $addCheck = {
        param ($Strategy, $Status, $Finding, $Advice)
        $checks.Add([pscustomobject]@{
            Strategy = $Strategy
            Status   = $Status   # Pass / Attention / ManualCheck
            Finding  = $Finding
            Advice   = $Advice
        })
    }

    # --- 1. Application control -------------------------------------------------
    $appLockerPolicy = $null
    if (Get-Command Get-AppLockerPolicy -ErrorAction SilentlyContinue) {
        try {
            $appLockerPolicy = Get-AppLockerPolicy -Effective -ErrorAction Stop
        }
        catch { $appLockerPolicy = $null }
    }
    $wdacActive = Test-Path -Path "$env:SystemRoot\System32\CodeIntegrity\CiPolicies\Active" -PathType Container
    if (($appLockerPolicy -and $appLockerPolicy.RuleCollections.Count -gt 0) -or $wdacActive) {
        & $addCheck 'Application control' 'Pass' 'AppLocker or WDAC policy is in effect' `
            'Confirm the policy actually blocks (audit-only mode is common).'
    }
    else {
        & $addCheck 'Application control' 'Attention' 'No AppLocker/WDAC policy found' `
            'Users can run any executable they download. Raise application control (even audit mode) with the client.'
    }

    # --- 2. Patch applications ----------------------------------------------------
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        # Count upgradable packages; skip the header/progress noise.
        $upgradeLines = @(winget upgrade --disable-interactivity 2>$null |
            Where-Object { $_ -match '^\S+.*\d+\.\S*\s+\d+\.\S*' })
        if ($upgradeLines.Count -le 3) {
            & $addCheck 'Patch applications' 'Pass' "$($upgradeLines.Count) app(s) with pending updates" `
                'Third-party apps look reasonably current.'
        }
        else {
            & $addCheck 'Patch applications' 'Attention' "$($upgradeLines.Count) app(s) with pending updates" `
                'Run winget upgrade --all or check the RMM patching policy for this client.'
        }
    }
    else {
        & $addCheck 'Patch applications' 'ManualCheck' 'winget not available to enumerate app updates' `
            'Check the RMM/third-party patching report for this machine.'
    }

    # --- 3. Configure Office macro settings ------------------------------------------
    # Policy value 4 = disabled without notification; the ACSC baseline is
    # to block macros from the internet at minimum.
    $macroBlocked = $false
    foreach ($app in 'word', 'excel', 'powerpoint') {
        $policy = Get-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Office\16.0\$app\security" -ErrorAction SilentlyContinue
        if ($policy -and ($policy.blockcontentexecutionfrominternet -eq 1 -or $policy.vbawarnings -eq 4)) {
            $macroBlocked = $true
        }
    }
    if ($macroBlocked) {
        & $addCheck 'Office macro settings' 'Pass' 'Macro-blocking policy detected for Office apps' `
            'Confirm the policy covers all Office apps and comes from Intune/GPO, not a local tweak.'
    }
    else {
        & $addCheck 'Office macro settings' 'Attention' 'No macro-blocking policy found in HKCU Office policies' `
            'Macros from the internet may run with just a click. Recommend the Intune baseline that blocks internet-sourced macros.'
    }

    # --- 4. User application hardening -------------------------------------------------
    $smartScreenPolicy = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -ErrorAction SilentlyContinue
    $smartScreenLocal  = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -ErrorAction SilentlyContinue
    $smartScreenOn = ($smartScreenPolicy -and $smartScreenPolicy.EnableSmartScreen -eq 1) -or
                     ($smartScreenLocal -and $smartScreenLocal.SmartScreenEnabled -in @('RequireAdmin', 'Warn', 'Prompt'))
    if ($smartScreenOn) {
        & $addCheck 'User application hardening' 'Pass' 'SmartScreen is enabled' `
            'One signal only — browser hardening and PDF handling still need a policy-level look.'
    }
    else {
        & $addCheck 'User application hardening' 'Attention' 'SmartScreen appears disabled' `
            'Re-enable SmartScreen; review browser hardening settings in the client baseline.'
    }

    # --- 5. Restrict administrative privileges -------------------------------------------
    $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    $isAdmin   = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    $adminCount = $null
    if (Get-Command Get-LocalGroupMember -ErrorAction SilentlyContinue) {
        # Broken SIDs from departed domain accounts make this throw — hence
        # the soft error handling.
        $adminCount = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue).Count
    }
    if ($isAdmin) {
        & $addCheck 'Restrict admin privileges' 'Attention' "Current user IS a local administrator (local admins: $adminCount)" `
            'Daily-driver accounts should not be local admins. Recommend a separate admin account or an EPM tool.'
    }
    else {
        & $addCheck 'Restrict admin privileges' 'Pass' "Current user is a standard user (local admins: $adminCount)" `
            'Good — confirm the admin accounts that do exist are known and documented.'
    }

    # --- 6. Patch operating systems --------------------------------------------------------
    $lastHotfix = Get-HotFix -ErrorAction SilentlyContinue |
        Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1
    if ($lastHotfix) {
        $patchAge = ((Get-Date) - $lastHotfix.InstalledOn).Days
        if ($patchAge -le 35) {
            & $addCheck 'Patch operating systems' 'Pass' "Last OS patch $($lastHotfix.HotFixID), $patchAge day(s) ago" `
                'Within the monthly patch cadence.'
        }
        else {
            & $addCheck 'Patch operating systems' 'Attention' "Last OS patch $($lastHotfix.HotFixID) was $patchAge day(s) ago" `
                'Over a month behind. Run Windows Update and check why the patching policy missed this machine.'
        }
    }
    else {
        & $addCheck 'Patch operating systems' 'ManualCheck' 'No hotfix history readable' `
            'Check Windows Update history in Settings, or the RMM patch report.'
    }

    # --- 7. Multi-factor authentication ------------------------------------------------------
    & $addCheck 'Multi-factor authentication' 'ManualCheck' 'MFA is enforced at the tenant, not the workstation' `
        'Check Conditional Access policies in Entra ID, and per-user methods with Get-SdUserSnapshot.'

    # --- 8. Regular backups --------------------------------------------------------------------
    # Look for well-known backup agent services as a local hint.
    $backupAgents = @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -match 'Veeam|Datto|Acronis|ShadowProtect|Backup Exec|Azure Backup|MARS'
    })
    if ($backupAgents.Count -gt 0) {
        & $addCheck 'Regular backups' 'ManualCheck' ("Backup agent(s) found: {0}" -f (($backupAgents.DisplayName | Select-Object -First 3) -join ', ')) `
            'An agent being present is not a backup — verify the last successful job and the most recent test restore.'
    }
    else {
        & $addCheck 'Regular backups' 'ManualCheck' 'No known backup agent service found on this machine' `
            'Fine for a workstation if data lives in OneDrive/SharePoint — confirm that is actually the case for this client.'
    }

    if (-not $AsTicketNote) {
        return $checks
    }

    # --- Ticket note ---------------------------------------------------------------------------
    $attention = @($checks | Where-Object Status -eq 'Attention')
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine(('=== ESSENTIAL EIGHT QUICK CHECK — {0} ===' -f $env:COMPUTERNAME))
    [void]$sb.AppendLine(('Captured: {0}' -f (Get-Date -Format $script:SdDateFormat)))
    [void]$sb.AppendLine('Scope: workstation-level signals only — NOT a formal E8 maturity assessment.')
    [void]$sb.AppendLine()
    foreach ($check in $checks) {
        [void]$sb.AppendLine(('  [{0}] {1}' -f $check.Status.ToUpper(), $check.Strategy))
        [void]$sb.AppendLine(('      {0}' -f $check.Finding))
        [void]$sb.AppendLine(('      -> {0}' -f $check.Advice))
    }
    [void]$sb.AppendLine()
    if ($attention.Count -gt 0) {
        [void]$sb.AppendLine(('SUMMARY: {0} item(s) need attention: {1}' -f $attention.Count, (($attention.Strategy) -join '; ')))
    }
    else {
        [void]$sb.AppendLine('SUMMARY: No local red flags — complete the manual checks to finish the picture.')
    }
    return $sb.ToString()
}
