<#
.SYNOPSIS
    Fetches the Azure AD Object ID from a list of aliases
.DESCRIPTION
    Long description
.EXAMPLE
    PS C:\> <example usage>
    Explanation of what the example does
.INPUTS
    Inputs (if any)
.OUTPUTS
    Output (if any)
.NOTES
    General notes
#>

[CmdletBinding()]
param (
    [string]$Path,
    [string]$DestinationColumn = "ObjectID"
)

try {
    $File = Import-Csv $Path -ErrorAction Stop
}
catch {
    Write-Host "ERROR: Could not import CSV" -ForegroundColor Red
    Write-Host "$_" -ForegroundColor Red
}

Connect-ExchangeOnline

$File | Get-Member | Where-Object { $_.MemberType -eq "NoteProperty" } | Select-Object Name | Out-Host

do {
    $SourceColumn = Read-Host "Enter name of the column to read from"
    if (($File | Get-Member).Name -notcontains $SourceColumn) {
        Write-Host "Error: $SourceColumn doesn't exist, try again" -ForegroundColor Red
        $SourceColumn = ""
    }
} until ($SourceColumn)

for ($i = 0; $i -lt $File.Count; $i++) {

    if ($File[$i].$DestinationColumn) {
        continue
    }

    Write-Progress -Activity "Getting user ObjectID's" -Status "Progress: $i/$($File.Count)" -PercentComplete ($i/$File.Count*100)

    $User = Get-EXORecipient $File[$i].$SourceColumn -ErrorAction SilentlyContinue

    if ($User.count -gt 1) {
        Write-Host "Error: Multiple users found" -ForegroundColor Yellow
        $NewValue = "ERROR"
    }
    elseif ($User) {
        $NewValue = $User.ExternalDirectoryObjectId
    }
    else {
        $NewValue = "ERROR"
    }

    $File[$i] | Add-Member -NotePropertyName $DestinationColumn -NotePropertyValue $NewValue -Force
}

try {
    $File | Export-Csv -Path $Path -NoTypeInformation -ErrorAction Stop
}
catch {
    Write-Host "Error writing file to $Path" -ForegroundColor Red
    Write-Host "$_" -ForegroundColor Red
}


<# 
for ($i = 0; $i -lt $File.Count; $i++) {
    if (!$File[$i].$DestinationColumn) {
        continue
    }

    $Result = $File | Where-Object { $_.ObjectID -eq $File[$i].$DestinationColumn}

    if ($Result.Count -gt 1) {
        foreach ($item in $Result) {
            $File[[array]::IndexOf($File,$item)].ObjectID = ""
        }
    }
}
 #>