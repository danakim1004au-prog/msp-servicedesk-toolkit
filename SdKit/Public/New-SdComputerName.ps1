function New-SdComputerName {
    <#
    .SYNOPSIS
        Builds a computer name from a configured pattern.

    .DESCRIPTION
        Replaces the `code`, `type` and `serial` tokens, removes unsupported
        characters and enforces the 15-character NetBIOS limit. When trimming
        is required, the end of the serial number is retained.

    .EXAMPLE
        New-SdComputerName -Pattern '{code}-{type}-{serial}' -ClientCode 'ACME' -DeviceType LT -Serial '5CG12345XY'
        # ACME-LT-2345XY (trimmed to fit 15 characters)
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This function returns a value and does not change system state.')]
    [OutputType([string])]
    param (
        # Naming pattern with {code}, {type} and {serial} tokens.
        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$ClientCode,

        # LT = laptop, DT = desktop, WS = workstation/CAD - whatever the
        # client convention uses.
        [Parameter(Mandatory)]
        [string]$DeviceType,

        # BIOS serial or asset tag, whichever the pattern calls for.
        [Parameter(Mandatory)]
        [string]$Serial
    )

    if ([string]::IsNullOrWhiteSpace($Serial)) {
        throw 'Serial must contain at least one character.'
    }

    $unknownTokens = [regex]::Matches($Pattern, '\{([^}]+)\}') |
        ForEach-Object { $_.Groups[1].Value } |
        Where-Object { $_ -notin @('code', 'type', 'serial') } |
        Select-Object -Unique
    if ($unknownTokens) {
        throw "Pattern contains unsupported token(s): $($unknownTokens -join ', '). Use {code}, {type} and {serial}."
    }

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
        # Over the NetBIOS limit - shorten the serial portion, keeping its
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
        # If it's still too long the pattern itself is the problem -
        # hard-truncate and let the tech know.
        if ($name.Length -gt 15) {
            $name = $name.Substring(0, 15)
            Write-Warning "Pattern produced a name over 15 characters even with a trimmed serial - hard-truncated to '$name'. Check the client's naming convention."
        }
    }

    if ([string]::IsNullOrWhiteSpace($name)) {
        throw 'Pattern and supplied values produced an empty computer name.'
    }

    return $name
}
