Import-Module MSOnline

Connect-MsolService

$Users = Get-MsolUser -EnabledFilter EnabledOnly -All | Where-Object { $_.isLicensed -eq $true}

$Users | Where-Object { -not $_.StrongAuthenticationMethods }

