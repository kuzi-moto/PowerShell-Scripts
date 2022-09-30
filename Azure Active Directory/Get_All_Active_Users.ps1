Connect-AzureAD

$Users = Get-AzureADUser -All $true

$ActiveUsers = $Users | Where-Object { $_.AssignedLicenses.count -gt 0 -and $_.AccountEnabled -eq $true -and $_.ShowInAddressList -ne $false -and $_.Mail }

$ActiveUsers | Select-Object DisplayName, PhysicalDeliveryOfficeName, CompanyName, Mail | Export-Csv -Path ".\output.csv" -NoTypeInformation