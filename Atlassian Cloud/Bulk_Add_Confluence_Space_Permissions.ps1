[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    $Object,

    [Parameter(Mandatory = $true)]
    [string]$GroupId
)
<# 
if ($Object.GetType().Name -in @('Hashtable','OrderedHashtable')) {
    if ($Object.ContainsKey('Confluence Spaces')) {
        # Whole $Report object provided.
    }
    elseif ($Object.ContainsKey('Key') {
        # Single Space provided, $Report.'Confluence Spaces'[$i]
    }
}
elseif ($Object.GetType().Name -eq 'PSCustomObject') {
    # Report was converted to JSON and back.
    if ($Object | Get-Member -MemberType NoteProperty)
}
elseif ($Object.GetType().Name -eq 'Object[]') {
    # $Report.'Confluence Spaces' object provided
}
#>

$Spaces = $Object.'Confluence Spaces'
$Params = @{
    GroupId = $GroupId
}

for ($i = 540; $i -lt $Spaces.Count; $i++) {

    Write-Progress -Id 0 -Activity "Space" -Status "$($i+1)/$($Spaces.Count)" -PercentComplete (($i+1)/$Spaces.count*100)

    $Params.SpaceKey = $Spaces[$i].Key

    # Must do this permission before any others.
    if ($Spaces[$i].Permissions | Where-Object {$_.operation.operation -eq 'read' -and $_.operation.targetType -eq 'space'}) {
        $Params.Operation = 'read'
        $Params.Target = 'space'
        $null = Add-ConfluenceSpacePermission @Params
    }

    $Permissions = $Spaces[$i].Permissions | Where-Object {$_.operation.operation -ne 'read' -and $_.operation.targetType -ne 'space'}

    for ($ii = 0; $ii -lt $Permissions.Count; $ii++) {
        Write-Progress -Id 1 -ParentId 0 "Permission" -Status "$($ii+1)/$($Permissions.Count)" -PercentComplete (($ii+1)/$Permissions.count*100)
        $Params.Operation = $Permissions[$ii].operation.operation
        $Params.Target = $Permissions[$ii].operation.targetType
        $null = Add-ConfluenceSpacePermission @Params
    }

    Write-Progress -Id 0 -ParentId 1 -Activity "Permissions" -Completed

}

Write-Progress -Id 0 -Activity "Space" -Completed
