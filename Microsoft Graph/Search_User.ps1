[CmdletBinding()]
param (
    [Parameter()]
    [String]
    $Query,
    [string[]]
    $Property
)

$DefaultProperties = @(
    'DisplayName'
    'GivenName'
    'Id'
    'Mail'
    'Surname'
    'UserPrincipalName'
)

$Context = Get-MgContext

if (-not $Context) {
    Connect-MgGraph 'User.Read.All'
}

$Params = @{}

if ($Property) {
    $Params.Property = $Property + $DefaultProperties | Select-Object -Unique
}

switch -regex ($Query) {
    # User's GUID
    '\b[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}\b' {
        $Params.UserId = $Query
        break
    }
    # string with a period to indicate an email address
    '^[^.]+\.[^.]+$' {
        $Params.Filter = "startsWith(Mail, '$Query')"
        break
    }
    # By default, try the display name
    Default { $Params.Filter = "startsWith(DisplayName, '$Query')" }
}

if (!$Params.UserId) {
    $Params.ConsistencyLevel = 'eventual'
    $Params.CountVariable = 'userCount'
}

# Consistencylevel and Count required to use 'endsWith()'

$Data = Get-MgUser @Params

if ($Data.Count -eq 1) { $Data }
elseif ($Data.Count -gt 1 ) {
    $Data | Select-Object DisplayName, Id, Mail | Out-Host
    Write-Warning "Search returns $($Data.Count) results. Try using a more specific query."
}
else {
    Write-Warning "Search returned no results"
}
