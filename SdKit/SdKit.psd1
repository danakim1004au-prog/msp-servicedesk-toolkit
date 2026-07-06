# =====================================================================
#  SdKit — MSP Service Desk Toolkit (module manifest)
#  A day-one toolkit for Level 1 / Level 2 service desk work at a
#  managed services provider: triage, ticket notes, M365 user admin,
#  PC run-ups and quick Essential Eight sanity checks.
# =====================================================================
@{
    RootModule        = 'SdKit.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '3f7c2a4e-9b1d-4e6a-8c5f-2d7e9a0b4c61'
    Author            = 'Dana Kim'
    CompanyName       = 'Dana Kim (portfolio project)'
    Copyright         = '(c) 2026 Dana Kim. Licensed under the MIT licence.'
    Description       = 'Service desk toolkit for MSP techs: workstation triage, layered network diagnostics, standardised PSA ticket notes, Microsoft 365 user snapshots, onboarding/offboarding, SOE PC run-ups and an ACSC Essential Eight quick check.'
    PowerShellVersion = '5.1'

    # Only the polished, tech-facing commands are exported. Helpers such as
    # the temp password generator stay private to the module.
    FunctionsToExport = @(
        'Invoke-SdTriage'
        'Test-SdNetworkStack'
        'New-SdTicketNote'
        'Get-SdUserSnapshot'
        'New-SdClientUser'
        'Disable-SdClientUser'
        'Invoke-SdPcRunUp'
        'Test-SdEssentialEight'
        'New-SdComputerName'
        'Get-SdClientConfig'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('MSP', 'ServiceDesk', 'HelpDesk', 'Microsoft365', 'Intune', 'EssentialEight', 'Australia')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ReleaseNotes = 'Initial release: triage, network stack tests, ticket notes, M365 user lifecycle, PC run-ups, Essential Eight quick check.'
        }
    }
}
