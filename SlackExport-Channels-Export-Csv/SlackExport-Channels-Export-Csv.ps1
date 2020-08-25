param (
  # Path to Slack export
  [Parameter(Mandatory = $true)]
  [string]$Path,

  [switch]$Excel = $false
)

$ExcelPath = 'C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE'
$Users = Get-Content -Path (Join-Path $Path  'users.json') | ConvertFrom-Json
$channels = Get-Content -Path (Join-Path $Path 'channels.json') | ConvertFrom-Json

if ($PSScriptRoot) { $OutPath = Join-Path $PSScriptRoot 'channels.csv' }
else { $OutPath = Join-Path (Get-Location).Path 'channels.csv' }

$UserFromID = @{ }
$Users | ForEach-Object {
  $UserFromID.($_.id) = $_.profile.email
}

$Guests = $Users | Where-Object { $_.is_restricted } | ForEach-Object { $_.id }

$Select = @(
  'id'
  'name'
  @{Name = "creator"; Expression = { $UserFromID.($_.creator) } }
  @{Name = "members"; Expression = { ($_.members | Where-Object { $Guests -notcontains $_ } | ForEach-Object { $UserFromID.($_) }) -join ';' } }
  @{Name = "guests"; Expression = { ($_.members | Where-Object { $Guests -contains $_ } | ForEach-Object { $UserFromID.($_) }) -join ';' } }
  'is_general'
  'is_archived'
  @{Name = "topic"; Expression = { $_.topic.Value } }
  @{Name = "purpose"; Expression = { $_.purpose.value } }
)

$channels | Select-Object $Select | Export-Csv -Path $OutPath -NoTypeInformation -Force

if ($Excel) { & $ExcelPath $OutPath }