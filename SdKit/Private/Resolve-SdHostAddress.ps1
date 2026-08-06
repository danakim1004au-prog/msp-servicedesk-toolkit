function Resolve-SdHostAddress {
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)]
        [string]$HostName
    )

    return @([System.Net.Dns]::GetHostAddresses($HostName) |
        ForEach-Object { $_.IPAddressToString })
}
