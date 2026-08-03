function Get-SdLastHotfix {
    [CmdletBinding()]
    param ()

    return Get-HotFix -ErrorAction SilentlyContinue |
        Where-Object InstalledOn |
        Sort-Object InstalledOn -Descending |
        Select-Object -First 1
}
