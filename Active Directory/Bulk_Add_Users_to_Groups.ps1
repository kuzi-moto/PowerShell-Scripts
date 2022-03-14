[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Path to the list of users")]
    [string]$Path
)

$UPNColumn = $null

try {
    $File = Get-Item $Path -ErrorAction SilentlyContinue
}
catch {
    Write-Host "ERROR: $($Error[0].Exception.Message)" -ForegroundColor Red
    return
}

if ($File.Extension -eq '.csv') {

    try {
        $csv = Import-Csv -Path $File.FullName -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "ERROR: $($Error[0].Exception.Message)" -ForegroundColor Red
        return
    }

    $csv[0] | Select-Object * | Out-Host

    do {

        $UserInput = Read-Host 'Enter column containing UPN'
    
        if (($csv | Get-Member -MemberType NoteProperty).Name -contains $UserInput) {
            $UPNColumn = $UserInput
        }
        else {
            Write-Host "$UserInput - Not a valid column, try again" -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    
    } until ($UPNColumn)

    $UserList = $csv.$UPNColumn

}
elseif ($File.Extension -eq '.txt') {

    try {
        $UserList = Get-Content -Path $Path -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "ERROR: $($Error[0].Exception.Message)" -ForegroundColor Red
        return
    }

}
else {
    Write-Host "ERROR: '$($File.Extension)' is not a supported type. TXT or CSV" -ForegroundColor Red
    return
}

do {
    
    $GroupName = Read-Host "Enter the name of a group to add users"

    if ($GroupName -eq '') {
        Write-Host  'Need to enter something' -ForegroundColor Yellow
    }
    else {
        Write-Host "Searching groups..."
        try {
            $GroupList = Get-ADGroup -Filter "Name -like '*$GroupName*'" -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "ERROR: $($Error[0].Exception.Message)" -ForegroundColor Red
        }
    }

    if ($GroupList.GetType().name -eq "Object[]") {

        for ($i = 1; $i -le $GroupList.Count; $i++) {
            $GroupList[$i - 1] | Add-Member -NotePropertyName "Option" -NotePropertyValue $i -Force
        }

        do {

            Write-Host "Found the following groups:"
            $GroupList | Select-Object Option, Name, SamAccountName, GroupCategory, ObjectClass | Format-Table -AutoSize | Out-Host
            
            $Option = Read-Host "Select a group - 0 to cancel"
            if ($Option -notmatch '^-?\d+$') {
                Write-Host "Must be a number" -ForegroundColor Red
            }
            elseif ($GroupList.Option -notcontains $Option -and $Option -ne 0) {
                Write-Host "Must enter one of the listed options" -ForegroundColor Red
            }
            else {
                $Group = ($GroupList | Where-Object { $_.Option -eq $Option })
            }

        } until ($Group -or $Option -eq 0)

    }
    elseif ($GroupList.GetType().Name -eq "ADGroup") {

        Write-Host "Found this group:"
        $GroupList | Select-Object Option, Name, SamAccountName, GroupCategory, ObjectClass | Format-Table -AutoSize | Out-Host
    
        $Done = $false
        do {
            switch -regex (Read-Host "Continue with this group? [Y]es/[N]o") {
                '^y$|^yes$' { $Group = $GroupList; $Done = $true; break }
                '^n$|^no$' { $Done = $true; break }
                Default { Write-Host "Not a valid answer. 'Y' or 'N' only" }
            }
        } until ($Done)


    
    }
    elseif ($GroupName -eq '') {}
    else { Write-Host "Not sure what happened but couldn't find a group. Try again" -ForegroundColor Red }

} until ($Group)

$GroupMembers = $Group | Get-ADGroupMember | Get-ADUser

for ($i = 0; $i -lt $UserList.Count; $i++) {

    Write-Progress -Activity "Adding users to $($Group.Name)" -Status "Progress: $i/$($UserList.Count)" -PercentComplete ($i / $UserList.Count * 100)

    if ($GroupMembers.UserPrincipalName -contains $UserList[$i]) {
        Write-Host "$($UserList[$i]) - Already a member"
    }
    else {
        $Group | Add-ADGroupMember -Members $UserList[$i]
        Write-Host "$($UserList[$i]) - Added to group" -ForegroundColor Green
    }

}