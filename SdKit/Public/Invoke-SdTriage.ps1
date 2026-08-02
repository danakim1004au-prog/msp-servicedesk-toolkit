function Invoke-SdTriage {
    <#
    .SYNOPSIS
        One-command workstation triage for "my computer is slow/broken" tickets.

    .DESCRIPTION
        Gathers the facts a Level 1/2 tech needs before touching anything:
        hardware model and serial, OS build, uptime, RAM, disk space (with
        low-space flags), pending reboot state, last OS patch, recent event
        log errors, printer status and an optional network quick check.

        Pipe-friendly object output for scripting, or -AsTicketNote for a
        block you can paste straight into the PSA while the client is still
        on the phone.

    .EXAMPLE
        Invoke-SdTriage -Client 'Acme Conveyancing' -Contact 'Sarah M' -AsTicketNote | Set-Clipboard

    .EXAMPLE
        Invoke-SdTriage -IncludeNetwork | Select-Object Uptime, PendingReboot, Disks
    #>
    [CmdletBinding()]
    param (
        [string]$Client,
        [string]$Contact,

        # How far back to sweep the System/Application logs for errors.
        [ValidateRange(1, 168)]
        [int]$EventHours = 24,

        # Run the layered network check as part of the triage.
        [switch]$IncludeNetwork,

        # Emit a paste-ready ticket note instead of the snapshot object.
        [switch]$AsTicketNote
    )

    if (-not $script:SdIsWindows) {
        throw 'Invoke-SdTriage collects Windows workstation data and must run on the affected Windows machine (locally or via a remote session).'
    }

    Write-Verbose 'Collecting system information...'
    $os   = Get-CimInstance -ClassName Win32_OperatingSystem
    $cs   = Get-CimInstance -ClassName Win32_ComputerSystem
    $bios = Get-CimInstance -ClassName Win32_BIOS

    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeText = '{0}d {1}h {2}m' -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    if ($uptime.TotalDays -ge 14) {
        # Fast Startup hides this from users — "I turn it off every night"
        # and a 40-day uptime can both be true.
        $uptimeText += '  << consider a restart'
    }

    Write-Verbose 'Checking disks...'
    $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
        $sizeGB = [math]::Round($_.Size / 1GB, 1)
        $freeGB = [math]::Round($_.FreeSpace / 1GB, 1)
        [pscustomobject]@{
            Drive       = $_.DeviceID
            SizeGB      = $sizeGB
            FreeGB      = $freeGB
            PercentFree = if ($sizeGB -gt 0) { [math]::Round(($freeGB / $sizeGB) * 100) } else { 0 }
        }
    })

    # Pending reboot: the registry keys that Windows servicing and domain
    # operations leave behind when a restart is owed.
    Write-Verbose 'Checking pending reboot state...'
    $rebootKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    $pendingReboot = $false
    foreach ($key in $rebootKeys) {
        if (Test-Path -Path $key) { $pendingReboot = $true; break }
    }
    if (-not $pendingReboot) {
        # A pending computer rename also counts.
        $pendingRename = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction SilentlyContinue
        $currentName   = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction SilentlyContinue
        if ($pendingRename -and $currentName -and $pendingRename.ComputerName -ne $currentName.ComputerName) {
            $pendingReboot = $true
        }
    }

    Write-Verbose 'Checking last OS patch...'
    $lastHotfix = Get-HotFix -ErrorAction SilentlyContinue |
        Where-Object InstalledOn |
        Sort-Object InstalledOn -Descending |
        Select-Object -First 1
    $lastHotfixText = if ($lastHotfix) {
        '{0} on {1:dd/MM/yyyy}' -f $lastHotfix.HotFixID, $lastHotfix.InstalledOn
    }
    else { 'No hotfix history found' }

    # Recent errors grouped by provider — the shape of the problem matters
    # more than fifty identical lines.
    Write-Verbose "Sweeping event logs for the last $EventHours hours..."
    $since = (Get-Date).AddHours(-$EventHours)
    $recentErrors = foreach ($log in 'System', 'Application') {
        $events = Get-WinEvent -FilterHashtable @{ LogName = $log; Level = 1, 2; StartTime = $since } -ErrorAction SilentlyContinue
        $events | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object {
            [pscustomobject]@{
                Log      = $log
                Provider = $_.Name
                Count    = $_.Count
            }
        }
    }

    Write-Verbose 'Checking printers...'
    $printers = @()
    if (Get-Command Get-Printer -ErrorAction SilentlyContinue) {
        $printers = @(Get-Printer -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                Name   = $_.Name
                Status = $_.PrinterStatus
            }
        })
    }

    $network = $null
    if ($IncludeNetwork) {
        Write-Verbose 'Running network quick check...'
        $network = Test-SdNetworkStack
    }

    $snapshot = [pscustomobject]@{
        ComputerName     = $env:COMPUTERNAME
        Captured         = Get-Date -Format $script:SdDateFormat
        Client           = $Client
        Contact          = $Contact
        Model            = ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim()
        SerialNumber     = $bios.SerialNumber
        OperatingSystem  = ('{0} (build {1})' -f $os.Caption, $os.BuildNumber)
        Uptime           = $uptimeText
        Memory           = ('{0} GB' -f [math]::Round($cs.TotalPhysicalMemory / 1GB, 1))
        PendingReboot    = $pendingReboot
        LastHotfix       = $lastHotfixText
        Disks            = $disks
        EventWindowHours = $EventHours
        RecentErrors     = @($recentErrors)
        Printers         = $printers
        Network          = $network
    }

    if ($AsTicketNote) {
        return Format-SdTriageNote -Triage $snapshot
    }
    return $snapshot
}
