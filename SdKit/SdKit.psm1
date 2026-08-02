# =====================================================================
#  SdKit — module loader
#  Dot-sources every function under Public/ and Private/, then exports
#  only the public ones. Keeps each command in its own file so changes
#  are easy to review and the git history stays tidy.
# =====================================================================

# PowerShell 5.1 doesn't define $IsWindows, but 5.1 only ever runs on
# Windows — so we work it out once here and reuse it everywhere.
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $script:SdIsWindows = $IsWindows
}
else {
    $script:SdIsWindows = $true
}

# Australian-style timestamps for ticket notes and reports (dd/MM/yyyy).
$script:SdDateFormat = 'dd/MM/yyyy HH:mm'

$public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue)
$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($public + $private)) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "Failed to load $($file.Name): $_"
    }
}

Export-ModuleMember -Function $public.BaseName
