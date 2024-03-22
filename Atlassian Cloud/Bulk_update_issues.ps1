<#
Allows for bulk editing many issues. The bulk edit tool using advanced issue
search only operates on 1000 at a time.
#>

param (
    [Parameter(
        Position = 0,
        Mandatory = $true,
        HelpMessage = "Enter a query")]
    [string]$Query,

    [Parameter(
        Position = 1,
        Mandatory = $true
    )]
    [string]$Property,

    [Parameter(
        Position = 2,
        Mandatory = $true
    )]
    [string]$Value,

    [Parameter(
        Position = 3,
        Mandatory = $true
    )]
    [string]$Operation
)

. $PSScriptRoot\Atlassian_Functions.ps1

[array]$IssueList = Search-JiraIssues $Query 'key' | Select-Object -ExpandProperty 'key'

if (!$IssueList) {
    Write-Warning "No issues found"
    return
}

$Metadata = Get-EditIssueMetadata $IssueList[0]

$AllowedIssueFields = ($MetaData | Get-Member -MemberType NoteProperty).Name | Sort-Object

if ($AllowedIssueFields -notcontains $Property) {
    Write-Warning "`"$Property`" is not a valid field. Please select from one of the following: $($AllowedIssueFields -join ', ')"
    return
}

# Attempt to select the correct value based on the name provided if the
# property has specific allowed values.
if ($Metadata.$Property.allowedValues) {

    $AllowedValues = $Metadata.$Property.allowedValues

    # Handle each type differently since they don't all have a 'Name' property
    switch ($Metadata.$Property.schema.type) {

        'array' {}
        'issuetype' {}
        'option' {}
        'priority' {}
        'sd-request-lang' {}
        'securitylevel' {

            $FieldValue = $AllowedValues | Where-Object { $_.name -eq $Value }

            if (!$FieldValue) {
                Write-Warning "`"$Value`" is not a valid field value. Please select from the following: $(($AllowedValues.name | Sort-Object) -join ', ')"
            }
            break

        }
        Default { Write-Warning "Sorry, handling the `"$_`" type has not yet been implemented."; return }
    }

}
else {
    <# todo: assign the $FieldValue when an allowedValue is not present. #>
}

# Verify that the operation is supported
if ($Metadata.$Property.operations -notcontains $Operation) {
    Write-Warning "The `"$Operation`" operation is not supported by this field. Please select from the following: $($Metadata.$Property.operations -join ', ')"
    return
}

for ($i = 82; $i -lt $IssueList.Count; $i++) {

    Write-Progress -Activity "Editing issues" -Status "Progress: $i/$($IssueList.Count)" -PercentComplete ($i / $IssueList.Count * 100)

    try {
        $null = Edit-JiraIssue -IssueIdOrKey $IssueList[$i] -Property $Property -Value $FieldValue -Operation $Operation
    }
    catch {
        Write-Warning "$($IssueList[$i]) error"
    }

}

Write-Progress -Activity "Editing issues" -Completed
