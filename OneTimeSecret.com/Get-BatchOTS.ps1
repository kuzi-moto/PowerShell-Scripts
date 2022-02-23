[CmdletBinding()]
param (
  # List of secrets to generate URLs for
  [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
  [string[]]$Secret,

  [string]$UserName,

  [string]$APIKey,

  # Save provided credentials so you don't have to enter it each time
  [switch]$SaveConfig = $false
)



function Get-OTS {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [string]$Secret
  )

  process {

    'https://onetimesecret.com/secret/' + (New-OTSSharedSecret -Secret $_).SecretKey

  }

}



$SecretList = $null
$ProcessedList = @()
$SecretFile = Join-Path -Path (Get-Location) -ChildPath 'secrets.csv'
$ConfigFile = Join-Path -Path $PSScriptRoot -ChildPath 'config.json'

if (Test-Path $ConfigFile) {
  try { $Config = Get-Content $ConfigFile -ErrorAction Stop | ConvertFrom-Json }
  catch {
    Write-Warning "Failed to read `"config.json`", exiting..."
    return
  }

  if ($Config) {
    $UserName = $Config.UserName
    $APIKey = $COnfig.APIKey
  }

}

if (!$UserName) { $UserName = Read-Host "Please supply your onetimesecret.com username" }
if (!$APIKey) { $APIKey = Read-Host "Please supply your onetimesecret.com API key" }

try { $null = Get-Module -Name OneTimeSecret -ErrorAction Stop }
catch {
  Write-Warning 'Please run "Install-Module -Name OneTimeSecret" to use this script, exiting...'
  return
}

try { $null = Get-OTSAuthorizationToken }
catch {
  try { $null = Set-OTSAuthorizationToken -Username $UserName -APIKey $APIKey <# -BaseUrl 'https://onetimesecret.com/' #> -ErrorAction Stop }
  catch {
    Write-Warning "Failed to get authorization token, exiting..."
    return
  }
}

# Determine if the input is a file, if so attempt to read
if ($Secret.Count -eq 1) {
  if ($Secret | Test-Path) {
    switch -regex ($Secret) {
      '\.txt$' { $SecretList = Get-Content $Secret; break }
      Default { Write-Warning "Detected a potential file, but script not configured to read from it." }
    }
  }
}

if (!$SecretList) { $SecretList = $Secret }

if ($SecretList.Count -eq 1) {
  $SecretList | Get-OTS
}
else {
  for ($i = 0; $i -lt $SecretList.Count; $i++) {
    Write-Progress -Activity "Querying onetimesecret.com" -Status ("Fetching secret {0}/{1}" -f ($i + 1), $SecretList.Count) -PercentComplete ($i / $SecretList.Count * 100)
    $ProcessedList += @{
      Link   = $SecretList[$i] | Get-OTS
      Secret = $SecretList[$i]
    }
  }

  $ProcessedList | `
    ForEach-Object { [PSCustomObject]$_ } | `
    Export-Csv -Path $SecretFile -NoTypeInformation

  Write-Host "Secret links saved to `"$SecretFile`""
}

if ($SaveConfig) {
  @{ APIKey = $APIKey; UserName = $UserName } | `
    ConvertTo-Json | `
    Out-File $ConfigFile
}