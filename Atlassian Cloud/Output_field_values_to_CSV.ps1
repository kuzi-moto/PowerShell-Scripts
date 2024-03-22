<#
.SYNOPSIS
    Script to output all of the field names and values to a spreadsheet
.DESCRIPTION
    Script to output all of the field names and values to a spreadsheet
    This is useful when you have hundreds of custom values and would like
    an easy way to refer to all the values.
.PARAMETER IssueKey
    This is required, enter any issue key such as 'IT-1234'
.PARAMETER Path
    Define a custom output path for the .csv file. Defaults to '.\output.csv'
.EXAMPLE
    PS C:\> .\Output_field_values_to_CSV.ps1 [issue key]
    Runs the script against an issue you would like to pull all the fields from
#>

param (
    [Parameter(Mandatory=$true, HelpMessage="Enter an issue key")]
    [string]$IssueKey,

    [string]$Path = ".\issuefields_output.csv"
)

. $PSScriptRoot\Atlassian_Functions.ps1

$Hash = @{}

$Response = Invoke-AtlassianApiRequest "issue/$IssueKey`?expand=names"

$Response.names | Get-Member -MemberType NoteProperty | ForEach-Object {
    $Hash.Add($_.Name, @{
        DisplayName = $Response.names.($_.Name)
        Value = $_.Name
    })
}

$Hash.GetEnumerator() | Sort-Object $_.Key | ForEach-Object {
    [PSCustomObject]$_.Value
} | Export-Csv -Path $Path -NoTypeInformation

Write-Host "File saved to $Path"
