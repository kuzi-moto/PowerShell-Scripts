. $PSScriptRoot\Atlassian_Functions.ps1

if (!$Users) {
    $Users = Get-AllAtlassianDirectoryUsers
}

if (!$GroupList) {
    $GroupList = Get-AtlassianAdminAllGroups
}

for ($i = 0; $i -lt $Users.Count; $i++) {

    Write-Progress -Activity 'Removing groups' -Status "#$i/$($Users.Count)" -PercentComplete (($i + 1) / $Users.Count * 100)

    if ($Users[$i].'account_status' -eq 'active') {
        continue
    }

    $UserGroups = Get-AtlassianUserGroups $Users[$i].account_id

    foreach ($Group in $UserGroups) {

        switch (($GroupList | Where-Object { $_.id -eq $Group.groupId}).unmodifiable) {
            'FALSE' {
                Remove-AtlassianGroupMember $Users[$i].account_id $Group.groupId
                Write-Host "Removed $($Users[$i].name) from $($Group.name)" -ForegroundColor Green
            }
            'TRUE' {
                Write-Warning "Skipping group $($Group.name) for $($Users[$i].name)"
            }
            Default { Write-Host 'skipped'}
        }

    }

}

Write-Progress -Activity 'Removing groups' -Completed
