function New-SdTempPassword {
    <#
    .SYNOPSIS
        Generates a temporary password.

    .DESCRIPTION
        Builds a temporary passphrase from a fixed word list, two digits and
        a symbol. Random values are selected with a cryptographic random
        number generator. Calling commands require a password change at the
        next sign-in.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This function returns a value and does not change system state.')]
    [OutputType([string])]
    param (
        # Number of words in the passphrase.
        [ValidateRange(2, 5)]
        [int]$WordCount = 3
    )

    # Familiar words reduce transcription errors during an approved
    # out-of-band handover.
    $words = @(
        'Wattle', 'Banksia', 'Jarrah', 'Karri', 'Mallee', 'Mulga',
        'Harbour', 'Jetty', 'Lagoon', 'Outback', 'Paddock', 'Billabong',
        'Kookaburra', 'Wombat', 'Echidna', 'Galah', 'Brolga', 'Dingo',
        'Coral', 'Opal', 'Quartz', 'Granite', 'Basalt', 'Ochre',
        'Summit', 'Valley', 'Ridge', 'Plateau', 'Estuary', 'Headland'
    )

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $pick = {
            param ([int]$Maximum)

            if ($Maximum -le 0) {
                throw 'Maximum must be greater than zero.'
            }

            # Rejection sampling avoids Int32.MinValue overflow and modulo
            # bias while remaining compatible with Windows PowerShell 5.1.
            $range = [uint64][int]::MaxValue + 1
            $limit = $range - ($range % [uint64]$Maximum)
            $bytes = New-Object byte[] 4
            do {
                $rng.GetBytes($bytes)
                $value = [uint64]([BitConverter]::ToUInt32($bytes, 0) -band 0x7fffffff)
            } while ($value -ge $limit)

            return [int]($value % [uint64]$Maximum)
        }

        $chosen = for ($i = 0; $i -lt $WordCount; $i++) {
            $words[(& $pick $words.Count)]
        }
        $digits = '{0}{1}' -f (& $pick 10), (& $pick 10)
        $symbol = ('!', '@', '#', '%', '?')[(& $pick 5)]

        return ('{0}{1}{2}' -f ($chosen -join '-'), $digits, $symbol)
    }
    finally {
        $rng.Dispose()
    }
}
