function Get-SdLocalAdminState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param ()

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    $isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

    $adminCount = $null
    if (Get-Command Get-LocalGroupMember -ErrorAction SilentlyContinue) {
        $adminCount = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue).Count
    }

    return [pscustomobject]@{
        IsAdmin   = $isAdmin
        AdminCount = $adminCount
    }
}
