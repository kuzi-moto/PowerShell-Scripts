<#
Exports any JQL expression to a .csv file. The advanced issue search in Jira
Cloud only allows for up to 1000 issues.
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

$IssueList = Search-JiraIssues $Query 'key'

$IssueList | Select-Object -Property 'key' | Export-Csv -Path $Path
