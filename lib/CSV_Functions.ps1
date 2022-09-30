function Import-FromCSV {

    param (
        [string]$Path
    )

    try {
        $Item = Get-Item -Path $Path -ErrorAction Stop
    }
    catch {
        throw
    }

    try {
        $File = Import-Csv $Item.FullName -ErrorAction Stop
    }
    catch {
        throw
    }

    return $File
}

function Export-CsvToFile {

    param (
        $File,
        [string]$Path
    )

    try {
        $File | Export-Csv -Path $Path -NoTypeInformation -ErrorAction Stop
    }
    catch {
        throw
    }

    Write-Host "Saved $Path"

}