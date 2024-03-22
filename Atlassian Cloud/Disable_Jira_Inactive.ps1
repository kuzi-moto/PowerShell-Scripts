. $PSScriptRoot\Atlassian_Functions.ps1

$Users = Get-AllAtlassianDirectoryUsers

for ($i = 0; $i -lt $Users.Count; $i++) {

    Write-Progress -Activity 'Disabling Users' -Status "#$i/$($Users.Count)" -PercentComplete (($i + 1) / $Users.Count * 100)

    if ($Users[$i].account_status -match 'inactive|closed') {
        continue
    }
    else {
        $User = Get-AtlassianUser $Users[$i].account_id
    }

    if ($User.active -eq $true) {
        continue
    }

    $null = Disable-AtlassianUser $Users[$i].account_id

    Write-Host "$($Users[$i].name) - disabled" -ForegroundColor Green

}

Write-Progress -Activity 'Disabling Users' -Completed
