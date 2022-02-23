[CmdletBinding()]
param (
    [string]$Path,
    [string]$DestinationColumn = "AccountEnabled"
)

try {
    $File = Import-Csv -Path $Path -ErrorAction Stop
}
catch {
    Write-Host "ERROR: Could not read file $Path" -ForegroundColor Red
    Write-Host "$_" -ForegroundColor Red
    return
}

Connect-AzureAD

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

    Write-Progress -Activity "Getting user status" -Status "Progress: $i/$($File.Count)" -PercentComplete ($i/$File.Count*100)

    $User = Get-AzureADUser -ObjectId $File[$i].$SourceColumn -ErrorAction SilentlyContinue

    if ($User) {
        $AccountStatus = $User.AccountEnabled
    }
    else {
        $AccountStatus = "ERROR"
    }

    $File[$i] | Add-Member -NotePropertyName $DestinationColumn -NotePropertyValue $AccountStatus -Force

}

try {
    $File | Export-Csv -Path $Path -NoTypeInformation -ErrorAction Stop
}
catch {
    Write-Host "Error writing file to $Path" -ForegroundColor Red
    Write-Host "$_" -ForegroundColor Red
}