function Get-SdClientConfig {
    <#
    .SYNOPSIS
        Loads and validates the per-client configuration file.

    .DESCRIPTION
        The MSP keeps one JSON file describing each managed client — tenant
        domain, UPN pattern, computer naming convention, default licence and
        groups. Commands like New-SdClientUser and Invoke-SdPcRunUp read it
        so client-specific detail lives in config, not in scripts.

        The real clients.json is git-ignored (it holds client identifiers);
        only clients.sample.json is committed. Validation is strict and the
        error messages say exactly which client and which field is missing,
        because a half-filled config is worse than none.

    .EXAMPLE
        Get-SdClientConfig -Path ./config/clients.json -ClientCode ACME
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        # Return just one client by its short code (e.g. ACME). Omit to get
        # every client in the file.
        [string]$ClientCode
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Client config not found at '$Path'. Copy config/clients.sample.json to clients.json and fill in your clients."
    }

    try {
        $config = Get-Content -Path $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Client config at '$Path' is not valid JSON: $($_.Exception.Message)"
    }

    if (-not $config.clients) {
        throw "Client config at '$Path' has no 'clients' array."
    }

    # Fields every client entry must carry before any automation runs
    # against them — better to fail here than halfway through an onboarding.
    $required = @('code', 'name', 'domain', 'upnPattern', 'computerNamePattern')
    foreach ($client in $config.clients) {
        foreach ($field in $required) {
            if (-not $client.$field) {
                $label = if ($client.code) { $client.code } else { '<no code>' }
                throw "Client '$label' in '$Path' is missing required field '$field'."
            }
        }

        if ($client.upnPattern -match '\{(?!first|last)[^}]+\}') {
            throw "Client '$($client.code)' in '$Path' has an unsupported token in 'upnPattern'. Use {first} and {last}."
        }

        if ($client.computerNamePattern -match '\{(?!code|type|serial)[^}]+\}') {
            throw "Client '$($client.code)' in '$Path' has an unsupported token in 'computerNamePattern'. Use {code}, {type} and {serial}."
        }
    }

    $duplicateCodes = @($config.clients.code | Group-Object | Where-Object Count -gt 1)
    if ($duplicateCodes.Count -gt 0) {
        throw "Client config at '$Path' contains duplicate client code(s): $($duplicateCodes.Name -join ', ')"
    }

    if ($ClientCode) {
        $match = $config.clients | Where-Object { $_.code -eq $ClientCode }
        if (-not $match) {
            $known = ($config.clients.code | Sort-Object) -join ', '
            throw "No client with code '$ClientCode' in '$Path'. Known codes: $known"
        }
        return $match
    }

    return $config.clients
}
