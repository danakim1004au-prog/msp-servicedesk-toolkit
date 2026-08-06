function New-SdTicketNote {
    <#
    .SYNOPSIS
        Formats a service desk ticket note.

    .DESCRIPTION
        Formats issue, impact, troubleshooting, cause, resolution and next-step
        fields as plain text. Optional escalation fields add the receiving
        queue and checks already ruled out.

        Use `-Escalation` to set the status and handover heading.

    .EXAMPLE
        New-SdTicketNote -Summary 'Outlook prompting for password' `
            -Client 'Acme Conveyancing' -Contact 'Sarah M' `
            -Issue 'Outlook repeatedly prompting for credentials since this morning.' `
            -Impact 'Single user; cannot send or receive email.' `
            -Steps 'Confirmed account not locked in Entra ID',
                   'Cleared cached credentials in Credential Manager',
                   'Recreated Outlook profile' `
            -Cause 'Stale credentials cached after last password change.' `
            -Resolution 'Profile recreated, mail flow confirmed with test message both ways.' `
            -Status Resolved -TimeSpentMinutes 25

    .EXAMPLE
        New-SdTicketNote -Summary 'Server 2019 host BSOD twice today' `
            -Escalation -EscalateTo 'L3 - Marcus' `
            -Issue 'ACME-HV01 blue-screened twice; clients losing RDS sessions.' `
            -Steps 'Pulled minidumps', 'Checked storage controller firmware' `
            -RuledOut 'Not Windows Update related - last patch 3 weeks ago and stable since' `
            -NextSteps 'Dump analysis needed; suspect NIC driver'
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This function returns formatted text and does not change system state.')]
    [OutputType([string])]
    param (
        # One-line summary - mirrors the ticket title in the PSA.
        [Parameter(Mandatory)]
        [string]$Summary,

        [string]$Client,
        [string]$Contact,

        # Technician defaults to the logged-on user so notes are attributable.
        [string]$Technician = [System.Environment]::UserName,

        [Parameter(Mandatory)]
        [string]$Issue,

        # Who/what is affected and how badly - drives ticket priority.
        [string]$Impact,

        # Troubleshooting steps in the order you took them, one per entry.
        [string[]]$Steps,

        [string]$Cause,
        [string]$Resolution,
        [string[]]$NextSteps,

        [ValidateSet('Resolved', 'Waiting on client', 'Waiting on vendor', 'Escalated', 'Monitoring', 'In progress')]
        [string]$Status = 'In progress',

        [ValidateRange(0, 480)]
        [int]$TimeSpentMinutes,

        # Escalation handover mode - forces status to Escalated and adds
        # the "ruled out" section that saves the next tech re-doing work.
        [switch]$Escalation,
        [string]$EscalateTo,

        # Things you've already eliminated, so nobody chases them twice.
        [string[]]$RuledOut
    )

    if ($Escalation) { $Status = 'Escalated' }

    $sb = [System.Text.StringBuilder]::new()
    $header = if ($Escalation) { 'ESCALATION HANDOVER' } else { 'TICKET NOTE' }
    [void]$sb.AppendLine(('=== {0} - {1} ===' -f $header, $Summary))
    [void]$sb.AppendLine(('Date:        {0}' -f (Get-Date -Format $script:SdDateFormat)))
    if ($Client)  { [void]$sb.AppendLine(('Client:      {0}' -f $Client)) }
    if ($Contact) { [void]$sb.AppendLine(('Contact:     {0}' -f $Contact)) }
    [void]$sb.AppendLine(('Technician:  {0}' -f $Technician))
    [void]$sb.AppendLine(('Status:      {0}' -f $Status))
    if ($EscalateTo) { [void]$sb.AppendLine(('Escalated to: {0}' -f $EscalateTo)) }
    if ($PSBoundParameters.ContainsKey('TimeSpentMinutes')) {
        [void]$sb.AppendLine(('Time spent:  {0} min' -f $TimeSpentMinutes))
    }
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('ISSUE')
    [void]$sb.AppendLine(('  {0}' -f $Issue))

    if ($Impact) {
        [void]$sb.AppendLine('IMPACT')
        [void]$sb.AppendLine(('  {0}' -f $Impact))
    }

    if ($Steps) {
        [void]$sb.AppendLine('TROUBLESHOOTING STEPS')
        $i = 0
        foreach ($step in $Steps) {
            $i++
            [void]$sb.AppendLine(('  {0}. {1}' -f $i, $step))
        }
    }

    if ($RuledOut) {
        [void]$sb.AppendLine('RULED OUT')
        foreach ($item in $RuledOut) {
            [void]$sb.AppendLine(('  - {0}' -f $item))
        }
    }

    if ($Cause) {
        [void]$sb.AppendLine('CAUSE')
        [void]$sb.AppendLine(('  {0}' -f $Cause))
    }

    if ($Resolution) {
        [void]$sb.AppendLine('RESOLUTION')
        [void]$sb.AppendLine(('  {0}' -f $Resolution))
    }

    if ($NextSteps) {
        [void]$sb.AppendLine('NEXT STEPS')
        foreach ($item in $NextSteps) {
            [void]$sb.AppendLine(('  - {0}' -f $item))
        }
    }

    return $sb.ToString()
}
