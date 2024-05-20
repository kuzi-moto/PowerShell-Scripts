
<# param (
    [Parameter(Mandatory = $true, HelpMessage = "Enter user's Atlassian username")]
    [string]$User
) #>

. $PSScriptRoot\Atlassian_Functions.ps1

if (!$Users) {
    $Users = Get-AllAtlassianDirectoryUsers
}

$Report = @()
$Domain = Get-AtlassianConfig domain

for ($i = 0; $i -lt $Users.Count; $i++) {

    Write-Progress -Activity 'Removing licenses' -Status "#$i/$($Users.Count)" -PercentComplete (($i + 1) / $Users.Count * 100)
    
    if (-not $Users[$i].product_access) { continue }

    $Products = $Users[$i].product_access | Where-Object { $_.name -notin @('Trello', 'Bitbucket', 'Jira Product Discovery') -and $_.url -eq "$Domain.atlassian.net" }

    if ($Users[$i].account_status -ne 'active') {

        foreach ($Product in $Products) {

            Write-Host "Removing $($Product.name) from $($Users[$i].name)"
            Revoke-AtlassianProductAccess $Users[$i].account_id $Product.key

        }

    }
    else {
        if ($Products | Where-Object { $_.last_active -lt (Get-Date).AddDays(-90) } ) {
            
            $Tokens = Get-AtlassianAdminUserApiTokens $Users[$i].account_id

            $LastToken = if ($Tokens) {
                $Tokens | Sort-Object lastAcccess -Descending | Select-Object -First 1
            }
            else { $null }

            $Properties = @(
                @{l = 'Name'; e = { $Users[$i].name } }
                @{l = 'Email'; e = { $Users[$i].email } }
                @{l = 'Product Name'; e = { $_.name } }
                @{l = 'Last Active'; e = { $_.last_active } }
                @{l = 'API Token Created'; e= {$LastToken.createdAt}}
                @{l = 'API Token Active'; e = { $LastToken.lastAccess } }
            )
            $Report += $Products | Where-Object { $_.last_active -lt (Get-Date).AddDays(-90) } | Select-Object -Property $Properties
        }
    }
    
}

Write-Progress -Activity 'Removing licenses' -Completed
