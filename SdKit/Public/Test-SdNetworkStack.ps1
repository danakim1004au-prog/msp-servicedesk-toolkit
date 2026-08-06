function Test-SdNetworkStack {
    <#
    .SYNOPSIS
        Tests local and external network connectivity by layer.

    .DESCRIPTION
        Runs the following checks in order:

          1. Is a network adapter actually up?
          2. Did we get a real IP, or an APIPA (169.254.x.x) address?
          3. Can we reach the default gateway?
          4. Does DNS resolve (internal name if given, plus external)?
          5. Can we get out on HTTPS?
          6. Can we reach the Microsoft 365 front doors?
          7. Is a VPN connected that might be steering traffic?

        Each result includes a short `PlainEnglish` explanation for ticket
        notes and client updates.

    .EXAMPLE
        Test-SdNetworkStack -InternalHost acme-dc01.acme.local | Format-Table Check, Result, Detail

    .EXAMPLE
        Test-SdNetworkStack -AsTicketNote
    #>
    [CmdletBinding()]
    param (
        # An internal hostname (usually a DC or file server) to prove
        # internal DNS separately from external DNS.
        [string]$InternalHost,

        # External name used to test public DNS resolution.
        [string]$ExternalHost = 'www.microsoft.com',

        [ValidateRange(500, 10000)]
        [int]$TimeoutMs = 3000,

        # Emit a paste-ready ticket note instead of raw check objects.
        [switch]$AsTicketNote
    )

    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    # Local helper so every check lands in the list with the same shape.
    $addCheck = {
        param ($Layer, $Check, $Result, $Detail, $PlainEnglish)
        $results.Add([pscustomobject]@{
            Layer        = $Layer
            Check        = $Check
            Result       = $Result   # Pass / Fail / Skip
            Detail       = $Detail
            PlainEnglish = $PlainEnglish
        })
    }

    # --- Layer 1: adapter ------------------------------------------------
    if ($script:SdIsWindows) {
        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
        if ($adapters.Count -gt 0) {
            & $addCheck 1 'Network adapter up' 'Pass' (($adapters.Name | Select-Object -First 3) -join ', ') `
                'A network adapter is connected.'
        }
        else {
            & $addCheck 1 'Network adapter up' 'Fail' 'No adapters in Up state' `
                'No connected adapter was found. Check the cable, Wi-Fi or dock.'
        }
    }
    else {
        & $addCheck 1 'Network adapter up' 'Skip' 'Adapter enumeration is Windows-only' `
            'Skipped on this platform.'
    }

    # --- Layer 2: IP address / DHCP ---------------------------------------
    if ($script:SdIsWindows) {
        $ipConfigs = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4Address -and $_.NetAdapter.Status -eq 'Up' })
        $ipv4 = $ipConfigs | ForEach-Object { $_.IPv4Address.IPAddress } | Select-Object -First 1
        if ($ipv4 -and $ipv4 -like '169.254.*') {
            & $addCheck 2 'IP address (DHCP)' 'Fail' "APIPA address $ipv4" `
                'The computer has an automatic private address. Check DHCP, the switch port and cabling.'
        }
        elseif ($ipv4) {
            $gw = $ipConfigs | ForEach-Object { $_.IPv4DefaultGateway.NextHop } | Select-Object -First 1
            & $addCheck 2 'IP address (DHCP)' 'Pass' "IP $ipv4, gateway $gw" `
                'The computer has a valid address on the local network.'
        }
        else {
            & $addCheck 2 'IP address (DHCP)' 'Fail' 'No IPv4 address found' `
                'The computer has no usable network address.'
        }

        # --- Layer 3: gateway reachability --------------------------------
        $gateway = $ipConfigs | ForEach-Object { $_.IPv4DefaultGateway.NextHop } | Select-Object -First 1
        if ($gateway) {
            $gwOk = Test-SdPing -ComputerName $gateway -Count 2
            if ($gwOk) {
                & $addCheck 3 'Default gateway ping' 'Pass' $gateway `
                    'The local router is responding.'
            }
            else {
                & $addCheck 3 'Default gateway ping' 'Fail' "$gateway not responding" `
                    'The gateway did not answer ICMP. Confirm whether ICMP is allowed before treating this as an outage.'
            }
        }
        else {
            & $addCheck 3 'Default gateway ping' 'Skip' 'No default gateway configured' `
                'No route off the local network is configured.'
        }
    }
    else {
        & $addCheck 2 'IP address (DHCP)' 'Skip' 'Windows-only check' 'Skipped on this platform.'
        & $addCheck 3 'Default gateway ping' 'Skip' 'Windows-only check' 'Skipped on this platform.'
    }

    # --- Layer 4: DNS ------------------------------------------------------
    if ($InternalHost) {
        try {
            $addresses = Resolve-SdHostAddress -HostName $InternalHost
            & $addCheck 4 "Internal DNS ($InternalHost)" 'Pass' (($addresses | Select-Object -First 2) -join ', ') `
                'Internal name resolution is working - the domain controller/DNS server is reachable.'
        }
        catch {
            & $addCheck 4 "Internal DNS ($InternalHost)" 'Fail' $_.Exception.Message `
                'The computer cannot look up internal server names - logins and file shares will play up. Check the DNS server.'
        }
    }

    try {
        $addresses = Resolve-SdHostAddress -HostName $ExternalHost
        & $addCheck 4 "External DNS ($ExternalHost)" 'Pass' (($addresses | Select-Object -First 2) -join ', ') `
            'Public website names are resolving correctly.'
    }
    catch {
        & $addCheck 4 "External DNS ($ExternalHost)" 'Fail' $_.Exception.Message `
            'The computer cannot look up website names - the internet will appear "down" even if the link is fine.'
    }

    # --- Layer 5: HTTPS egress ---------------------------------------------
    if (Test-SdTcpPort -HostName $ExternalHost -Port 443 -TimeoutMs $TimeoutMs) {
        & $addCheck 5 'HTTPS egress (443)' 'Pass' "$ExternalHost`:443 reachable" `
            'General internet access is working.'
    }
    else {
        & $addCheck 5 'HTTPS egress (443)' 'Fail' "$ExternalHost`:443 unreachable" `
            'Websites cannot be reached - likely an internet outage or a firewall rule.'
    }

    # --- Layer 6: Microsoft 365 front doors ---------------------------------
    foreach ($endpoint in 'login.microsoftonline.com', 'outlook.office365.com') {
        if (Test-SdTcpPort -HostName $endpoint -Port 443 -TimeoutMs $TimeoutMs) {
            & $addCheck 6 "M365 endpoint ($endpoint)" 'Pass' 'Reachable on 443' `
                'Microsoft 365 sign-in and mail services are reachable from here.'
        }
        else {
            & $addCheck 6 "M365 endpoint ($endpoint)" 'Fail' 'Unreachable on 443' `
                'Microsoft 365 could not be reached on TCP 443. Check the firewall, proxy and content filter.'
        }
    }

    # --- Layer 7: VPN state (informational) ---------------------------------
    if ($script:SdIsWindows -and (Get-Command Get-VpnConnection -ErrorAction SilentlyContinue)) {
        $vpns = @(Get-VpnConnection -ErrorAction SilentlyContinue | Where-Object ConnectionStatus -eq 'Connected')
        if ($vpns.Count -gt 0) {
            & $addCheck 7 'VPN connected' 'Pass' (($vpns.Name) -join ', ') `
                'A VPN is connected and may affect routing or DNS.'
        }
        else {
            & $addCheck 7 'VPN connected' 'Skip' 'No VPN connections active' `
                'No VPN in play.'
        }
    }

    if ($AsTicketNote) {
        $fails = @($results | Where-Object Result -eq 'Fail')
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine(('=== NETWORK STACK CHECK - {0} ===' -f [System.Environment]::MachineName))
        [void]$sb.AppendLine(('Captured: {0}' -f (Get-Date -Format $script:SdDateFormat)))
        [void]$sb.AppendLine()
        foreach ($check in $results) {
            [void]$sb.AppendLine(('  [{0}] L{1} {2} - {3}' -f $check.Result.ToUpper(), $check.Layer, $check.Check, $check.Detail))
        }
        [void]$sb.AppendLine()
        if ($fails.Count -eq 0) {
            [void]$sb.AppendLine('SUMMARY: All layers passing - the network stack looks healthy from this machine.')
        }
        else {
            [void]$sb.AppendLine(('SUMMARY: First failing layer is L{0} ({1}).' -f $fails[0].Layer, $fails[0].Check))
            [void]$sb.AppendLine(('  In plain English: {0}' -f $fails[0].PlainEnglish))
        }
        return $sb.ToString()
    }

    return $results
}
