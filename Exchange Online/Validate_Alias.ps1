<#
.SYNOPSIS
    Validates an email alias exists.
.DESCRIPTION
    A longer description of the function, its purpose, common use cases, etc.
.NOTES
    Information or caveats about the function e.g. 'This function is not supported in Linux'
.LINK
    Specify a URI to a help page, this will show when Get-Help -Online is used.
.EXAMPLE
    Test-MyTestFunction -Verbose
    Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
#>

[CmdletBinding()]
param (
    [string]$Path,
    [string]$IsValidColumn = "IsValid"
)


#--------------[ Includes ]--------------


$Lib = Join-Path (Get-Item -Path $PSScriptRoot).Parent.FullName 'lib'

. (Join-Path $Lib 'CSV_Functions.ps1')
. (Join-Path $PSScriptRoot 'Functions.ps1')


#-----------[ Main Execution ]-----------


Connect-ToEXO

$File = Import-FromCSV $Path

$File | Get-Member | Where-Object { $_.MemberType -eq "NoteProperty" } | Select-Object Name | Out-Host

do {
    $SourceColumn = Read-Host "Enter name of column which contains user alias"
    if (($File | Get-Member).Name -notcontains $SourceColumn) {
        Write-Warning "$SourceColumn doesn't exist, try again" -ForegroundColor Red
        $SourceColumn = ""
    }
} until ($SourceColumn)

for ($i = 0; $i -lt $File.Count; $i++) {

    if ($File[$i].$IsValidColumn -ne '' -and ($File[$i] | Get-Member).Name -contains $IsValidColumn) {
        continue
    }

    Write-Progress -Activity "Searching alias" -Status "Progress: $($i+1)/$($File.Count)" -PercentComplete (($i + 1) / $File.Count * 100)

    $User = Search-Alias $File[$i].$SourceColumn

    if ($User) {
        $IsValid = "TRUE"
    }
    else {
        $IsValid = "FALSE"
    }

    $File[$i] | Add-Member -NotePropertyName $IsValidColumn -NotePropertyValue $IsValid -Force

}

Export-CsvToFile $File $Path