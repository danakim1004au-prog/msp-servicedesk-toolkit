function Test-SdPing {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [ValidateRange(1, 10)]
        [int]$Count = 2
    )

    $responses = @(Test-Connection -ComputerName $ComputerName -Count $Count -Quiet -ErrorAction SilentlyContinue)
    return [bool]($responses -contains $true)
}
