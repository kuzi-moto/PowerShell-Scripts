param(
    [Parameter(
        Position = 0
    )]
    [int]$Days = 90,
    [Parameter(
        Position = 1
    )]
    [string[]]$Products = @('jira-software', 'jira-service-desk', 'confluence')
)

. $PSScriptRoot\Atlassian_Functions.ps1

$Domain = (Get-AtlassianConfig domain) + ".atlassian.net"

#$UserList = Get-AllAtlassianDirectoryUsers

$UserReport = @()
$LicenseReport = @()

for ($i = 0; $i -lt $UserList.Count; $i++) {

    if (-not $UserList[$i].product_access) { continue }
    
    $Licenses = $UserList[$i].product_access | Where-Object { $_.key -in $Products -and $_.url -eq $Domain -and $_.last_active -lt (Get-Date).AddDays(-$Days) }

    if (!$Licenses) {
        continue
    }
    else {
        $Licenses | ForEach-Object {
            $LicenseReport += @{
                user        = $UserList[$i].email
                license     = $_.key
                last_active = $_.last_active
            }
        }
    }

    $UserReport += $UserList[0]

}