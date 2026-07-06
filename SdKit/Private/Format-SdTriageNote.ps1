function Format-SdTriageNote {
    <#
    .SYNOPSIS
        Turns an Invoke-SdTriage snapshot into a paste-ready PSA ticket note.

    .DESCRIPTION
        Kept separate from the collection logic so the formatting can be
        unit-tested on any platform with a fabricated snapshot object —
        no live Windows box required.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Triage
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine(('=== WORKSTATION TRIAGE — {0} ===' -f $Triage.ComputerName))
    [void]$sb.AppendLine(('Captured:      {0}' -f $Triage.Captured))
    if ($Triage.Client)  { [void]$sb.AppendLine(('Client:        {0}' -f $Triage.Client)) }
    if ($Triage.Contact) { [void]$sb.AppendLine(('Contact:       {0}' -f $Triage.Contact)) }
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('SYSTEM')
    [void]$sb.AppendLine(('  Model:         {0}' -f $Triage.Model))
    [void]$sb.AppendLine(('  Serial:        {0}' -f $Triage.SerialNumber))
    [void]$sb.AppendLine(('  OS:            {0}' -f $Triage.OperatingSystem))
    [void]$sb.AppendLine(('  Uptime:        {0}' -f $Triage.Uptime))
    [void]$sb.AppendLine(('  RAM:           {0}' -f $Triage.Memory))
    [void]$sb.AppendLine(('  Pending reboot: {0}' -f $Triage.PendingReboot))
    [void]$sb.AppendLine(('  Last OS patch: {0}' -f $Triage.LastHotfix))
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('DISKS')
    foreach ($disk in @($Triage.Disks)) {
        # Flag anything under 15% free — the usual culprit behind "my
        # computer is running slow" tickets.
        $flag = if ($disk.PercentFree -lt 15) { '  << LOW SPACE' } else { '' }
        [void]$sb.AppendLine(('  {0}  {1} GB free of {2} GB ({3}%){4}' -f `
            $disk.Drive, $disk.FreeGB, $disk.SizeGB, $disk.PercentFree, $flag))
    }
    [void]$sb.AppendLine()

    if ($Triage.RecentErrors) {
        [void]$sb.AppendLine(('RECENT EVENT LOG ERRORS (last {0}h)' -f $Triage.EventWindowHours))
        foreach ($err in @($Triage.RecentErrors)) {
            [void]$sb.AppendLine(('  {0}x  {1} [{2}]' -f $err.Count, $err.Provider, $err.Log))
        }
        [void]$sb.AppendLine()
    }

    if ($Triage.Printers) {
        [void]$sb.AppendLine('PRINTERS')
        foreach ($printer in @($Triage.Printers)) {
            [void]$sb.AppendLine(('  {0} — {1}' -f $printer.Name, $printer.Status))
        }
        [void]$sb.AppendLine()
    }

    if ($Triage.Network) {
        [void]$sb.AppendLine('NETWORK QUICK CHECK')
        foreach ($check in @($Triage.Network)) {
            [void]$sb.AppendLine(('  [{0}] {1} — {2}' -f $check.Result.ToUpper(), $check.Check, $check.Detail))
        }
        [void]$sb.AppendLine()
    }

    [void]$sb.AppendLine('--- End of automated triage. Add troubleshooting notes below. ---')
    return $sb.ToString()
}
