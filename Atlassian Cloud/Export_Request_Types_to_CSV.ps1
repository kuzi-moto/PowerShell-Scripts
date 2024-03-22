<#
Exports the sevice request types for a Service Management project to a CSV.
#>

param (
    [Parameter(
        Position = 0,
        Mandatory = $true,
        HelpMessage = "Enter a query")]
    [string]$Query,

    [Parameter(
        Position = 1
    )]
    [string]$Path = ".\output.csv"
)

. $PSScriptRoot\Atlassian_Functions.ps1

$RequestTypes = Get-AtlassianRequestTypes $Query

$RequestTypeGroups = @{}

Get-AtlassianRequestTypeGroups $Query | ForEach-Object {
    $RequestTypeGroups.($_.id) = $_.name
}

Get-AtlassianRequestTypeGroups $Query | ForEach-Object {
    @{name = $_.id; value = $_.name }
}

$GroupIdExpression = {
    ($_.groupIds | ForEach-Object { $RequestTypeGroups.($_) }) -join ', '
}

$RequestTypes | Select-Object -Property name,description,helpText,@{l='groups';e={($_.groupIds | ForEach-Object { $RequestTypeGroups.($_) }) -join ', '}} | Export-Csv -Path $Path
