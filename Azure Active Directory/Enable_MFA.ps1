$list = Import-Csv .\output.csv

Import-Module MSOnline

Connect-MsolService

$Auth = New-Object -TypeName Microsoft.Online.Administration.StrongAuthenticationRequirement
$Auth.RelyingParty = "*"
$Auth.State = "Enabled"
$AuthRequirements = @($Auth)

$EnabledUsers = @()

for ($i = 0; $i -lt $list.Count; $i++) {

    Write-Progress -Activity "Enabling MFA" -Status "User $($i+1)/$($list.Count)" -PercentComplete ($i/$list.Count*100)

    $User = Get-MsolUser -UserPrincipalName $list[$i].UserPrincipalName

    Write-Host "User: $($User.DisplayName)"

    if ($User.StrongAuthenticationMethods) {
        Write-Host "  - Already enabled"
    }
    else {
        $EnabledUsers += $User.UserPrincipalName
        Set-MsolUser -UserPrincipalName $User.UserPrincipalName -StrongAuthenticationRequirements $AuthRequirements
        Write-Host "  - Enabled MFA" -ForegroundColor Green
    }

}