<#
.SYNOPSIS
    Adds multiple users from a file to a distribution group.
.DESCRIPTION
    Adds multiple users from either a text file or csv to a distribution group.
.NOTES
    Text files should normally be provided where each member to add is on a
    separate line. However, one line can be used if the members are separated
    by a semicolon ';' and it will automatically separate these.

    If entries have angle brackets, it will assume the content between the
    brackets is the email address. This occurrs for exmaple when copying names
    from Outlook.
.EXAMPLE
    . .\Bulk_Add_Users_To_Group.ps1 -File 'some_file.txt' -GroupEmail group@example.com
    Adds all of the members in 'some_file.txt' to the list 'group@example.com'.
#>

[CmdletBinding()]
param (
    [Parameter(
        Mandatory = $true
    )]
    [string[]]$File,

    [Parameter(
        Mandatory = $true
    )]
    [string]$GroupEmail
)

if (-not (Test-Path -Path $File)) {
    Write-Warning 'File not found'
    return
}

try {
    $FileInfo = Get-Item $File
}
catch {
    throw
}

switch ($FileInfo.Extension) {
    '.txt' {
        $Members = Get-Content -Path $File

        if ($Members.Count -eq 1 -and $Members -match ';') {
            $Members = $Members -split ';' | ForEach-Object { $_.Trim() }
        }
        break
    }
    '.csv' {
        $Members = Import-Csv -Path $File

        if (($Members | Get-Member -MemberType NoteProperty).Count -gt 1) {
            $Members[0] | Select-Object * | Out-Host
            Write-Host "Multiple columns, please enter the name of the column containing the email"
            do {
                $Column = Read-Host "Column"
                if ($Column -notin ($Members | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)) {
                    Write-Warning "$Column is not a valid colum"
                    $Column = $null
                }
            } until (
                $Column
            )
        }

        break
    }
    Default {
        Write-Warning "Extension ($_) is not supported"
        return
    }

}

. (Join-Path $PSScriptRoot 'Functions.ps1')

Connect-ToEXO

Write-Verbose "Searching Group"
$Group = Search-Group $GroupEmail

if ($Group -is [array]) {
    throw "Multiple groups found:`r$($Group | Select-Object Name)"
}

if ($null -eq $Group) {
    throw 'No group found.'
}

if ($Group.RecipientType -notin ('MailUniversalDistributionGroup', 'MailUniversalSecurityGroup')) {
    throw 'Group is not a distribution list.'
}

Write-Verbose "Starting loop"
foreach ($Member in $Members) {

    if ($Member -match '<(.+?)>') {
        $Email = $Matches[1]
    }
    else {
        $Email = $Member
    }

    try {
        Add-DistributionGroupMember -BypassSecurityGroupManagerCheck -Identity $Group.ExchangeObjectId -Member $Email -ErrorAction Stop
        Write-Host "Added $Email to group" -ForegroundColor Green
    }
    catch {
        Write-Warning $_
    }

}
