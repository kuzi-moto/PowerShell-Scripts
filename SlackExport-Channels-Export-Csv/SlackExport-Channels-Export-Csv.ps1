param (
  [switch]$IncludeArchived = $false,
  [switch]$OnlyChannelsWithGuests = $false,
  [switch]$Excel = $false
)

$ExcelPath = 'C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE'

# Goal: Create a document that lists all channels and their members, and integrations

$Users = Get-Content -Path '.\users.json' | ConvertFrom-Json
$channels = Get-Content -Path '.\channels.json' | ConvertFrom-Json
#$integrations_log = Get-Content -Path '.\integration_logs.json' | ConvertFrom-Json

$UserFromID = @{ }
$Users | ForEach-Object {
  $UserFromID.($_.id) = $_.profile.email
}

if ($OnlyChannelsWithGuests) {
  $Guests = $Users | Where-Object { $_.is_restricted } | ForEach-Object { $_.id }
}

$Select = @(
  'id'
  'name'
  @{Name = "creator"; Expression = { $UserFromID.($_.creator) } }
  @{Name = "members"; Expression = { ($_.members | Where-Object { $Guests -notcontains $_ } | ForEach-Object { $UserFromID.($_) }) -join ';' } }
  @{Name = "guests"; Expression = { ($_.members | Where-Object { $Guests -contains $_ } | ForEach-Object { $UserFromID.($_) }) -join ';' } }
  'is_general'
  @{Name = "topic"; Expression = { $_.topic.Value } }
  @{Name = "purpose"; Expression = { $_.purpose.value } }
)

if ($IncludeArchived) { $Select += 'is_archived' }

$SelectedChannels = @()

for ($i = 0; $i -lt $channels.Count; $i++) {
  if (!$IncludeArchived -and $channels[$i].is_archived) { continue }
  if ($OnlyChannelsWithGuests -and !(Compare-Object -ReferenceObject $channels[$i].members -DifferenceObject $Guests -IncludeEqual -ExcludeDifferent )) { continue }

  $SelectedChannels += $channels[$i]
}

$SelectedChannels | Select-Object $Select | Export-Csv -Path '.\channels.csv' -NoTypeInformation

if ($Excel) { & $ExcelPath '.\channels.csv' }