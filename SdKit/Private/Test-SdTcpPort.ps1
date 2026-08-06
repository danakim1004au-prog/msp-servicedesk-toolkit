function Test-SdTcpPort {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string]$HostName,

        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [Parameter(Mandatory)]
        [ValidateRange(100, 60000)]
        [int]$TimeoutMs
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync($HostName, $Port)
        return [bool]($task.Wait($TimeoutMs) -and $client.Connected)
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}
