function Assert-SdAdModule {
    <#
    .SYNOPSIS
        Shared guard for every command that talks to on-premises Active Directory.

    .DESCRIPTION
        Fails fast with a friendly message instead of a bare
        "term not recognised" when RSAT / the ActiveDirectory module isn't
        present. On a desk this usually means "run it from the jump box or a
        machine with RSAT installed", so the message says exactly that.
    #>
    [CmdletBinding()]
    param ()

    if (-not (Get-Module -ListAvailable -Name 'ActiveDirectory')) {
        throw ("The ActiveDirectory PowerShell module isn't available. Run this from a " +
               "domain-joined admin box or jump host with RSAT installed:`n" +
               '  Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"')
    }

    # Import on demand so the module loads cleanly on machines (and CI) that
    # will never have RSAT — the guard only bites when an AD command is run.
    if (-not (Get-Module -Name 'ActiveDirectory')) {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
}
