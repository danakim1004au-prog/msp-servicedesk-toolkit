function Invoke-SdPcRunUp {
    <#
    .SYNOPSIS
        Workshop PC run-up: applies the SOE baseline and produces a QA report.

    .DESCRIPTION
        The bench work, standardised. Reads the SOE baseline (JSON) and the
        client config, then works through the run-up checklist:

          - Rename the machine to the client's naming convention
          - Set the time zone (defaults to Adelaide)
          - Apply the power plan
          - Install the standard app set via winget
          - Remove consumer bloatware (Appx packages on the baseline list)
          - Sensible Windows defaults (show file extensions)
          - Hardware/security QA: TPM present, BitLocker state, disk space

        Every step is recorded as Done / Failed / Manual / Skipped, and the
        run finishes with a report saved next to the ticket so QA can be
        eyeballed before the machine ships. Supports -WhatIf for a dry run.

    .EXAMPLE
        Invoke-SdPcRunUp -BaselinePath ./config/runup-baseline.json -ConfigPath ./config/clients.json `
            -ClientCode ACME -DeviceType LT -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory)]
        [string]$BaselinePath,

        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [string]$ClientCode,

        # LT = laptop, DT = desktop — feeds the naming convention.
        [Parameter(Mandatory)]
        [ValidateSet('LT', 'DT', 'WS')]
        [string]$DeviceType,

        # Where to drop the run-up report. Defaults to the current folder.
        [string]$ReportPath = '.',

        # Skip the winget app installs (e.g. machine is imaged with apps).
        [switch]$SkipApps
    )

    if (-not $script:SdIsWindows) {
        throw 'Invoke-SdPcRunUp configures a Windows machine and must run on the box being run up.'
    }

    if (-not (Test-Path $BaselinePath)) {
        throw "SOE baseline not found at '$BaselinePath'. Copy config/runup-baseline.sample.json and adjust."
    }
    $baseline = Get-Content -Path $BaselinePath -Raw | ConvertFrom-Json
    $client   = Get-SdClientConfig -Path $ConfigPath -ClientCode $ClientCode

    $steps = [System.Collections.Generic.List[pscustomobject]]::new()
    $addStep = {
        param ($Name, $Status, $Detail)
        $steps.Add([pscustomobject]@{ Step = $Name; Status = $Status; Detail = $Detail })
        $colour = switch ($Status) {
            'Done'   { 'Green' }
            'Failed' { 'Red' }
            'Manual' { 'Yellow' }
            default  { 'Gray' }
        }
        Write-Host ('  [{0}] {1} — {2}' -f $Status.ToUpper(), $Name, $Detail) -ForegroundColor $colour
    }

    Write-Host "Starting run-up for $($client.name) ($DeviceType) against SOE $($baseline.soeVersion)..." -ForegroundColor Cyan

    # --- Computer name -------------------------------------------------------
    $serial = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
    $newName = New-SdComputerName -Pattern $client.computerNamePattern -ClientCode $client.code -DeviceType $DeviceType -Serial $serial
    if ($env:COMPUTERNAME -eq $newName) {
        & $addStep 'Computer name' 'Skipped' "Already named $newName"
    }
    elseif ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Rename to $newName")) {
        try {
            Rename-Computer -NewName $newName -Force -ErrorAction Stop
            & $addStep 'Computer name' 'Done' "Renamed to $newName (takes effect after restart)"
        }
        catch {
            & $addStep 'Computer name' 'Failed' $_.Exception.Message
        }
    }

    # --- Time zone --------------------------------------------------------------
    $tz = if ($client.timezone) { $client.timezone } else { $baseline.timezone }
    if ($tz -and $PSCmdlet.ShouldProcess('System', "Set time zone to $tz")) {
        try {
            Set-TimeZone -Id $tz -ErrorAction Stop
            & $addStep 'Time zone' 'Done' $tz
        }
        catch {
            & $addStep 'Time zone' 'Failed' $_.Exception.Message
        }
    }

    # --- Power plan ---------------------------------------------------------------
    # Friendly name to GUID map for the built-in plans.
    $planGuids = @{
        'Balanced'         = '381b4222-f694-41f0-9685-ff5bb260df2e'
        'High performance' = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        'Power saver'      = 'a1841308-3541-4fab-bc81-f71556f20b4a'
    }
    $planName = if ($baseline.powerPlan) { $baseline.powerPlan } else { 'Balanced' }
    if ($planGuids.ContainsKey($planName)) {
        if ($PSCmdlet.ShouldProcess('System', "Set power plan to $planName")) {
            powercfg /setactive $planGuids[$planName] 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                & $addStep 'Power plan' 'Done' $planName
            }
            else {
                & $addStep 'Power plan' 'Failed' "powercfg exited with code $LASTEXITCODE"
            }
        }
    }
    else {
        & $addStep 'Power plan' 'Manual' "Unknown plan '$planName' in baseline — set manually"
    }

    # --- Standard apps via winget ------------------------------------------------
    if ($SkipApps) {
        & $addStep 'Standard apps' 'Skipped' 'Skipped by -SkipApps'
    }
    elseif (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        & $addStep 'Standard apps' 'Manual' 'winget not available — install the App Installer from the Microsoft Store first'
    }
    else {
        foreach ($appId in @($baseline.wingetApps)) {
            if ($PSCmdlet.ShouldProcess($appId, 'Install via winget')) {
                winget install --id $appId --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    & $addStep "App: $appId" 'Done' 'Installed'
                }
                elseif ($LASTEXITCODE -eq -1978335189) {
                    # winget's "no applicable upgrade" — already installed.
                    & $addStep "App: $appId" 'Skipped' 'Already installed'
                }
                else {
                    & $addStep "App: $appId" 'Failed' "winget exit code $LASTEXITCODE — install manually"
                }
            }
        }
    }

    # --- Debloat -------------------------------------------------------------------
    foreach ($appx in @($baseline.removeAppx)) {
        $package = Get-AppxPackage -Name $appx -ErrorAction SilentlyContinue
        if (-not $package) {
            & $addStep "Debloat: $appx" 'Skipped' 'Not present'
            continue
        }
        if ($PSCmdlet.ShouldProcess($appx, 'Remove Appx package')) {
            try {
                $package | Remove-AppxPackage -ErrorAction Stop
                & $addStep "Debloat: $appx" 'Done' 'Removed'
            }
            catch {
                & $addStep "Debloat: $appx" 'Failed' $_.Exception.Message
            }
        }
    }

    # --- Sensible defaults ------------------------------------------------------------
    if ($baseline.windowsSettings.showFileExtensions -and
        $PSCmdlet.ShouldProcess('Explorer', 'Show file extensions')) {
        try {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
                -Name 'HideFileExt' -Value 0 -ErrorAction Stop
            & $addStep 'Show file extensions' 'Done' 'Hidden extensions are how users double-click invoice.pdf.exe'
        }
        catch {
            & $addStep 'Show file extensions' 'Failed' $_.Exception.Message
        }
    }

    # --- QA checks (read-only) ----------------------------------------------------------
    try {
        $tpm = Get-Tpm -ErrorAction Stop
        if ($tpm.TpmPresent -and $tpm.TpmReady) {
            & $addStep 'QA: TPM' 'Done' 'TPM present and ready'
        }
        else {
            & $addStep 'QA: TPM' 'Manual' 'TPM missing or not ready — check firmware settings before enabling BitLocker'
        }
    }
    catch {
        & $addStep 'QA: TPM' 'Manual' "Could not query TPM: $($_.Exception.Message)"
    }

    if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        $systemDrive = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
        if ($systemDrive -and $systemDrive.ProtectionStatus -eq 'On') {
            & $addStep 'QA: BitLocker' 'Done' "Protection on ($($systemDrive.EncryptionPercentage)% encrypted) — confirm the recovery key is escrowed"
        }
        else {
            & $addStep 'QA: BitLocker' 'Manual' 'Not enabled — enable via Intune policy or manually, and escrow the recovery key'
        }
    }

    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    $freeGb = [math]::Round($disk.FreeSpace / 1GB, 1)
    $minFree = if ($baseline.checks.minDiskFreeGb) { $baseline.checks.minDiskFreeGb } else { 40 }
    if ($freeGb -ge $minFree) {
        & $addStep 'QA: Disk space' 'Done' "$freeGb GB free on $env:SystemDrive"
    }
    else {
        & $addStep 'QA: Disk space' 'Manual' "$freeGb GB free is under the $minFree GB baseline — check the drive spec"
    }

    # Windows Update is deliberately last and deliberately manual-or-module:
    # PSWindowsUpdate isn't on a fresh image by default.
    if (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue) {
        & $addStep 'Windows updates' 'Manual' 'PSWindowsUpdate available — run Install-WindowsUpdate -AcceptAll -AutoReboot to finish'
    }
    else {
        & $addStep 'Windows updates' 'Manual' 'Run Windows Update until no updates remain (usually 2-3 passes on a fresh image)'
    }

    # --- Report ------------------------------------------------------------------------
    $reportFile = Join-Path $ReportPath ('runup-{0}-{1}.md' -f $newName, (Get-Date -Format 'yyyyMMdd-HHmm'))
    $manualCount = @($steps | Where-Object Status -eq 'Manual').Count
    $failedCount = @($steps | Where-Object Status -eq 'Failed').Count

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# PC Run-Up Report — $newName")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("| | |")
    [void]$sb.AppendLine("|---|---|")
    [void]$sb.AppendLine("| Client | $($client.name) |")
    [void]$sb.AppendLine("| SOE version | $($baseline.soeVersion) |")
    [void]$sb.AppendLine("| Device type | $DeviceType |")
    [void]$sb.AppendLine("| Serial | $serial |")
    [void]$sb.AppendLine("| Technician | $([System.Environment]::UserName) |")
    [void]$sb.AppendLine("| Date | $(Get-Date -Format $script:SdDateFormat) |")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Steps')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Step | Status | Detail |')
    [void]$sb.AppendLine('|---|---|---|')
    foreach ($step in $steps) {
        [void]$sb.AppendLine(('| {0} | {1} | {2} |' -f $step.Step, $step.Status, $step.Detail))
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**Outstanding before shipping:** $manualCount manual step(s), $failedCount failed step(s).")

    if ($PSCmdlet.ShouldProcess($reportFile, 'Write run-up report')) {
        Set-Content -Path $reportFile -Value $sb.ToString() -Encoding UTF8
        Write-Host "`nRun-up report saved to $reportFile" -ForegroundColor Cyan
    }

    [pscustomobject]@{
        ComputerName = $newName
        Client       = $client.name
        SoeVersion   = $baseline.soeVersion
        Steps        = $steps
        ManualSteps  = $manualCount
        FailedSteps  = $failedCount
        ReportFile   = $reportFile
    }
}
