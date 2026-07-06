function Assert-SdGraphConnection {
    <#
    .SYNOPSIS
        Shared guard for every command that talks to Microsoft Graph.

    .DESCRIPTION
        Fails fast with a friendly, actionable message instead of letting a
        junior tech hit a wall of red text halfway through an onboarding.
        Checks that the Microsoft Graph PowerShell SDK is installed and that
        there's an active Connect-MgGraph session.
    #>
    [CmdletBinding()]
    param (
        # Scopes the calling command needs — included in the error message
        # so the fix is copy-paste ready.
        [Parameter(Mandatory)]
        [string[]]$RequiredScopes
    )

    if (-not (Get-Command -Name 'Connect-MgGraph' -ErrorAction SilentlyContinue)) {
        throw ("The Microsoft Graph PowerShell SDK isn't installed. Run:`n" +
               '  Install-Module Microsoft.Graph -Scope CurrentUser')
    }

    $context = Get-MgContext
    if (-not $context) {
        throw ("Not connected to Microsoft Graph. Connect to the client's tenant first:`n" +
               ('  Connect-MgGraph -Scopes "{0}"' -f ($RequiredScopes -join '","')))
    }

    # Warn (don't block) on missing scopes — some tenants grant broader
    # roles that satisfy the call anyway, so a hard stop would be annoying.
    $missing = $RequiredScopes | Where-Object { $context.Scopes -notcontains $_ }
    if ($missing) {
        Write-Warning ("Current Graph session may be missing scopes: {0}. " +
                       "If calls fail, reconnect with -Scopes." -f ($missing -join ', '))
    }

    return $context
}
