param (
  [switch]$IncludeDeleted = $false,
  [switch]$IncludeBots = $false,
  [switch]$IncludeAppUsers = $false,
  [switch]$IncludeGuests = $false,
  [switch]$ExcludeRemovedChannels = $false,
  [switch]$Excel = $false
)

function Get-Channels {
  param ( $user )

  $ChannelList = @()

  $ChannelList += ($Channels | Where-Object { $_.members -contains $user.id }).name | Where-Object { $_.Length -gt 1 } | Where-Object { $RemovedChannels -notcontains $_ }

  if ($user.is_ultra_restricted -and !$ChannelList) {
    switch -regex ($user.profile.email) {
      '@xngage\.com' { $ChannelList += 'prm-xngage'; break }
      '@nishtechinc\.com' { $ChannelList += 'prm-nishtech'; break }
      '@perficient\.com' { $ChannelList += 'prm-perficient'; break }
      '@absolunet\.(com|ca)' { $ChannelList += 'prm-absolunet'; break }
      '@xcentium\.com' { $ChannelList += 'prm-xcentium'; break }
      '@verndale\.com' { $ChannelList += 'prm-verndale'; break }
      '@adapty\.com' { $ChannelList += 'prm-adapty'; break }
      '@solutionists\.(co\.nz|au)' { break }
      '@nbf\.com' { break }
      '@fivemill\.com' { break }
      '@konnectedinteractive\.com' { break }
      Default { }
    }
  }

  return $ChannelList
}

function Get-RemovedChannels {
  param ( $user )

  $ChannelList = @()

  $ChannelList += ($Channels | Where-Object { $_.members -contains $user.id }).name | Where-Object { $_.Length -gt 1 -and $RemovedChannels -contains $_ }

  if ($user.is_ultra_restricted -and !$ChannelList) {
    switch -regex ($user.profile.email) {
      '@xngage\.com' { $ChannelList += 'prm-xngage'; break }
      '@nishtechinc\.com' { $ChannelList += 'prm-nishtech'; break }
      '@perficient\.com' { $ChannelList += 'prm-perficient'; break }
      '@absolunet\.(com|ca)' { $ChannelList += 'prm-absolunet'; break }
      '@xcentium\.com' { $ChannelList += 'prm-xcentium'; break }
      '@verndale\.com' { $ChannelList += 'prm-verndale'; break }
      '@adapty\.com' { $ChannelList += 'prm-adapty'; break }
      '@solutionists\.(co\.nz|au)' { break }
      '@nbf\.com' { break }
      '@fivemill\.com' { break }
      '@konnectedinteractive\.com' { break }
      Default { }
    }
  }

  return $ChannelList
}

$Users = Get-Content -Path '.\users.json' | ConvertFrom-Json
$Channels = Get-Content -Path '.\channels.json' | ConvertFrom-Json
$RemovedChannels = Get-Content -Path '.\channels_to_remove.csv'
$ExcelPath = 'C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE'

$UserChannels = @{}

$Users | ForEach-Object { $UserChannels.($_.profile.email) = Get-Channels -user $_ }

$Select = @(
  @{Name = "display_name"; expression = { $_.profile.display_name_normalized } }
  @{Name = "real_name"; expression = { $_.profile.real_name_normalized } }
  @{Name = "email"; expression = { $_.profile.email } }
  'is_admin'
  'is_owner'
  'is_primary_owner'
  @{Name = "channels"; expression = { $UserChannels.($_.profile.email) -join '; ' } }
  @{Name = "# channels"; expression = { $UserChannels.($_.profile.email).count } }
  @{Name = "Removed Channels"; expression = { Get-RemovedChannels -user $_ } }
)

if ($IncludeDeleted) { $Select += 'deleted' }
if ($IncludeBots) { $Select += 'is_bot' }
if ($IncludeAppUsers) { $Select += 'is_app_user' }
if ($IncludeGuests) { $Select += 'is_restricted', 'is_ultra_restricted' }

$SelectedUsers = @()

for ($i = 0; $i -lt $Users.Count; $i++) {
  if (!$IncludeDeleted -and $Users[$i].deleted) { continue }
  if (!$IncludeBots -and $Users[$i].is_bot) { continue }
  if (!$IncludeAppUsers -and $Users[$i].is_app_user) { continue }
  if (!$IncludeGuests -and $Users[$i].is_restricted) { continue }

  $SelectedUsers += $Users[$i]
}

$SelectedUsers | Select-Object $Select | Sort-Object email | Export-Csv -Path ".\users.csv" -NoTypeInformation

if ($Excel) { & $ExcelPath '.\users.csv' }