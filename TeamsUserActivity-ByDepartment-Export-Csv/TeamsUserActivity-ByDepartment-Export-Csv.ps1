[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $Office365Domain,

    [Parameter(Mandatory = $true)]
    [String]
    $TeamsUserActivityFile
)

$UserActivity = Import-Csv $TeamsUserActivityFile

$MessagesByDepartment = @{}

Import-Module AzureAD

if (([Microsoft.Open.Azure.AD.CommonLibrary.AzureSession]::AccessTokens).count -lt 1) {
    Connect-AzureAD -TenantId $Office365Domain
}

Write-Progress "Getting AzureAD users"
$AllUsers = Get-AzureADUser -All $true

$AllUsers.Department | Select-Object -Unique | ForEach-Object {
    $MessagesByDepartment.($_) = 0
}

$DepartmentFor = @{}
for ($i = 0; $i -lt $AllUsers.Count; $i++) {
    $DepartmentFor.($AllUsers[$i].UserPrincipalName) = $AllUsers[$i].Department
}

$UserCount = 1
foreach ($User in $UserActivity) {
    Write-Progress "$UserCount/$($UserActivity.Count)"
    $Department = $DepartmentFor.($User.EmailId)
    if (!$Department) { $Department = "Empty" }
    $MessagesByDepartment.($Department) += [int]$User.ChatMessages
    $UserCount++
}

$MessagesByDepartment.GetEnumerator() | Select-Object @{name="Department";Expression={$_.Key}},@{name="MessageCount";expression={$_.Value}} | Export-Csv -NoTypeInformation -Path '.\MessagesByDepartment.csv'