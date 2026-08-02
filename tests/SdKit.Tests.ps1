# =====================================================================
#  SdKit — Pester 5 tests
#  Focused on the pure logic that can run anywhere (macOS/Linux CI or a
#  Windows bench machine): note formatting, naming conventions, config
#  validation and the password generator. The Windows-only collectors
#  (triage, run-up, E8) are exercised on a Windows box or lab VM.
#
#  Run with:  Invoke-Pester -Path ./tests
# =====================================================================

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'SdKit' 'SdKit.psd1'
    Import-Module $modulePath -Force
    $script:SamplesConfig = Join-Path $PSScriptRoot '..' 'config' 'clients.sample.json'
}

Describe 'Module manifest' {
    It 'is a valid module manifest' {
        $manifest = Test-ModuleManifest -Path (Join-Path $PSScriptRoot '..' 'SdKit' 'SdKit.psd1') -ErrorAction Stop
        $manifest.Name | Should -Be 'SdKit'
    }

    It 'exports exactly the eleven public commands' {
        $exported = (Get-Module SdKit).ExportedFunctions.Keys | Sort-Object
        $exported | Should -Be @(
            'Disable-SdClientUser'
            'Get-SdClientConfig'
            'Get-SdUserSnapshot'
            'Invoke-SdPcRunUp'
            'Invoke-SdTriage'
            'New-SdClientUser'
            'New-SdComputerName'
            'New-SdTicketNote'
            'Reset-SdAdAccount'
            'Test-SdEssentialEight'
            'Test-SdNetworkStack'
        )
    }
}

Describe 'New-SdTicketNote' {
    It 'produces the standard sections in order' {
        $note = New-SdTicketNote -Summary 'Printer offline' -Client 'Acme' -Contact 'Sarah' `
            -Issue 'Reception printer showing offline.' `
            -Impact 'Reception cannot print settlement packs.' `
            -Steps 'Power-cycled printer', 'Cleared stuck job from queue' `
            -Cause 'Stuck spooler job.' `
            -Resolution 'Queue cleared, test page printed.' `
            -Status Resolved -TimeSpentMinutes 15

        $note | Should -Match '=== TICKET NOTE — Printer offline ==='
        $note | Should -Match 'ISSUE'
        $note | Should -Match 'IMPACT'
        $note | Should -Match '1\. Power-cycled printer'
        $note | Should -Match '2\. Cleared stuck job from queue'
        $note | Should -Match 'CAUSE'
        $note | Should -Match 'RESOLUTION'
        $note | Should -Match 'Time spent:  15 min'
        # Australian date format, dd/MM/yyyy
        $note | Should -Match 'Date:\s+\d{2}/\d{2}/\d{4}'
    }

    It 'switches to a handover format for escalations' {
        $note = New-SdTicketNote -Summary 'Server BSOD' -Escalation -EscalateTo 'L3 - Marcus' `
            -Issue 'Hyper-V host blue-screened twice.' `
            -Steps 'Collected minidumps' `
            -RuledOut 'Not patch-related — stable for 3 weeks post-update'

        $note | Should -Match '=== ESCALATION HANDOVER — Server BSOD ==='
        $note | Should -Match 'Status:      Escalated'
        $note | Should -Match 'Escalated to: L3 - Marcus'
        $note | Should -Match 'RULED OUT'
    }

    It 'omits sections that were not provided' {
        $note = New-SdTicketNote -Summary 'Quick job' -Issue 'Something small.'
        $note | Should -Not -Match 'IMPACT'
        $note | Should -Not -Match 'RULED OUT'
        $note | Should -Not -Match 'Time spent'
    }
}

Describe 'New-SdComputerName' {
    It 'substitutes tokens and upper-cases the result' {
        New-SdComputerName -Pattern '{code}-{type}-{serial}' -ClientCode 'acme' -DeviceType 'lt' -Serial 'ab123' |
            Should -Be 'ACME-LT-AB123'
    }

    It 'strips illegal characters from the serial' {
        New-SdComputerName -Pattern '{code}-{type}-{serial}' -ClientCode 'BLU' -DeviceType 'DT' -Serial 'S/N 99-88' |
            Should -Be 'BLU-DT-SN9988'
    }

    It 'keeps the tail of a long serial to stay under 15 characters' {
        $name = New-SdComputerName -Pattern '{code}-{type}-{serial}' -ClientCode 'ACME' -DeviceType 'LT' -Serial '5CG1234567890XY'
        $name.Length | Should -BeLessOrEqual 15
        # The distinctive tail of the serial survives the trim.
        $name | Should -Match 'XY$'
        $name | Should -Match '^ACME-LT-'
    }

    It 'hard-truncates and warns when the pattern itself is too long' {
        $name = New-SdComputerName -Pattern '{code}-{type}-{serial}' -ClientCode 'LONGCLIENTCODE' -DeviceType 'DT' -Serial 'A1' -WarningAction SilentlyContinue
        $name.Length | Should -BeLessOrEqual 15
    }

    It 'rejects unsupported naming tokens' {
        { New-SdComputerName -Pattern '{code}-{asset}-{serial}' -ClientCode 'ACME' -DeviceType 'LT' -Serial 'A1' } |
            Should -Throw '*unsupported token*'
    }

    It 'rejects an empty serial' {
        { New-SdComputerName -Pattern '{code}-{type}-{serial}' -ClientCode 'ACME' -DeviceType 'LT' -Serial ' ' } |
            Should -Throw '*Serial must contain*'
    }
}

Describe 'Get-SdClientConfig' {
    It 'loads all clients from the sample config' {
        $clients = Get-SdClientConfig -Path $script:SamplesConfig
        @($clients).Count | Should -Be 2
    }

    It 'returns a single client by code' {
        $client = Get-SdClientConfig -Path $script:SamplesConfig -ClientCode ACME
        $client.name | Should -Be 'Acme Conveyancing Pty Ltd'
        $client.domain | Should -Be 'acme.example.com.au'
    }

    It 'lists the known codes when the code does not exist' {
        { Get-SdClientConfig -Path $script:SamplesConfig -ClientCode NOPE } |
            Should -Throw '*Known codes: ACME, BLU*'
    }

    It 'fails with a helpful message when the file is missing' {
        { Get-SdClientConfig -Path './does-not-exist.json' } |
            Should -Throw '*clients.sample.json*'
    }

    It 'names the client and field when a required field is missing' {
        $broken = Join-Path ([System.IO.Path]::GetTempPath()) 'sdkit-broken-clients.json'
        @{ clients = @(@{ code = 'BAD'; name = 'Bad Co' }) } | ConvertTo-Json -Depth 5 | Set-Content -Path $broken
        try {
            { Get-SdClientConfig -Path $broken } | Should -Throw "*Client 'BAD'*missing required field 'domain'*"
        }
        finally {
            Remove-Item -Path $broken -ErrorAction SilentlyContinue
        }
    }

    It 'rejects duplicate client codes' {
        $broken = Join-Path ([System.IO.Path]::GetTempPath()) 'sdkit-duplicate-clients.json'
        @{ clients = @(
            @{ code = 'DUP'; name = 'First Co'; domain = 'first.example.com'; upnPattern = '{first}.{last}'; computerNamePattern = '{code}-{type}-{serial}' },
            @{ code = 'DUP'; name = 'Second Co'; domain = 'second.example.com'; upnPattern = '{first}.{last}'; computerNamePattern = '{code}-{type}-{serial}' }
        ) } | ConvertTo-Json -Depth 5 | Set-Content -Path $broken
        try {
            { Get-SdClientConfig -Path $broken } | Should -Throw '*duplicate client code*'
        }
        finally {
            Remove-Item -Path $broken -ErrorAction SilentlyContinue
        }
    }

    It 'rejects unsupported pattern tokens' {
        $broken = Join-Path ([System.IO.Path]::GetTempPath()) 'sdkit-unsupported-token.json'
        @{ clients = @(
            @{ code = 'BAD'; name = 'Bad Co'; domain = 'bad.example.com'; upnPattern = '{first}.{middle}.{last}'; computerNamePattern = '{code}-{type}-{serial}' }
        ) } | ConvertTo-Json -Depth 5 | Set-Content -Path $broken
        try {
            { Get-SdClientConfig -Path $broken } | Should -Throw '*unsupported token*'
        }
        finally {
            Remove-Item -Path $broken -ErrorAction SilentlyContinue
        }
    }
}

Describe 'New-SdTempPassword (private)' {
    It 'generates passwords with words, digits and a symbol' {
        InModuleScope SdKit {
            $password = New-SdTempPassword
            # Three capitalised words joined by hyphens, two digits, one symbol.
            $password | Should -Match '^([A-Z][a-z]+-){2}[A-Z][a-z]+\d{2}[!@#%?]$'
        }
    }

    It 'respects the word count parameter' {
        InModuleScope SdKit {
            $password = New-SdTempPassword -WordCount 5
            ($password -split '-').Count | Should -Be 5
        }
    }

    It 'does not repeat itself across runs' {
        InModuleScope SdKit {
            $passwords = 1..20 | ForEach-Object { New-SdTempPassword }
            ($passwords | Select-Object -Unique).Count | Should -BeGreaterThan 15
        }
    }
}

Describe 'Format-SdTriageNote (private)' {
    It 'formats a fabricated snapshot and flags low disk space' {
        InModuleScope SdKit {
            $fake = [pscustomobject]@{
                ComputerName     = 'ACME-LT-2345XY'
                Captured         = '01/07/2026 09:15'
                Client           = 'Acme Conveyancing'
                Contact          = 'Sarah M'
                Model            = 'HP EliteBook 840 G9'
                SerialNumber     = '5CG12345XY'
                OperatingSystem  = 'Windows 11 Pro (build 26100)'
                Uptime           = '21d 4h 2m  << consider a restart'
                Memory           = '16 GB'
                PendingReboot    = $true
                LastHotfix       = 'KB5041585 on 12/06/2026'
                EventWindowHours = 24
                Disks            = @(
                    [pscustomobject]@{ Drive = 'C:'; SizeGB = 476.0; FreeGB = 21.5; PercentFree = 5 }
                )
                RecentErrors     = @(
                    [pscustomobject]@{ Log = 'System'; Provider = 'disk'; Count = 14 }
                )
                Printers         = @(
                    [pscustomobject]@{ Name = 'Reception-MFP'; Status = 'Normal' }
                )
                Network          = $null
            }

            $note = Format-SdTriageNote -Triage $fake
            $note | Should -Match '=== WORKSTATION TRIAGE — ACME-LT-2345XY ==='
            $note | Should -Match '<< LOW SPACE'
            $note | Should -Match '14x  disk \[System\]'
            $note | Should -Match 'Reception-MFP'
        }
    }
}

Describe 'Reset-SdAdAccount' {
    It 'fails with an RSAT install hint when the ActiveDirectory module is absent' -Skip:([bool](Get-Module -ListAvailable -Name ActiveDirectory)) {
        # On a box without RSAT (macOS/Linux CI), the AD guard should give a
        # human answer, not a bare "term not recognised".
        { Reset-SdAdAccount -Identity jsmith -Unlock } | Should -Throw '*RSAT*'
    }
}

Describe 'Test-SdNetworkStack' {
    It 'returns structured check objects with plain-English fields' {
        # DNS + TCP layers work cross-platform; Windows-only layers report Skip.
        $results = Test-SdNetworkStack
        @($results).Count | Should -BeGreaterThan 3
        foreach ($check in $results) {
            $check.Result | Should -BeIn @('Pass', 'Fail', 'Skip')
            $check.PlainEnglish | Should -Not -BeNullOrEmpty
        }
    }

    It 'produces a ticket note with a summary line' {
        $note = Test-SdNetworkStack -AsTicketNote
        $note | Should -Match '=== NETWORK STACK CHECK'
        $note | Should -Match 'SUMMARY:'
    }
}
