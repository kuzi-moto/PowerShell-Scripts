$done = $false
do {

    try {
        $SourceUser = Get-ADUser -Identity (Read-Host "User to replicate") -Properties MemberOf -ErrorAction Stop
        Write-Host "Found user $($SourceUser.Name)"
    }
    catch {
        Write-Host "User not found." -ForegroundColor Red
        continue
    }
    
    $Ans = $false
    do {
        switch -regex (Read-Host "Proceed? (y/n)") {
            'y|yes' { $Ans = $true; $done = $true; break }
            'n|no' { continue }
            Default { }
        }
    } until ($Ans)
} until ($done)

$done = $false
do {

    try {
        $DestUser = Get-ADUser -Identity (Read-Host "User to apply membership") -Properties MemberOf -ErrorAction Stop
        Write-Host "Found user $($DestUser.Name)"
    }
    catch {
        Write-Host "User not found." -ForegroundColor Red
        continue
    }
    
    $Ans = $false
    do {
        switch -regex (Read-Host "Proceed? (y/n)") {
            'y|yes' { $Ans = $true; $done = $true; break }
            'n|no' { $Ans = $true; break }
            Default { }
        }
    } until ($Ans)
} until ($done)

foreach ($group in $SourceUser.MemberOf) {
    $ADGroup = $group | Get-ADGroup
    $members = $ADGroup | Get-ADGroupMember -Recursive | Select-Object -ExpandProperty Name
    
    if ($members -contains $DestUser.Name) {
        Write-Host "Already in group: $($ADGroup.Name)"
    }
    else {
        $ADGroup | Add-ADGroupMember -Members $DestUser
        Write-Host "Added to group:   $($ADGroup.Name)"
    }
}