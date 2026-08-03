function Test-SdEssentialEight {
    <#
    .SYNOPSIS
        Checks local workstation signals related to the ACSC Essential Eight.

    .DESCRIPTION
        Checks local indicators for the eight mitigation strategies. This is
        not a formal maturity assessment. Controls that require tenant,
        policy or service evidence are returned as `ManualCheck`.

    .EXAMPLE
        Test-SdEssentialEight | Format-Table Strategy, Status, Finding

    .EXAMPLE
        Test-SdEssentialEight -AsTicketNote
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]], [string])]
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
        & $addCheck 'Application control' 'ManualCheck' 'AppLocker or WDAC configuration was detected' `
            'Confirm enforcement mode, rule coverage and approved exceptions in the policy source.'
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
        if ($upgradeLines.Count -eq 0) {
            & $addCheck 'Patch applications' 'Pass' 'No pending winget upgrades were detected' `
                'Confirm centrally managed applications in the RMM or patching report.'
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
    $macroBlockedApps = [System.Collections.Generic.List[string]]::new()
    foreach ($app in 'word', 'excel', 'powerpoint') {
        $policy = Get-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Office\16.0\$app\security" -ErrorAction SilentlyContinue
        if ($policy -and ($policy.blockcontentexecutionfrominternet -eq 1 -or $policy.vbawarnings -eq 4)) {
            $macroBlockedApps.Add($app)
        }
    }
    if ($macroBlockedApps.Count -eq 3) {
        & $addCheck 'Office macro settings' 'Pass' 'Macro-blocking policy detected for Word, Excel and PowerPoint' `
            'Confirm the settings are centrally managed and review approved exceptions.'
    }
    elseif ($macroBlockedApps.Count -gt 0) {
        & $addCheck 'Office macro settings' 'Attention' ("Policy detected for: {0}" -f ($macroBlockedApps -join ', ')) `
            'Review the missing Office application policies before treating this control as covered.'
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
            'One signal only - browser hardening and PDF handling still need a policy-level look.'
    }
    else {
        & $addCheck 'User application hardening' 'Attention' 'SmartScreen appears disabled' `
            'Re-enable SmartScreen; review browser hardening settings in the client baseline.'
    }

    # --- 5. Restrict administrative privileges -------------------------------------------
    $adminState = Get-SdLocalAdminState
    if ($adminState.IsAdmin) {
        & $addCheck 'Restrict admin privileges' 'Attention' "Current user IS a local administrator (local admins: $($adminState.AdminCount))" `
            'Daily-driver accounts should not be local admins. Recommend a separate admin account or an EPM tool.'
    }
    else {
        & $addCheck 'Restrict admin privileges' 'Pass' "Current user is a standard user (local admins: $($adminState.AdminCount))" `
            'Confirm the remaining local administrator accounts are approved and documented.'
    }

    # --- 6. Patch operating systems --------------------------------------------------------
    $lastHotfix = Get-SdLastHotfix
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
            'Verify the last successful backup and the most recent test restore.'
    }
    else {
        & $addCheck 'Regular backups' 'ManualCheck' 'No known backup agent service found on this machine' `
            'Confirm where workstation data is stored and how it is recovered.'
    }

    if (-not $AsTicketNote) {
        return $checks
    }

    # --- Ticket note ---------------------------------------------------------------------------
    $attention = @($checks | Where-Object Status -eq 'Attention')
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine(('=== ESSENTIAL EIGHT QUICK CHECK - {0} ===' -f $env:COMPUTERNAME))
    [void]$sb.AppendLine(('Captured: {0}' -f (Get-Date -Format $script:SdDateFormat)))
    [void]$sb.AppendLine('Scope: workstation-level signals only - NOT a formal E8 maturity assessment.')
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
        [void]$sb.AppendLine('SUMMARY: No local attention items. Complete the manual checks separately.')
    }
    return $sb.ToString()
}
