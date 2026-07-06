function New-SdTempPassword {
    <#
    .SYNOPSIS
        Generates a readable temporary password for new starters and resets.

    .DESCRIPTION
        Three random Aussie-flavoured words plus digits and a symbol,
        e.g. "Wattle-Harbour-Jetty47!". Easy to read out over the phone,
        hard to guess, and always paired with "must change at next sign-in"
        so it never lives longer than the first logon.

        Uses the cryptographic RNG rather than Get-Random so the choice of
        words and digits isn't tied to a predictable seed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # Number of words in the passphrase. Three is the sweet spot for
        # phone handovers; bump it up for anything longer-lived.
        [ValidateRange(2, 5)]
        [int]$WordCount = 3
    )

    # Deliberately familiar words — a client reading this back over the
    # phone shouldn't have to spell out anything exotic.
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
            param ($max)
            # Draw 4 random bytes and reduce modulo $max. The tiny modulo
            # bias is irrelevant at these ranges for a one-time password.
            $bytes = New-Object byte[] 4
            $rng.GetBytes($bytes)
            [Math]::Abs([BitConverter]::ToInt32($bytes, 0)) % $max
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
