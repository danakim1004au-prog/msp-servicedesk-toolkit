function New-SdComputerName {
    <#
    .SYNOPSIS
        Builds a compliant computer name from a client's naming pattern.

    .DESCRIPTION
        Every client has their own naming convention, and getting it wrong
        during a run-up means a rename-and-reboot later. This takes the
        pattern from the client config (e.g. "{code}-{type}-{serial}"),
        substitutes the tokens, strips illegal characters and enforces the
        15-character NetBIOS limit — trimming the serial from the left so
        the distinctive tail end of the serial is kept.

    .EXAMPLE
        New-SdComputerName -Pattern '{code}-{type}-{serial}' -ClientCode 'ACME' -DeviceType LT -Serial '5CG12345XY'
        # ACME-LT-2345XY (trimmed to fit 15 characters)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # Naming pattern with {code}, {type} and {serial} tokens.
        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$ClientCode,

        # LT = laptop, DT = desktop, WS = workstation/CAD — whatever the
        # client convention uses.
        [Parameter(Mandatory)]
        [string]$DeviceType,

        # BIOS serial or asset tag, whichever the pattern calls for.
        [Parameter(Mandatory)]
        [string]$Serial
    )

    # Serials often carry spaces or symbols the OS won't accept in a name.
    $cleanSerial = ($Serial -replace '[^A-Za-z0-9]', '')

    $name = $Pattern.
        Replace('{code}', $ClientCode).
        Replace('{type}', $DeviceType).
        Replace('{serial}', $cleanSerial).
        ToUpper()

    # Strip anything that isn't a letter, digit or hyphen.
    $name = $name -replace '[^A-Z0-9\-]', ''

    if ($name.Length -gt 15) {
        # Over the NetBIOS limit — shorten the serial portion, keeping its
        # tail because that's usually the unique part.
        $overrun = $name.Length - 15
        if ($cleanSerial.Length -gt $overrun) {
            $trimmedSerial = $cleanSerial.Substring($overrun).ToUpper()
            $name = $Pattern.
                Replace('{code}', $ClientCode).
                Replace('{type}', $DeviceType).
                Replace('{serial}', $trimmedSerial).
                ToUpper()
            $name = $name -replace '[^A-Z0-9\-]', ''
        }
        # If it's still too long the pattern itself is the problem —
        # hard-truncate and let the tech know.
        if ($name.Length -gt 15) {
            $name = $name.Substring(0, 15)
            Write-Warning "Pattern produced a name over 15 characters even with a trimmed serial — hard-truncated to '$name'. Check the client's naming convention."
        }
    }

    return $name
}
