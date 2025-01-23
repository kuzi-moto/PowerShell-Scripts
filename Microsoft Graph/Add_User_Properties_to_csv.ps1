[CmdletBinding()]
param (
    [string]$Path,
    [string[]]$Property,
    [switch]$Update
)

try {
    $File = Import-Csv -Path $Path -ErrorAction Stop
}
catch {
    Write-Host "ERROR: Could not read file $Path" -ForegroundColor Red
    Write-Host "$_" -ForegroundColor Red
    return
}

if (-not (Get-MgContext)) {
    try {
        $null = Connect-MgGraph User.Read.All -ErrorAction Stop
    }
    catch {
        throw
    }
}

$File[0] | Select-Object * | Out-Host

do {
    $SourceColumn = Read-Host 'Enter name of the column to read from'
    if (($File | Get-Member).Name -notcontains $SourceColumn) {
        Write-Host "Error: $SourceColumn doesn't exist, try again" -ForegroundColor Red
        $SourceColumn = ''
    }
} until ($SourceColumn)

$AvailableAttributes = @(
    'UserPrincipalName'
    'ProxyAddresses'
    'Mail'
    'EmployeeId'
    'DisplayName'
)

$AvailableAttributes | Out-Host

do {
    $MatchingAttribute = Read-Host "Enter name of directory attribute to match to $SourceColumn"
    if ($MatchingAttribute -notin $AvailableAttributes) {
        Write-Warning "$MatchingAttribute not valid, try again"
        $MatchingAttribute = ''
    }    
} until ($MatchingAttribute)

if (-not $PSBoundParameters.ContainsKey('Property')) {

    $Property = @(
        'JobTitle'
        'Department'
        'OfficeLocation'
    )
    Write-Host "Did not specify any properties. Using the following as defaults: $($Property -join ', ')"

}

$SelectedProperties = @($MatchingAttribute;$Property) | Select-Object -Unique

Write-Progress -Activity "Getting users"
[array]$GraphUsers = Get-MgUser -All -Property $SelectedProperties
Write-Progress -Activity "Getting users" -Completed

if ($GraphUsers.Count -eq 0) {
    Write-Warning "Couldn't find any graph users, exiting..."
    return
}

$ValidatedProperties = $Property | ForEach-Object {

    if ($_ -notin ($GraphUsers | Get-Member -MemberType Property | Select-Object -ExpandProperty Name)) {
        Write-Warning "Provided property '$_' is not valid and will be ignored."
    } 
    else {
        $_
    }

}

if ($ValidatedProperties.Count -eq 0) {
    Write-Warning "No valid properties to match, exiting..."
    return
}

for ($i = 0; $i -lt $File.Count; $i++) {

    Write-Progress -Activity 'Setting users' -Status "#$($i+1)/$($File.Count)" -PercentComplete (($i + 1) / $File.Count * 100)

    if ($MatchingAttribute -eq 'ProxyAddresses') {
        [array]$User = $GraphUsers | Where-Object { $_.$MatchingAttribute -contains "smtp:$($File[$i].$SourceColumn)" }
    }
    else {
        [array]$User = $GraphUsers | Where-Object { $_.$MatchingAttribute -eq $File[$i].$SourceColumn }
    }

    $ValidatedProperties | ForEach-Object {

        if ($null -ne $File[$i].$_ -and $File[$i].$_ -ne '' -and !$PSBoundParameters.ContainsKey('Update')) {
            Write-Host 'skipping'
            continue
        }

        if ($User.Count -eq 1) {
            $Value = if ($null -eq $User.$_) { '<EMPTY>' } else { $User.$_ }
        }
        elseif ($User.Count -gt 1) {
            #Write-Warning "Multiple matches found for `"$($File[$i].$SourceColumn)`""
            $Value = 'ERROR - MultipleMatch'
        }
        else {
            #Write-Warning "No matches found for `"$($File[$i].$SourceColumn)`""
            $Value = 'ERROR - NoMatch'
        }

        $File[$i] | Add-Member -NotePropertyName $_ -NotePropertyValue $Value -Force

    }

}
Write-Progress -Activity 'Setting users' -Completed

try {
    $File | Export-Csv -Path $Path -NoTypeInformation -ErrorAction Stop
    Write-Host "Saved updates to file: $Path"
}
catch {
    Write-Host "Error writing file to $Path" -ForegroundColor Red
    Write-Host "$_" -ForegroundColor Red
}
