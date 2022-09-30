<#
.SYNOPSIS
    Gets all issue events.
.DESCRIPTION

.PARAMETER IssueKey
    This is required, enter any issue key such as 'IT-1234'
.PARAMETER Path
    Define a custom output path for the .csv file. Defaults to '.\output.csv'
.EXAMPLE
    PS C:\> .\Output_field_values_to_CSV.ps1 [issue key]
    Runs the script against an issue you would like to pull all the fields from
#>

param (
    [Parameter(Mandatory = $true, HelpMessage = "Enter user's Atlassian username")]
    [string]$User
)

. $PSScriptRoot\Atlassian_Functions.ps1

$Account = Get-AtlassianIdpDirectoryUser $User

[PSCustomObject]@{
    'Name'         = $Account.displayName
    'Username'     = $Account.userName
    'Email'        = $Account.emails[0].value
    'Atlassian ID' = $Account.'urn:scim:schemas:extension:atlassian-external:1.0'.atlassianAccountId
} | Out-Host

switch (Read-Host "Disable and remove IdP connection for $($Account.displayName) (y/n)") {
    'y' {
        if (Disable-AtlassianIdpDirectoryUser $User) {
            Write-Host "Successfully disabled Atlassian account $($Account.'urn:scim:schemas:extension:atlassian-external:1.0'.atlassianAccountId)"
        }
        else {
            Write-Error 'Something went wrong.'
        }
        break
    }
    'n' { Write-Warning 'Exiting, will not disable.'; break }
    Default { Write-Warning 'Exiting, did not select "y" or "n"' }
}