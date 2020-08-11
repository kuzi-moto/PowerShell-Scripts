<#
.SYNOPSIS
  Imports Slack conversation history from an export archive, to Microsoft Teams Channels

.DESCRIPTION
  Using a spreadsheet, this script will go through all Slack messages from an export archive into a corresponding
  Microsoft Teams channel. First, the script will download all attachments then prompt the user to upload them
  manually (to simplify the script), then will loop through all messages, including the attachments if any.

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

  #[String]$ConfigurationPath = (Join-Path $PSScriptRoot 'config.json'),
  [String]$ConfigurationPath = (Join-Path './' 'config.json'),

  #[String]$DataPath = (Join-Path $PSScriptRoot 'data.csv')
  [String]$DataPath = (Join-Path './' 'data.csv')
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
    [string]$Method = "Get"
  )

  function Update-Token {
    # Utilizes global $Token variable
    try {
      Write-Progress "Updating access token"
      Write-Host ""
      Write-Host "Please login. If you don't see the login pop-up, it may be hidden behind the terminal window." -ForegroundColor Yellow
      $Token = Get-MsalToken -ClientId $ClientId -TenantId $TenantID -Interactive -RedirectUri "http://localhost"
    }
    catch { throw }
  }

  if ($Query -match '(?:v1\.0|beta)\/(.*)') {
    Write-Error "`"-Query`" parameter should not use full URL. Try again using just `"$($Matches[1])`""
    return
  }

  # These queries will be assigned to the 'beta' endpiont instead of 'v1.0'
  $BetaRegex = @(
    [regex]::new('^teams\/.*?\/channels\/.*?\/messages$')
    [regex]::new('^teams\/.*?\/channels\/.*?\/messages\/.*?\/replies$')
  )

  if (($BetaRegex.Match($Query)).Success -contains $true) { $Endpoint = 'beta' }
  else { $Endpoint = 'v1.0' }

  if ($QueryStringData) {
    $URL = "https://graph.microsoft.com/$Endpoint/$Query", (Get-EncodedQueryString $QueryStringData) -join '?'
  }
  else { $URL = "https://graph.microsoft.com/$Endpoint/$Query" }

  for ($i = 0; $i -lt 3; $i++) {
    $AccessToken = $Token.AccessToken
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
          throw "Bad request - $($Response.message)"
        }
        Default {
          throw "Other error: $($Response.code) - $($Response.message)"
        }
      }
    }
  }
  throw 'Invoke-GraphRequest failed to run the query after 3 attempts.'
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


function Get-SlackFilesInTeams {
  param (
    [Parameter(Mandatory = $true)]
    [String]$TeamID,
    [Parameter(Mandatory = $true)]
    [String]$ChannelID
  )

  try {
    # Get the metadata for the location where the files of a channel are stored.
    $Params = @{
      Query           = "teams/$TeamID/channels/$ChannelID/filesFolder"
      QueryStringData = @{ select = 'parentReference,id' }
    }
    $DriveInfo = Invoke-GraphRequest @Params
  }
  catch { throw }

  try {
    # Get the folders for the channel
    $Params = @{
      Query           = "drives/$($DriveInfo.parentReference.driveId)/items/$($DriveInfo.id)/children"
      QueryStringData = @{ select = 'id,name' }
    }
    $DriveFolders = Invoke-GraphRequest @Params
  }
  catch { throw }

  $SlackFolder = $DriveFolders.value | Where-Object { $_.name -eq 'slack_files' }

  if (!$SlackFolder) {
    throw "Could not find the `"slack_files`" directory for this channel please check that you have copied it to the right location."
  }

  $Files = @()
  try {
    $Params = @{
      Query           = "drives/$($DriveInfo.parentReference.driveId)/items/$($SlackFolder.id)/children"
      QueryStringData = @{ select = 'eTag,name,webUrl' }
    }
    $Response = Invoke-GraphRequest @Params
    $Files += $Response.value | Select-Object name, webUrl, @{Label = 'guid'; Expression = { $_.eTag | Select-String -Pattern '{(.*?)}' | ForEach-Object { $_.matches.Groups[1].value } } }
  }
  catch { throw }

  $Files
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
    } | ConvertTo-Json
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
    #$Params.Body.attachments = @()
    [array]$Params.Body.attachments += $Attachments
  }

  $Params.Body = $Params.Body | ConvertTo-Json

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


function Format-FileSize {
  # Stolen from https://superuser.com/a/468795
  Param ([int]$Size)
  If ($Size -gt 1TB) { [string]::Format("{0:0.00} TB", $Size / 1TB) }
  ElseIf ($Size -gt 1GB) { [string]::Format("{0:0.00} GB", $Size / 1GB) }
  ElseIf ($Size -gt 1MB) { [string]::Format("{0:0.00} MB", $Size / 1MB) }
  ElseIf ($Size -gt 1KB) { [string]::Format("{0:0.00} kB", $Size / 1KB) }
  ElseIf ($Size -gt 0) { [string]::Format("{0:0.00} B", $Size) }
  Else { "" }
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

if (-not (Test-Path $ConfigurationPath)) {
  throw "Failed to find the configuration file at `"$ConfigurationPath`"."
}

if (-not (Test-Path $DataPath)) {
  throw "Failed to find the data faile at `"$DataPath`"."
}


<# -----------------------------------------------------------------------------
                                 Set Variables
----------------------------------------------------------------------------- #>


$Epoch = Get-Date 01.01.1970
$WebClient = New-Object System.Net.WebClient

try { $SlackExportDir = Get-Item $SlackExportPath } catch { throw }

try {
  # Generate constant variables $ClientID, $TenantID, and $RootMessageSubject from config.json
  $ConfigFile = Get-Content $ConfigurationPath -ErrorAction Stop | ConvertFrom-Json
  foreach ($Property in $ConfigFile.PSObject.Properties) {
    if (-not (Get-Variable -Name $Property.Name -ErrorAction SilentlyContinue)) {
      New-Variable -Name $Property.Name -Value $ConfigFile.($Property.Name) -Option Constant
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
  catch { throw "" }
}

if (-not (Get-Variable -Name 'Token' -ErrorAction SilentlyContinue)) {
  # Setting "AllScope" will persist the $Token variable throughout all scopes to make it easier to use.
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
$ItemCount = 1
foreach ($item in $Data) {

  Write-Progress ("Channel {0}/{1}" -f $ItemCount, ($Data | Measure-Object).Count)

  $Channel = $Channels | Where-Object { $_.name -eq $item.slack_channel }
  if (!$Channel) {
    Write-Warning ("Skipping Slack channel ({0}), make sure the name is correct" -f $item.slack_channel)
    continue
  }

  try { $DayFiles = Get-ChildItem -Path $ChannelDir -File -Filter "*.json" -ErrorAction Stop | Sort-Object -Property Name }
  catch { throw }

  $MstTeam = $item.teams_team
  $MstChannel = $item.teams_channel
  $ChannelCreator = $UserFromID.($Channel.creator)
  $ChannelDir = Join-Path $SlackExportDir.FullName $Channel.name
  $AttachmentDir = Join-Path $ChannelDir 'slack_files'
  $MessageBody = ''
  $LastMessage = $false

  # Get the Team ID based on the name in data.csv
  $TeamID = ($AvailableTeams | Where-Object { $_.displayName -eq $MstTeam }).id
  if (!$TeamID) {
    Write-Warning ("Skipping Slack channel ({0}), associated team ({1}) not found." -f $item.slack_channel, $MSTTeam)
    continue
  }

  # Get all the channels from the requested Team so we can find the channel ID
  $AvailableChannels = Get-TeamChannels $TeamID

  # Get the Channel ID based on the name in data.csv
  $ChannelID = ($AvailableChannels | Where-Object { $_.displayName -eq $MstChannel }).id
  if (!$ChannelID) {
    Write-Warning ("Skipping Slack channel ({0}), associated Teams channel ({1}) not found." -f $item.slack_channel, $MSTChannel)
    continue
  }

  # Check the team messages to see if an import has been done already
  $ChannelMessages = Get-RootMessages -TeamID $TeamID -ChannelID $ChannelID
  $RootMessage = $ChannelMessages.value | Where-Object { $_.subject -eq $RootMessageSubject }
  if (!$RootMessage) {
    Write-Progress "Creating root message to hold Slack history"
    $Params = @{
      TeamID    = $TeamID
      ChannelID = $ChannelID
      Subject   = $RootMessageSubject
      Message   = @"
<p>This thread is for archival purposes, please do not post any messages here.</p>
<pre>Channel: $($Channel.name)
Creator: $ChannelCreator
Topic: $($Channel.topic.value)
Purpose: $($Channel.purpose.value)</pre>
"@
    }
    $RootMessageID = New-RootMessage @Params
  }
  else {
    Write-Host "Found existing root message"
    $RootMessageID = $RootMessage.id
  }

  if (-not (Test-Path $AttachmentDir)) {
    $null = New-Item -Path $AttachmentDir -ItemType Directory
  }

  <# -----------------------------------------------------------------------------
                                 Process Files
----------------------------------------------------------------------------- #>

  # Loop through the messages and grab the files so they can be uploaded
  $DayCount = 1
  foreach ($Day in $DayFiles) {

    try { $Messages = Get-Content $Day.FullName -ErrorAction Stop | ConvertFrom-Json }
    catch { throw }

    $MessageCount = 1
    foreach ($Message in $Messages) {

      foreach ($File in $Message.files) {

        $AttachmentFile = Join-Path $AttachmentDir ($File.id + '-' + $File.name)

        if (Test-Path $AttachmentFile) {
          Write-Verbose "File $($File.title) already downloaded"
        }
        elseif ($File.mode -ne "external") {
          Write-Progress "Downloading $($File.title)"

          try { $WebClient.DownloadFile($File.url_private_download, $AttachmentFile) }
          catch { Write-Warning "Error downloading" }
        }
      }

      $MessageCount++
    }

    $DayCount++
  }

  if (Get-ChildItem $AttachmentDir) {
    Write-Host "Files were downloaded. Please copy the `"slack_files`" folder into the $MSTChannel channel of the $MSTTeam team."
    $null = Read-Host 'Press "Enter" to open the location of "slack_files"'
    Start-Process -FilePath (join-path $ENV:windir 'explorer.exe') -ArgumentList "/root,`"$ChannelDir`""
    $null = Read-Host 'Press "Enter" once you have copied the files, and they have finished uploading'
    Start-Sleep -Seconds 2
    $TeamsFiles = Get-SlackFilesInTeams -TeamID $TeamID -ChannelID $ChannelID
  }


  <# -----------------------------------------------------------------------------
                                Process Messages
----------------------------------------------------------------------------- #>


  $DayCount = 1
  foreach ($Day in $DayFiles) {

    try { $Messages = Get-Content $Day.FullName -ErrorAction Stop | ConvertFrom-Json }
    catch { throw }

    # Loop through all the messages in each chat file
    $MessageCount = 1
    foreach ($Message in $Messages) {

      Write-Progress ("Day: {0}/{1} - Message: {2}/{3}" -f $DayCount, $DayFiles.Count, $MessageCount, $Messages.Count)

      if ($DayCount -eq $DayFiles.Count -and $MessageCount -eq $Messages.Count - 1) { $LastMessage = $true }

      $AllowedSubtypes = 'file_comment', 'me_message', 'thread_broadcast'
      # Skipping any messages other than standard user messages
      if ($Message.subtype -and $AllowedSubtypes -notcontains $Message.subtype -and !$LastMessage) { continue }

      if ($Message.subtype -and $AllowedSubtypes -notcontains $Message.subtype -and $LastMessage -and $MessageBody) {
        # We want to send now if it's the last message and doesn't meet the subtype we are looking for
        Write-Progress "Reached last message: Sending"
        New-ReplyMessage -TeamID $TeamID -ChannelID $ChannelID -RootMessageID $RootMessageID -Message $MessageBody
        continue
      }

      $MessageDate = ($Epoch.AddSeconds($Message.ts)).ToString('M/d/yyyy h:m tt')
      $MessageText = $Message.text
      $Files = $Message.files
      $MessageAttachments = @()
      $ThreadTable = @{}

      # The message username changes depending on the subtype (if any)
      if ($Message.subtype -eq 'file_comment') { $MessageUser = '' }
      else { $MessageUser = $UserFromID.($Message.user) }

      if ($Message.thread_ts -eq $Message.ts) {
        $ThreadTable.($Message.ts) = @{
          user = $MessageUser
          date = $MessageDate
        }
      }

      # This pattern will grab any special Slack-formatted text
      $FormattedText = ($MessageText | Select-String -Pattern '<(.*?)>' -AllMatches).Matches
      for ($i = 0; $i -lt $FormattedText.Count; $i++) {

        switch -regex ($FormattedText[$i].Groups[1].Value) {
          # Channel mentions
          '^#(C.*)' {
            $Name = $ChannelFromID[$Matches[1]]
            if (!$Name) { $Matches[1] }
            $Replacement = '<a style="text-decoration: none;">@' + $Name + '</a>'
            break
          }
          # User mentions
          '^@(U.*)' {
            $ID = $Matches[1] -split "\|"
            if ($ID.Count -gt 1) { $Name = $ID[1] }
            else {
              $Name = $UserFromID[$ID]
              if (!$Name) { Write-Host 'didnt find name'; $Name = $Matches[1] -replace '<', '' -replace '>', '' }
            }
            $Replacement = '<a style="text-decoration: none;">@' + $Name + '</a>'
            break
          }
          # Special mentions
          '^!(.*)' {
            $Replacement = '<a style="text-decoration: none;">@' + $Matches[1] + '</a>'
            break
          }
          # Links with alternative text
          '(.*)\|(.*)' {
            $Replacement = '<a href="' + $Matches[1] + '">' + $Matches[2] + '</a>'
            break
          }
          # Anything else, should be a link
          Default {
            $Replacement = '<a href="' + $FormattedText[$i].Groups[1].Value + '">' + $FormattedText[$i].Groups[1].Value + '</a>'
          }
        }

        $MessageText = $MessageText.Replace($FormattedText[$i].Groups[0].Value, $Replacement)
      }


      # Unicode
      $UnicodeText = ($MessageText | Select-String -Pattern '\\u[0-9a-fA-F]{4}' -AllMatches).Matches
      for ($i = 0; $i -lt $UnicodeText.Count; $i++) {

        $MessageText = $MessageText.Replace($UnicodeText[$i].Value, [regex]::Unescape($UnicodeText[$i].Value))
      }

      # Fix newlines
      $MessageText = $MessageText.Replace("`n", '<br />')

      if ($MessageBody.Length -gt 0) {
        # Adds a space between messages in the same comment
        $MessageBody += '<br>'
      }

      if ($Message.subtype -eq 'me_message') { $MessageText = '/me ' + $MessageText }

      $MessageBody += '<div id="{0}" style="border: .2rem solid #777; border-top-color: rgb(0, 137, 0); border-radius: .3rem; padding: .8rem 1.6rem;">' -f $Message.ts

      if ($Message.subtype -eq 'thread_broadcast') {
        $MessageBody += '<div><em>Also sent to the channel</em></div>'
      }

      # TODO: Create table of threads so that we can refer to them in replies. Will need the 'ts', with the author and time of post.
      if ($Message.thread_ts -and $Message.thread_ts -ne $Message.ts) {
        $MessageBody += "<div><em>Reply to {0} @ {1}</em></div>" -f $ThreadTable.($Message.thread_ts).user, $ThreadTable.($Message.thread_ts).date
      }

      $MessageBody += @"
<div style="padding-bottom: .8rem; border-bottom: .2rem solid #777;"><strong>$MessageUser</strong>&nbsp;&nbsp;<em>$MessageDate</em></div>
<div style="padding-top: .8rem;">$MessageText
"@

      # Add attachments
      if ($Files) {

        foreach ($File in $Files) {

          # Slack stores each attachment in a folder with a unique ID. Easier to
          # append the ID to the filename instead of creating folders per attachment.
          $FileName = $File.id + '-' + $File.name
          $TeamFile = $TeamsFiles | Where-Object { $_.name -eq $FileName }
          if ($File.mode -ne "external") {
            $MessageBody += @"
<div>&lt;Attached: $FileName&gt;</div>
<attachment id="$($TeamFile.guid)"></attachment>
"@

            # Attachment information needs a separate section outside of the body of
            # the message. the 'reference' contentType indicates the file already exists
            $MessageAttachments += @{
              id          = $TeamFile.guid
              contentType = 'reference'
              contentUrl  = $TeamFile.webUrl
              name        = $TeamFile.name
            }
          }
        }
      }

      $MessageBody += '</div></div>'

      if ($MessageBody.Length -gt 25000 -or $LastMessage -or $MessageAttachments) {
        # - In testing, the max $MessageBody allowed was about 28k characters. We're
        #   going to send the message once it's about 25k characters just to be safe.
        # - We will also send if it's the last message of the channel.
        # - Lastly we'll send the message if there are any attachments, because
        #   attachments always appear at the bottom of a message.

        Write-Progress "Sending Message"

        $Params = @{
          TeamID        = $TeamID
          ChannelID     = $ChannelID
          RootMessageID = $RootMessageID
          Message       = $MessageBody
          Attachments   = $MessageAttachments
        }

        New-ReplyMessage @Params

        $MessageBody = ''
      }

      $MessageCount++
    }

    $DayCount++
  }

  $ItemCount++
}

Write-Host "Done!" -ForegroundColor Green