<#
.SYNOPSIS
  Imports Slack conversation history from an export archive, to Microsoft Teams Channels

.DESCRIPTION
  Using a .csv file, this script will go through all Slack messages from an Slack export into a corresponding
  Microsoft Teams channel. The script runs through all the messages for each specified channel twice. The first
  time downloading all the images, and the second to post the messages to Teams using the Graph API.

.EXAMPLE
  PS C:\> Slack-Export-to-Teams.ps1 -ArchiveDir .\SLACK_EXPORT_DIR
  Runs this script using the config.json and data.csv file in the current directory.

.INPUTS
  None, does not allow for piping objects to Slack-Export-to-Teams.ps1.

.OUTPUTS
  System.string. Slack-Exort-to-Teams.ps1 returns a string with a success or error message.

.NOTES
  Before using this script, be sure to fill out the config.json, and data.csv files. config.json should have the
  client id of your Azure application, and your Office 365 tenant id. The data.csv file should have the Slack
  Channel, Teams team, and Teams channel that the data will be migrated to. The user authenticating with the script
  should be a member of all the Teams/Channels that will be migrated to.
#>


[CmdletBinding()]
param (
  [Parameter(Mandatory = $true)]
  [ValidateScript( { Test-Path -Path $_ })]
  [String]$SlackExportPath,

  [String]$ConfigurationPath,

  [String]$DataPath,

  # Sets the maximum message length since the Slack max is higher than Teams
  [int]$MessageTrimLength = 25000,

  # In case of failure, try to resume from the last sent message
  [switch]$Resume
)


<# -----------------------------------------------------------------------------
                              Function Definitions
----------------------------------------------------------------------------- #>


function Invoke-GraphRequest {
  param (
    [Parameter(Mandatory = $true)]
    [String]$Query,
    [System.Collections.Hashtable]$QueryStringData,
    [String]$Body,
    [ValidateSet("Get", "Post", "Patch")]
    [string]$Method = "Get",
    [switch]$FullUrl
  )

  function Update-Token {
    # Utilizes global $Token variable

    $Params = @{
      ClientID    = $ClientId
      TenantID    = $TenantID
      RedirectUri = 'http://localhost'
    }

    Write-Progress "Updating access token"

    try { $Token = Get-MsalToken @Params -Silent -ErrorAction Stop }
    catch {
      Write-Host ""
      Write-Host "Please login. If you don't see the login pop-up, it may be hidden behind the terminal window." -ForegroundColor Yellow
      try { $Token = Get-MsalToken @Params -Interactive }
      catch { throw }
    }
  }

  if (!$Token) { Update-Token }

  if ($Query -match '(?:v1\.0|beta)\/(.*)' -and !$FullUrl) {
    Write-Error "`"-Query`" parameter should not use full URL. Try again using just `"$($Matches[1])`""
    return
  }

  # When the $Body gets converted to JSON, some characters don't get encoded properly causing pain and suffering.
  if ($Body) {
    foreach ($i in ($UnicodeChars | Sort-Object -Unique)) {
      $Body = $Body -replace [char]$i, ('\u{0:x4}' -f $i)
    }
  }

  # These queries will be assigned to the 'beta' endpiont instead of 'v1.0'
  $BetaRegex = @(
    [regex]::new('^teams\/.*?\/channels\/.*?\/messages$')
    [regex]::new('^teams\/.*?\/channels\/.*?\/messages\/.*?\/replies$')
  )

  if (($BetaRegex.Match($Query)).Success -contains $true) { $Endpoint = 'beta' }
  else { $Endpoint = 'v1.0' }

  if ($FullUrl) {
    $URL = $Query
  }
  elseif ($QueryStringData) {
    $URL = "https://graph.microsoft.com/$Endpoint/$Query", (Get-EncodedQueryString $QueryStringData) -join '?'
  }
  else { $URL = "https://graph.microsoft.com/$Endpoint/$Query" }

  $AccessToken = $Token.AccessToken

  for ($i = 0; $i -lt 5; $i++) {
    try {
      if ($Method -eq "Get") {
        return Invoke-RestMethod -Method $Method -Headers @{Authorization = "Bearer $AccessToken" } -Uri $URL
      }
      else {
        return Invoke-RestMethod -Method $Method -Headers @{Authorization = "Bearer $AccessToken" } -Uri $URL -Body $Body -ContentType "application/json"
      }
    }
    catch {
      $Response = ($_.ErrorDetails.Message | ConvertFrom-Json).error
      switch ($Response.code) {
        'Unauthorized' {
          if ($AccessToken) { Write-Warning "Unauthorized - updating access token" }
          Update-Token
          break
        }
        'InvalidAuthenticationToken' {
          Write-Warning "Invalid authentication token - $($Response.message)"
          Update-Token
          break
        }
        'AuthenticationError' {
          Write-Warning "Authentication error - $($Response.message)"
          Update-Token
          break
        }
        'ErrorAccessDenied' {
          throw "Access denied - may not have correct permissions to use this query"
        }
        'Forbidden' {
          throw "Forbidden - you do not have access to the requested item"
        }
        'BadRequest' {
          Write-Warning "Bad request - $($Response.message) - $URL"
          Write-Host "--------------------`n"
          Write-Host "Body: $Body"
          Write-Host "`n--------------------"
          throw
        }
        Default {
          Write-Warning "Other error: $($Response.code) - $($Response.message) - $URL"
        }
      }
    }

    Write-Host "`nWating 3 seconds and trying again..."
    Start-Sleep -Seconds 3
  }

  throw 'Invoke-GraphRequest failed to run the query after 5 attempts.'
}


function Get-JoinedTeams {
  $Response = Invoke-GraphRequest -Query 'me/joinedTeams'
  $Response.Value
}


function Get-TeamChannels {
  param (
    [Parameter(Mandatory = $true)]
    [String]$TeamID
  )

  $Params = @{
    Query           = "teams/$TeamID/channels"
    QueryStringData = @{ select = 'id,displayName' }
  }

  $Response = Invoke-GraphRequest @Params
  $Response.Value
}


function Get-TeamsChannelFilesLocation {
  # Get the metadata for the location where the files of a channel are stored.
  param (
    [Parameter(Mandatory = $true)]
    [String]$TeamID,
    [Parameter(Mandatory = $true)]
    [String]$ChannelID
  )

  try {
    $Params = @{
      Query           = "teams/$TeamID/channels/$ChannelID/filesFolder"
      QueryStringData = @{ select = 'parentReference,id' }
    }

    Invoke-GraphRequest @Params
  }
  catch { throw }

}


function Get-TeamsChannelFolders {
  # Get the folders for the channel
  param (
    [Parameter(Mandatory = $true)]
    [String]$DriveID,
    [Parameter(Mandatory = $true)]
    [String]$ItemID
  )

  try {
    $Params = @{
      Query           = "drives/$DriveID/items/$ItemID/children"
      QueryStringData = @{ select = 'id,name' }
    }

    Invoke-GraphRequest @Params
  }
  catch { throw }

}


function Get-TeamsChannelFolderItems {
  param (
    [Parameter(Mandatory = $true)]
    [String]$DriveID,
    [Parameter(Mandatory = $true)]
    [String]$ItemID
  )

  $Params = @{
    Query           = "drives/$DriveID/items/$ItemID/children"
    QueryStringData = @{
      select = 'eTag,name,webUrl'
      top    = 999
    }
  }
  $Select = @(
    'name'
    @{
      # For some reason office documents get junk appended to the url, so it needs to be stripped off otherwise
      # Graph freaks out when trying to attach the file to a message.
      Label      = 'webUrl'
      Expression = { $_.webUrl -replace '&action=.*', '' }
    }
    @{
      Label      = 'guid'
      Expression = {
        $_.eTag | Select-String -Pattern '{(.*?)}' | ForEach-Object { $_.matches.Groups[1].value }
      }
    }
  )
  $Files = @()

  do {

    try { $Response = Invoke-GraphRequest @Params }
    catch { throw }

    $Files += $Response.value | Select-Object $Select

    if ($Response.'@odata.nextLink') {
      $Params.Query = $Response.'@odata.nextLink'
      $Params.FullUrl = $true
    }

  } until (!$Response.'@odata.nextLink')

  return $Files
}


function Get-RootMessages {
  param (
    [Parameter(Mandatory = $true)]
    [String]$TeamID,
    [Parameter(Mandatory = $true)]
    [String]$ChannelID
  )

  Invoke-GraphRequest -Query "teams/$TeamID/channels/$ChannelID/messages"
}


function New-RootMessage {
  param (
    [Parameter(Mandatory = $true)]
    [String]$TeamID,
    [Parameter(Mandatory = $true)]
    [String]$ChannelID,
    [Parameter(Mandatory = $true)]
    [String]$Message,
    [String]$Subject
  )

  $Params = @{
    Query  = "teams/$TeamID/channels/$ChannelID/messages"
    Body   = @{
      subject = $Subject
      body    = @{
        contentType = "html"
        content     = $Message
      }
    } | ConvertTo-Json -Depth 10
    Method = 'Post'
  }

  (Invoke-GraphRequest @Params).id
}


function Get-ReplyMessages {
  param (
    [Parameter(Mandatory = $true)]
    [String]$TeamID,
    [Parameter(Mandatory = $true)]
    [String]$ChannelID,
    [Parameter(Mandatory = $true)]
    [String]$RootMessageID
  )

  Invoke-GraphRequest -Query "teams/$TeamID/channels/$ChannelID/messages/$RootMessageID/replies"
}


function New-ReplyMessage {
  param (
    [Parameter(Mandatory = $true)]
    [String]$TeamID,
    [Parameter(Mandatory = $true)]
    [String]$ChannelID,
    [Parameter(Mandatory = $true)]
    [String]$RootMessageID,
    [Parameter(Mandatory = $true)]
    [String]$Message,
    [array]$Attachments
  )

  $Params = @{
    Query  = "teams/$TeamID/channels/$ChannelID/messages/$RootMessageID/replies"
    Method = 'Post'
    Body   = @{
      body = @{
        contentType = "html"
        content     = $Message
      }
    }
  }

  if ($Attachments) {
    [array]$Params.Body.attachments += $Attachments
  }

  $Params.Body = $Params.Body | ConvertTo-Json -Depth 10

  $null = Invoke-GraphRequest @Params
}


function Get-EncodedQueryString {
  # Stolen from https://riptutorial.com/powershell/example/24404/encode-query-string-with---uri---escapedatastring---
  param (
    [Parameter(Mandatory = $true)]
    [System.Collections.Hashtable]$Parameters
  )

  [System.Collections.ArrayList]$ParametersArray = @()
  foreach ($Parameter in $Parameters.GetEnumerator()) {
    $Key = [uri]::EscapeDataString($Parameter.Name)
    $value = [uri]::EscapeDataString($Parameter.Value)
    $ParametersArray.Add("`$${Key}=${Value}") | Out-Null
  }

  $ParametersArray -join '&'
}


function Format-FileName {
  Param(
    [string]$Name,
    [string]$Mode
  )

  $NewName = $Name -replace '[<>:"\/\\\|\?\*]', '-'

  if ($NewName -notmatch '\.[a-z0-9]+$') {
    # Add an extension if it's missing

    switch ($Mode) {
      'snippet' { return $NewName + '.txt' }
      'email' { return $NewName + '.html' }
      Default { return $NewName }
    }
  }
  else {
    return $NewName
  }
}


<# -----------------------------------------------------------------------------
                                     Tests
----------------------------------------------------------------------------- #>


try { Import-Module MSAL.PS -ErrorAction Stop }
catch { throw 'Missing the MSAL.PS module. Try running "Install-Module -Name MSAL.PS" first.' }

if (-not (Test-Path (Join-Path $SlackExportPath 'channels.json'))) {
  throw "Failed to find the `"channels.json`" file in `"$SlackExportPath`"."
}

if (-not (Test-Path (Join-Path $SlackExportPath 'users.json'))) {
  throw "Failed to find the `"users.json`" file in `"$SlackExportPath`"."
}


<# -----------------------------------------------------------------------------
                                 Set Variables
----------------------------------------------------------------------------- #>


$Epoch = Get-Date 01.01.1970
$WebClient = New-Object System.Net.WebClient
$SaveCheckPoint = $false
$AllowedSubtypes = 'file_comment', 'me_message', 'thread_broadcast'

if (!$ConfigurationPath) {
  if ($PSScriptRoot) {
    $ConfigurationPath = Join-Path $PSScriptRoot 'config.json'
  }
  else {
    $ConfigurationPath = Join-Path (Get-Location) 'config.json'
  }
}

if (!$DataPath) {
  if ($PSScriptRoot) {
    $DataPath = Join-Path $PSScriptRoot 'data.csv'
  }
  else {
    $DataPath = Join-Path (Get-Location) 'data.csv'
  }
}

if (-not (Test-Path $ConfigurationPath)) {
  throw "Failed to find the configuration file at `"$ConfigurationPath`"."
}

if (-not (Test-Path $DataPath)) {
  throw "Failed to find the data faile at `"$DataPath`"."
}

try { $SlackExportDir = Get-Item $SlackExportPath -ErrorAction Stop } catch { throw }

try {
  # Generate ReadOnly variables $ClientID, $TenantID, $RootMessageSubject, and $SlackToken from config.json
  $ConfigFile = Get-Content $ConfigurationPath -ErrorAction Stop | ConvertFrom-Json
  foreach ($Property in $ConfigFile.PSObject.Properties) {
    if (-not (Get-Variable -Name $Property.Name -ErrorAction SilentlyContinue)) {
      New-Variable -Name $Property.Name -Value $ConfigFile.($Property.Name) -Scope global -Option ReadOnly
    }
    else {
      Set-Variable -Name $Property.Name -Value $ConfigFile.($Property.Name) -Force
    }
  }
}
catch { throw "Failed to read the configuration file at `"$ConfigurationPath`"." }

try { $Data = Import-Csv $DataPath -ErrorAction Stop }
catch { throw "Failed to read the data file at `"$DataPath`"." }

try { $Users = Get-Content -Path (Join-Path $SlackExportDir.FullName 'users.json') -ErrorAction Stop | ConvertFrom-Json }
catch { throw "Failed to read `"users.json`" in `"$($SlackExportDir.FullName)`"." }

try { $Channels = Get-Content -Path (Join-Path $SlackExportDir.FullName 'channels.json') -ErrorAction Stop | ConvertFrom-Json }
catch { throw "Failed to read `"channels.json`" in `"$($SlackExportDir.FullName)`"." }

if (Test-Path (Join-Path $SlackExportDir.FullName 'groups.json')) {
  try { $Channels += Get-Content (Join-Path $SlackExportDir.FullName 'groups.json') -ErrorAction Stop | ConvertFrom-Json }
  catch { throw }
}

$CheckPointPath = Join-Path $SlackExportDir.FullName 'checkpoint.json'

if ($Resume) {
  if (Test-Path $CheckPointPath) {
    try { $CheckPoint = Get-Content -Path $CheckPointPath -ErrorAction Stop | ConvertFrom-Json }
    catch { throw }
  }
  else { throw "Parameter `"-Resume`" used, but could not find the checkpoint file at `"$CheckPointPath`"" }
}

if (-not (Get-Variable -Name 'Token' -ErrorAction SilentlyContinue)) {
  # Setting "AllScope" will persist the $Token variable throughout all scopes making it easier to use.
  New-Variable -Name 'Token' -Option AllScope
}

Write-Progress "Building user and channel table, depending on number of entries this could take some time."
$UserFromID = @{ }
$Users | ForEach-Object {
  $UserFromID.($_.id) = $_.profile.real_name_normalized
}

$ChannelFromID = @{ }
$Channels | ForEach-Object {
  $ChannelFromID.($_.id) = $_.name
}


<# -----------------------------------------------------------------------------
                                  Begin Script
----------------------------------------------------------------------------- #>


# Get a list of the authenticated user's joined teams
$AvailableTeams = Get-JoinedTeams

# Begin going through each entry in the data.csv file
for ($i = 0; $i -lt ($Data | Measure-Object).Count; $i++) {
  if ($CheckPoint) { $i = $CheckPoint.item }
  $item = $Data[$i]

  Write-Progress ("Channel {0}/{1}" -f ($i + 1), ($Data | Measure-Object).Count)

  if (!$item.slack_channel -or !$item.teams_channel -or !$item.teams_team) {
    Write-Warning "Skipping Slack channel ({0}), missing either 'slack_channel', 'teams_team', or 'teams_channel' from `"$DataPath`"."
    continue
  }

  $Channel = $Channels | Where-Object { $_.name -eq $item.slack_channel }
  if (!$Channel) {
    Write-Warning ("Skipping Slack channel ({0}), make sure the name is correct" -f $item.slack_channel)
    continue
  }

  if ($Channel.is_private -and !$SlackToken) {
    Write-Warning ("Skipping Slack channel ({0}), channel is private and value `"SlackToken`" in config.json is empty." -f $item.slack_channel)
    continue
  }
  elseif ($Channel.is_private) {
    $WebClient.Headers.Set('Authorization', "Bearer $SlackToken")
  }

  $MstTeam = $item.teams_team
  $MstChannel = $item.teams_channel
  $ChannelCreator = $UserFromID.($Channel.creator)
  $ChannelDir = Join-Path $SlackExportDir.FullName $Channel.name
  $AttachmentDir = Join-Path $ChannelDir 'slack_files'
  $MessageBody = ''
  $LastMessage = $false
  $ThreadTable = @{}
  $RootMessageID = $false
  # For some reason some unicode characters are not encoded in the Slack export. Pre-populating this variable with
  # some I ran into otherwise they are not re-encoded properly when sending a message.
  $UnicodeChars = @(160, 162, 174, 194, 226, 8211, 8217, 8220, 8221, 8222, 8226, 8230, 8482)

  try { $DayFiles = Get-ChildItem -Path $ChannelDir -File -Filter "*.json" -ErrorAction Stop | Sort-Object -Property Name }
  catch { throw }

  if (!$DayFiles) {
    Write-Warning "Didn't find any files for the $($item.slack_channel) channel."
    continue
  }

  # Get the Team ID based on the name in data.csv
  Write-Progress "Getting Team ID for $MstTeam"
  $TeamID = ($AvailableTeams | Where-Object { $_.displayName -eq $MstTeam }).id
  if (!$TeamID) {
    Write-Warning ("Skipping Slack channel ({0}), associated team ({1}) not found." -f $item.slack_channel, $MSTTeam)
    continue
  }

  # Get all the channels from the requested Team so we can find the channel ID
  Write-Progress "Getting channels for $MstTeam"
  $AvailableChannels = Get-TeamChannels $TeamID

  # Get the Channel ID based on the name in data.csv
  Write-Progress "Getting Channel ID for $MstChannel"
  $ChannelID = ($AvailableChannels | Where-Object { $_.displayName -eq $MstChannel }).id
  if (!$ChannelID) {
    Write-Warning ("Skipping Slack channel ({0}), associated Teams channel ({1}) not found." -f $item.slack_channel, $MSTChannel)
    continue
  }

  # Check the channel's messages to find an existing import root message
  Write-Progress "Searching for existing root message"
  $ChannelMessages = Get-RootMessages -TeamID $TeamID -ChannelID $ChannelID
  do {

    $RootMessage = $ChannelMessages.value | Where-Object { $_.subject -eq $RootMessageSubject -and !$_.deletedDateTime }
    if (!$RootMessage -and $ChannelMessages.'@odata.nextLink') {
      $ChannelMessages = Invoke-GraphRequest -Query $ChannelMessages.'@odata.nextLink' -FullUrl
    }
    elseif (!$RootMessage) {
      if ($Resume) {
        Write-Warning 'The "-Resume" parameter was used, but no existing message was found.
         Script will continue, but message history may be incomplete.'
      }
      Write-Progress "Creating root message to hold Slack history"
      $Params = @{
        TeamID    = $TeamID
        ChannelID = $ChannelID
        Subject   = $RootMessageSubject
        Message   = @"
<p>This thread is for archival purposes, please do not post any messages here.</p>
<p>Click "see more" to view all messages.</p>
<pre>Channel: $($Channel.name)
Creator: $ChannelCreator
Topic: $($Channel.topic.value)
Purpose: $($Channel.purpose.value)</pre>
"@
      }
      $RootMessageID = New-RootMessage @Params
    }
    else {
      Write-Host "Found existing root message for `"$($Channel.name)`""
      $RootMessageID = $RootMessage.id
    }
  } until ($RootMessageID)

  if (-not (Test-Path $AttachmentDir)) {
    $null = New-Item -Path $AttachmentDir -ItemType Directory
  }

  $Resume = $false


  <# -----------------------------------------------------------------------------
                                 Process Files
----------------------------------------------------------------------------- #>


  # Loop through the messages and grab the files so they can be uploaded
  Write-Progress "Looking for Files"
  foreach ($Day in $DayFiles) {

    # Assume this was already done if '-Resume' is used.
    if ($CheckPoint) { break }

    try { $Messages = Get-Content $Day.FullName -ErrorAction Stop | ConvertFrom-Json }
    catch { throw }

    foreach ($Message in $Messages) {

      foreach ($File in $Message.files) {

        if ($File.mode -eq 'tombstone') {
          Write-Verbose "Deleted file - skipping"
          continue
        }
        if ($File.mode -eq 'external') {
          Write-Verbose "External file - skipping"
          continue
        }
        if ($File.mode -match 'space|docs') {
          Write-Warning "Found a slack `"Post`" ($($File.title)) - can't download this file. Link: $($File.permalink)"
          continue
        }

        $FileName = Format-FileName -Name ($File.id + '-' + $File.name) -Mode $File.mode
        $FilePath = Join-Path $AttachmentDir $FileName

        if ($File.mode -eq 'hosted') {
          Write-Progress "Downloading file: $($File.title)"
        }
        elseif ($File.mode -eq 'snippet') {
          Write-Progress "Downloading snippet: $($File.title)"
        }
        elseif ($File.mode -eq 'email') {
          Write-Progress "Downloading email: $($File.title)"
        }
        else {
          throw "Unable to download file ($($File.title)) from `"$($Channel.name)`" - Unknown type: $($File.mode)"
        }

        if (Test-Path $FilePath) {
          Write-Verbose "File $($File.title) already downloaded"
          continue
        }

        try { $WebClient.DownloadFile($File.url_private_download, $FilePath) }
        catch {
          Write-Warning "Error downloading: Day: $($Day.basename) File: $($File.name)"
          $File
          return
        }
      }

    }

  }

  $LocalFiles = Get-ChildItem $AttachmentDir

  if ($LocalFiles -and !$CheckPoint) {
    Write-Host ""
    Write-Host "Files were downloaded. Copy the `"slack_files`" folder into the `"$MSTChannel`" channel of the `"$MSTTeam`" team."
    $null = Read-Host 'Press "Enter" to open the location of "slack_files"'

    Start-Process -FilePath (join-path $ENV:windir 'explorer.exe') -ArgumentList "/root,`"$ChannelDir`""

    Start-Sleep -Seconds 2
  }

  if ($LocalFiles) {
    $DriveInfo = Get-TeamsChannelFilesLocation -TeamID $TeamID -ChannelID $ChannelID

    $Count = 0
    do {
      if ($Count -gt 2) { Write-Progress "Waiting for the `"slack_files`" folder. Has it been copied to the correct location?" }
      else { Write-Progress "Looking for the `"slack_files`" folder" }

      $SlackFolder = Get-TeamsChannelFolders -DriveID $DriveInfo.parentReference.driveId -ItemID $DriveInfo.id | ForEach-Object { $_.value } | Where-Object { $_.name -eq 'slack_files' }

      if (!$SlackFolder) { Start-Sleep -Seconds 10 }
      $Count++
    } until ($SlackFolder)

    $Count = 0
    do {
      if ($Count -gt 0) { Write-Progress "Waiting for files to upload. Found $($TeamsFiles.count) of $($LocalFiles.count) files" }
      else { Write-Progress "Getting file information from Teams" }

      $TeamsFiles = Get-TeamsChannelFolderItems -DriveID $DriveInfo.parentReference.driveId -ItemID $SlackFolder.id

      $Done = $TeamsFiles.count -eq $LocalFiles.count

      if (!$Done) { Start-Sleep -Seconds 10 }
      $Count++
    } until ($Done)
  }


  <# -----------------------------------------------------------------------------
                                Process Messages
----------------------------------------------------------------------------- #>


  for ($d = 0; $d -lt $DayFiles.Count; $d++) {

    if ($CheckPoint) { $d = $CheckPoint.day }
    $Day = $DayFiles[$d]

    try { $RawMessages = Get-Content $Day.FullName -Encoding UTF8 -ErrorAction Stop }
    catch { throw }

    $UnicodeMatch = $RawMessages | Select-String -Pattern '\\u([0-9a-f]{4})' -AllMatches
    $UnicodeChars += ($UnicodeMatch.Matches.Groups | Where-Object { $_.Name -eq '1' }).Value | ForEach-Object {
      if ($_) { [int64]('0x' + $_) }
    }

    try { $Messages = $RawMessages | ConvertFrom-Json -ErrorAction Stop }
    catch { throw }

    # Loop through all the messages for this day
    for ($m = 0; $m -lt $Messages.Count; $m++) {

      if ($CheckPoint) {
        $m = $CheckPoint.message
        $CheckPoint = $null
      }

      if ($SaveCheckPoint) {
        # Store the position after the last sent message,
        # just in case the next one fails.
        @{
          item    = $i
          day     = $d
          message = $m
        } | ConvertTo-Json | Set-content -Path $CheckPointPath
        $SaveCheckPoint = $false
      }

      $Message = $Messages[$m]

      Write-Progress ("Day: {0}/{1} - Message: {2}/{3}" -f ($d + 1), $DayFiles.Count, ($m + 1), $Messages.Count)

      if (($d + 1) -eq $DayFiles.Count -and ($m + 1) -eq $Messages.Count) { $LastMessage = $true }

      if ($Message.subtype -and ($AllowedSubtypes -notcontains $Message.subtype) -and $LastMessage -and $MessageBody) {
        # Send message now if:
        # - The message has a subtype
        # - It's not a desired subtype
        # - It's the last message for this channel
        # - There is something to send

        Write-Progress ("Day: {0}/{1} - Message: {2}/{3} - Sending last message" -f ($d + 1), $DayFiles.Count, ($m + 1), $Messages.Count)
        New-ReplyMessage -TeamID $TeamID -ChannelID $ChannelID -RootMessageID $RootMessageID -Message $MessageBody

        $SaveCheckPoint = $true
        continue
      }
      elseif ($Message.subtype -and ($AllowedSubtypes -notcontains $Message.subtype) -and !$LastMessage) {
        # Skipping a message if:
        # - It has a subtype
        # - The subtype isn't one we want
        # - It's not the last message (otherwise we might not send some messages)
        continue
      }
      elseif ($Message.subtype -and ($AllowedSubtypes -notcontains $Message.subtype) -and $LastMessage -and !$MessageBody) {
        # Skipping a message if:
        # - It has a subtype
        # - The subtype isn't one we want
        # - It is the last message
        # - There are no pending messages
        continue
      }
      elseif ($Message.bot_id) {
        # Some bot messages don't have a subtype, but a bot_id
        continue
      }

      $MessageDate = ($Epoch.AddSeconds($Message.ts)).ToString('M/d/yyyy h:mm tt')
      $MessageText = $Message.text
      $Files = $Message.files
      $NewMessage = ''
      $MessageTooLarge = $false
      $MessageAttachments = @()

      if ($MessageText.Length -gt 25000) {
        # If a single message is longer than 25,000 characters script will fail to send.
        # Logic to split the message into multiple message could be added but we're just
        # going to truncate it.
        Write-Warning "A message was too large and has been truncated. Message TS: $($Message.ts)"
        $MessageText = $MessageText.Substring(0, $MessageTrimLength) + '<br>&lt;Message was too large and has been truncated.&gt;'
      }

      # The message username changes depending on the subtype (if any)
      if ($Message.subtype -eq 'file_comment') { $MessageUser = '' }
      else { $MessageUser = $UserFromID.($Message.user) }

      if ($Message.thread_ts -eq $Message.ts) {
        # Builds a table of threaded posts, so replies can refer to them later
        # Otherwise we would have to load all messages into memory first
        # Any messages that are a part of a thread use the 'thread_ts' value
        # to refer to the root message's 'ts' value.
        $ThreadTable.($Message.ts) = @{
          user = $MessageUser
          date = $MessageDate
        }
      }

      # This pattern grabs any special Slack-formatted text
      # See https://api.slack.com/reference/surfaces/formatting#retrieving-messages
      $FormattedText = ($MessageText | Select-String -Pattern '<(.*?)>' -AllMatches).Matches

      for ($ii = 0; $ii -lt $FormattedText.Count; $ii++) {

        switch -regex ($FormattedText[$ii].Groups[1].Value) {

          # Channel mention
          '#(C.+)' {
            $ID = $Matches[1] -split "\|"
            if ($ID.Count -gt 1) { $Name = $ID[1] }
            else {
              $Name = $ChannelFromID[$Matches[1]]
              if (!$Name) { $Name = $Matches[1] }
            }
            $Replacement = '<a style="text-decoration: none;">@' + $Name + '</a>'
            break
          }

          # User mention
          '^@(U.+)' {
            $ID = $Matches[1] -split "\|"
            if ($ID.Count -gt 1) { $Name = $ID[1] }
            else {
              $Name = $UserFromID[$ID]
              if (!$Name) { $Name = $Matches[1] }
            }
            $Replacement = '<a style="text-decoration: none;">@' + $Name + '</a>'
            break
          }

          # Special mention
          '^!(.*)' {
            $Replacement = '<a style="text-decoration: none;">@' + $Matches[1] + '</a>'
            break
          }

          # Links with alternative text
          '(.*?)\|(.*)' {
            $Replacement = '<a href="' + $Matches[1] + '">' + $Matches[2] + '</a>'
            break
          }

          # Anything else, should be a link
          Default {
            $Replacement = '<a href="' + $FormattedText[$ii].Groups[1].Value + '">' + $FormattedText[$ii].Groups[1].Value + '</a>'
          }
        }

        $MessageText = $MessageText.Replace($FormattedText[$ii].Groups[0].Value, $Replacement)
      }

      # Fix newlines
      $MessageText = $MessageText.Replace("`n", '<br />')

      if ($MessageBody.Length -gt 0) {
        # Adds a space between messages
        $NewMessage += '<br>'
      }

      # Start message
      $NewMessage += '<div style="border: .2rem solid #777; border-top-color: rgb(0, 137, 0); border-radius: .3rem; padding: .8rem 1.6rem;">'

      if ($Message.subtype -eq 'thread_broadcast') {
        # Indicate a broadcast message, see https://slackhq.com/getting-the-most-out-of-threads
        $NewMessage += '<div><em>Also sent to the channel</em></div>'
      }

      if ($Message.thread_ts -and ($Message.thread_ts -ne $Message.ts)) {
        # Indicate that the message is a reply to a thread
        $NewMessage += "<div><em>Reply to {0} @ {1}</em></div>" -f $ThreadTable.($Message.thread_ts).user, $ThreadTable.($Message.thread_ts).date
      }

      if ($Message.subtype -eq 'me_message') { $MessageText = '<em>/me ' + $MessageText + '</em>' }

      # Main message content (username, date, text)
      $NewMessage += @"
<div style="padding-bottom: .8rem; border-bottom: .2rem solid #777;"><strong>$MessageUser</strong>&nbsp;&nbsp;<em>$MessageDate</em></div>
<div style="padding-top: .8rem;">$MessageText
"@

      if ($Files) {
        # Add attachments

        foreach ($File in $Files) {
          # Slack stores each attachment in a folder with a unique ID. Easier to
          # append the ID to the filename instead of creating folders per attachment.
          # Otherwise filenames would conflict.

          $FileName = Format-FileName ($File.id + '-' + $File.name) -Mode $File.mode

          $TeamFile = $TeamsFiles | Where-Object { $_.name -eq $FileName }

          if ($File.mode -eq 'tombstone') {
            $NewMessage += '<div>&lt;Attached file was deleted.&gt;</div>'
          }
          elseif ($File.mode -match 'space|docs') {
            $NewMessage += "<div>&lt;Slack post: <a href=`"$($File.permalink)`">$($File.title)</a>&gt;</div>"
          }
          elseif ($File.mode -ne "external") {
            if (!$TeamFile) { Write-Warning "Couldn't find file ($FileName) in Teams. Unable to attach to message." }

            $NewMessage += @"
<div>&lt;Attached: $FileName&gt;</div>
<attachment id="$($TeamFile.guid)"></attachment>
"@

            # Attachment information needs a separate section outside of the body of
            # the message. The 'reference' contentType indicates the file already exists in Teams.
            $MessageAttachments += @{
              id          = $TeamFile.guid
              contentType = 'reference'
              contentUrl  = $TeamFile.webUrl
              name        = $TeamFile.name
            }
          }
        }
      }

      $NewMessage += '</div></div>'

      if (!$MessageBody -and $NewMessage.Length -ge 26000) {
        # Error out if the only message is too large, otherwise script will get stuck.
        throw "Message too large. Please re-run and set `"-MessageTrimLength`" to a value lower than 25000."
      }
      elseif (($NewMessage + $MessageBody).Length -lt 26000) {
        # Slack maximum message size is 40,000 characters, so only add the curent
        # message if it doesn't put us over the character limit.
        $MessageBody += $NewMessage
      }
      else {
        $d = $LastMessagePos.d
        $m = $LastMessagePos.m
        $MessageAttachments = @()
        $MessageTooLarge = $true
      }

      if ($MessageBody.Length -gt 25000 -or $LastMessage -or $MessageAttachments -or $MessageTooLarge) {
        # - In testing, the max $MessageBody allowed was about 28k characters. We're
        #   going to send the message once it's about 26k characters just to be safe.
        # - We will also send if it's the last message of the channel.
        # - We'll send the message if there are any attachments, because
        #   attachments always appear at the bottom of a message so it would be
        #   confusing to show any more messages afterwards.
        # - Lastly send the message if the current one is too large

        Write-Progress ("Day: {0}/{1} - Message: {2}/{3} - Sending message" -f ($d + 1), $DayFiles.Count, ($m + 1), $Messages.Count)

        $Params = @{
          TeamID        = $TeamID
          ChannelID     = $ChannelID
          RootMessageID = $RootMessageID
          Message       = $MessageBody
          Attachments   = $MessageAttachments
        }

        New-ReplyMessage @Params

        $MessageBody = ''
        $SaveCheckPoint = $true

      } # End send message logic

      $LastMessagePos = @{ d = $d; m = $m }

    } # End message loop

  } # End day loop

  if ($WebClient.Headers -contains 'Authorization') {
    $WebClient.Headers.Remove('Authorization')
  }

  if (!$LastMessage) {
    Write-Warning "Seems that there might have been an issue processing all the messages for the `"$($Channel.name)`" channel. `
         Try again adding the `"-Resume`" parameter to try again from the last successful message."
  }

} # End channel loop

Write-Host "Done!" -ForegroundColor Green