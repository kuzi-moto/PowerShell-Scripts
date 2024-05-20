# Takes a CSV file to remove licenses
param (
    [Parameter(Mandatory = $true, HelpMessage = "CSV Path")]
    [string]$Path
)

. $PSScriptRoot\Atlassian_Functions.ps1

$Data = Import-Csv $Path

$LicenseInformation = (Get-AtlassianAdminLicenses).products
$LicenseGroups = Get-AtlassianAdminProductUse | ForEach-Object {
    @{ $_.product.productId = $_.groups }
}

$Report = @()

for ($i = 0; $i -lt $Data.Count; $i++) {

    Write-Progress -Activity 'Removing licenses' -Status "#$i/$($Data.Count)" -PercentComplete (($i + 1) / $Data.Count * 100)

    if ($Data[$i].'Clear to Delete?' -ne 'X') {
        continue
    }

    $ProductName = $Data[$i].'Product Name'
    try {
        $User = Search-AtlassianUser $Data[$i].Email
    }
    catch { throw }

    if (!$User) {
        Write-Warning "Couldn't find $($Data[$i].Name)"
        continue
    }
    elseif ($User -is 'array') {
         Write-Warning "Found multiple accounts for $($Data[$i].Email)"
    }
    
    if ($LicenseInformation.productId -notcontains $ProductName) {
        $Product = $LicenseInformation | Where-Object { $_.productname -eq $ProductName }
    }
    else {
        $Product = $LicenseInformation | Where-Object { $_.productId -eq $ProductName }
    }

    if (!$Product) {
        Write-Warning "Couldn't find a Product for $($Data[$i].'Product Name')"
        continue
    }

    Write-Host "Removing $($Product.productName) from $($Data[$i].name)"

    try {
        $null = Revoke-AtlassianProductAccess $User.accountId $Product.productId -ErrorAction Stop
    }
    catch {

        if ((Get-Error).Exception.Message -eq 'HTTP 400 Bad Request: Group not modifiable') {

            $UserGroups = Get-AtlassianUserGroups $User.accountId

            [array]$RemoveGroup = $LicenseGroups.($Product.productId) | Where-Object { $_.id -in $UserGroups.groupId }

            if (!$RemoveGroup) {
                Write-Warning "didn't detect any group"
            }
            else {
                $RemoveGroup | ForEach-Object {
                    if ($_.managementAccess -eq 'READ_ONLY') {
                        $Report += @{
                            user = $Data[$i].ExternalDirectoryObjectId
                            group = $_.name
                            action = 'skipped'
                        }
                    }
                    else {
                        Remove-AtlassianGroupMember $User.accountId $_.id
                        $Report += @{
                            user = $Data[$i].ExternalDirectoryObjectId
                            group = $_.name
                            action = 'deleted'
                        }
                    }
                }
            }

        }
        elseif ($null = (Get-Error).Exception.Message -match 'product access cannot be revoked for user \S+ because they have roles: (\[.+?\])') {
            Write-Warning "Product access cannot be revoked for user $($Data[$i].Name) because they have roles: $($Matches[1]) `nRemove the roles to revoke access"
        }
        else { throw }

    }

}

Write-Progress -Activity 'Removing licenses' -Completed

$Report | ConvertTo-Csv | Out-File './report.csv' -Encoding utf8
