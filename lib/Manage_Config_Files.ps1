function Get-ConfigFile {

    [CmdletBinding()]
    param([string]$Path)

    $ConfigPath = Join-Path $Path 'config.json'
    $SchemaPath = Join-Path $Path 'config_schema.json'

    if (Test-Path $ConfigPath) {

        try {
            $Global:ADConfig = Get-Content $ConfigPath -ErrorAction Stop | ConvertFrom-Json
        }
        catch { throw }

    }
    else {
        New-ConfigFile
    }

}

function New-ConfigFile {

    [CmdletBinding()]
    param([string]$Path)

    $SchemaPath = Join-Path $Path 'config_schema.json'

    try {
        $Schema = Get-Content $SchemaPath -ErrorAction Stop | ConvertFrom-Json
    }
    catch { throw }



}

# (Get-DnsClient).ConnectionSpecificSuffix | Where-Object { $_ }