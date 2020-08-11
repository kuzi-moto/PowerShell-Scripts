[CmdletBinding()]
param (
  [Parameter(Mandatory = $true)]
  [String]$ExportPath,

  [String]$Destination = '.\output',

  [string]$Channel
)

# Look at https://powershellexplained.com/2017-03-18-Powershell-reading-and-saving-data-to-files/ for a better way to save to files.
# Icons from https://icomoon.io/ from slack v2 font

try {
  $ExportDirectory = Get-Item $ExportPath -ErrorAction Stop
}
catch {
  Write-Host "`"$ExportPath`" is not a valid directory."
  return
}

try {
  Get-Item (Join-Path $ExportDirectory.FullName 'channels.json') -ErrorAction Stop | Out-Null
  Get-Item (Join-Path $ExportDirectory.FullName 'users.json') -ErrorAction Stop  | Out-Null
}
catch {
  Write-Host "Either `"users.json`" or `"channels.json`" are missing. Please make sure you're using the correct directory"
  return
}

### Functions

function Get-HTMLHead {
  return @"
<!DOCTYPE html>
<html>
<head>
  <title>$ChannelName</title>
  <style>
    body {
      font-family: sans-serif;
      margin: 0;
      padding: 0;
    }
    .day-separator {
      display: block;
      text-align: center;
    }
      hr {
        border-top: 1px solid rgba(221,221,221,1);
        border-bottom: 0;
        bottom: 20px;
        margin: 0;
        padding: 0;
        position: relative;
      }
      .date {
        background: rgb(255, 255, 255);
        border: 0;
        border-radius: 24px;
        box-shadow: rgba(29, 28, 29, 0.13) 0px 0px 0px 1px, rgba(0, 0, 0, 0.08) 0px 1px 3px 0px;
        display: inline-block;
        font-size: 13px;
        font-weight: 700;
        height: 28px;
        line-height: 27px;
        margin: 6px 0;
        padding: 0 16px;
        position: relative;
        z-index: 2;
      }
    .message-item {
      color: rgb(29, 28, 29);
      display: block;
      font-size: 15px;
      line-height: 22px;
      margin-bottom: 0;
      padding: 8px 20px;
      text-align: left;
      width: 100%;
    }
      .username {
        display: inline-block;
        font-weight: 900;
        margin-right: .5em;
      }
        .app-label {
          background-color: rgba(29,28,29,.13);
          color: rgba(29,28,29,.7);
          border-radius: 2px;
          font-size: 10px;
          padding: 1px 3px;
          margin-left: 4px;
          font-weight: 700;
          vertical-align: top;
        }
      .message-time {
        color: rgb(97, 96, 97);
        display: inline-block;
        font-size: 12px;
        font-weight: 400px;
        line-height: 17.6px;
      }
      .message-text {
        display: block;
        font-weight: 400;
        line-height: 1.5;
      }
        .mention {
          color: blue;
    }
    .message-file {
      border: 1px solid rgba(29,28,29,0.1);
      border-radius: 4px;
      margin-top: 4px;
      max-width: 426px;
      padding: 12px;
    }
      .file-name {
        font-size: 16px;
        font-weight: 700;
        color: rgba(29,28,29,1);
        padding: 4px 0;
        margin: -4px 0;
      }
      .file-information {
        line-height: 1;
        font-size: 13px;
        font-weight: 400;
        color: rgba(97,96,97,1);
        margin-top: 4px;
      }
        .file-size {}
        .file-type {}
      .icon {
        display: inline-block;
        fill: currentColor;
        height: 1em;
        stroke: currentColor;
        stroke-width: 0;
        width: 1em;
      }
  </style>
</head>
<body>
  <svg aria-hidden=`"true`" style=`"position: absolute; width: 0; height: 0; overflow: hidden;`" version=`"1.1`" xmlns=`"http://www.w3.org/2000/svg`" xmlns:xlink=`"http://www.w3.org/1999/xlink`"><defs><symbol id=`"icon-cloud_download`" viewBox=`"0 0 32 32`"><path d=`"M6.416 28.8c-3.536 0-6.416-2.976-6.416-6.624 0-2.208 1.072-4.192 2.72-5.392-0.176-0.608-0.272-1.248-0.272-1.888 0-3.648 2.88-6.608 6.4-6.608 0.256 0 0.512 0.016 0.768 0.032 1.888-3.136 5.232-5.12 8.912-5.12 5.776 0 10.48 4.88 10.496 10.864 1.872 1.552 2.976 3.904 2.976 6.464 0 4.56-3.584 8.272-8 8.272h-17.584zM6.416 26.4h17.584c3.088 0 5.6-2.64 5.6-5.872 0-2.16-1.12-4.064-2.768-5.088-0.4-0.224-0.208-0.464-0.208-1.344 0-4.688-3.632-8.496-8.096-8.496-3.376 0-6.272 2.176-7.488 5.264-0.096 0.256-0.272 0.32-0.512 0.192-0.512-0.24-1.072-0.368-1.68-0.368-2.208 0-4 1.872-4 4.208 0 1.040 0.352 1.984 0.944 2.72 0.192 0.24 0.144 0.368-0.16 0.432-1.84 0.368-3.232 2.080-3.232 4.128 0 2.336 1.792 4.224 4.016 4.224zM16.4 23.2c-0.384 0-0.688-0.208-0.848-0.368l-4.8-4.784c-0.224-0.224-0.352-0.528-0.352-0.832s0.112-0.608 0.352-0.848 0.56-0.368 0.864-0.368 0.608 0.128 0.832 0.352l2.752 2.736v-6.688c0-0.336 0.128-0.64 0.336-0.848 0.224-0.224 0.528-0.352 0.864-0.352s0.624 0.144 0.848 0.352 0.352 0.512 0.352 0.848v6.688l2.768-2.736c0.224-0.224 0.528-0.352 0.832-0.352 0.32 0 0.624 0.16 0.88 0.4 0.224 0.208 0.32 0.512 0.32 0.8 0 0.304-0.112 0.624-0.352 0.848l-4.8 4.784c-0.24 0.224-0.544 0.368-0.848 0.368z`"></path></symbol><symbol id=`"icon-file_generic`" viewBox=`"0 0 32 32`"><path d=`"M9.76 30.4c-2.736 0-4.96-2.224-4.96-4.96v-18.88c0-2.736 2.224-4.96 4.96-4.96h7.52c1.504 0 2.864 0.544 3.92 1.632l4.448 4.544c1.024 1.056 1.552 2.352 1.552 3.808v13.856c0 2.736-2.224 4.96-4.96 4.96h-12.48zM9.76 28h12.48c1.408 0 2.56-1.152 2.56-2.56v-13.856c0-0.848-0.272-1.52-0.88-2.144l-4.448-4.544c-0.592-0.608-1.296-0.896-2.192-0.896h-7.52c-1.408 0-2.56 1.152-2.56 2.56v18.88c0 1.408 1.152 2.56 2.56 2.56zM14.784 15.040c-0.656 0-1.2-0.512-1.2-1.2v-6.4c0-0.688 0.528-1.2 1.2-1.2 0.656 0 1.2 0.512 1.2 1.2v5.2h5.216c0.672 0 1.168 0.544 1.184 1.2 0.016 0.672-0.512 1.2-1.184 1.2h-6.416z`"></path></symbol></defs></svg>
  <h1>Information</h1>
  <p>Channel: $ChannelName</p>
  <p>Creator: $ChannelCreator</p>
  <p>Topic  : $ChannelTopic</p>
  <p>Purpose: $ChannelPurpose</p>
  <h2>Messages</h2>
"@
}

function Get-HTMLDaySeparator {
  param ([string]$Day)

  $DayFormat = Get-Date $Day -Format "MMMM dd, yyyy"

  return @"
  <div class="day-separator">
    <div class=`"date`">$DayFormat</div>
    <hr />
  </div>
"@
}

function Get-HTMLFile {
  param (
    [string]$Title,
    [string]$Size,
    [string]$Type,
    [string]$Path
  )

  return @"
  <div class=`"message-file`">
    <div class=`"file-name`">$Title</div>
    <div class=`"file-information`">
      <span class=`"file-size`">$Size</span>
      &nbsp;
      <span class=`"file-type`">$Type</span>
    </div>
  </div>
"@

}

function Get-HTMLIcon {
  param ([string]$Icon)

  switch ($Icon) {
    'download' { $IconName = 'icon-cloud_download'; break }
    'file' { $IconName = 'icon-file_generic'; break }
    Default {}
  }

  return "<svg class=`"icon $IconName`"><use xlink:href=`"#$IconName`"></use></svg>`""
}

function Get-HTMLMessage {
  param (
    [string]$Username,
    [string]$Date,
    [string]$Message,
    [string]$Type,
    [array]$Files
  )

  $MessageObject = @()

  $MessageObject += @"
  <div class="message-item">
"@

  if (!$Type) {
    $MessageObject += @"
    <div class="username">$MessageUser</div>
"@
  }
  elseif ($Type -eq 'bot_message') {
    $MessageObject += @"
    <div class="username">$MessageUser<span class="app-label">APP</span></div>
"@
  }

  $MessageObject += @"
    <time class="message-time">$MessageDate</time>
    <div class="message-text">$MessageText</div>
"@

  $MessageObject += $Files

  $MessageObject += "  </div>"

  return $MessageObject
}

# Stolen from https://superuser.com/a/468795
function Format-FileSize {
  Param ([int]$Size)
  If     ($Size -gt 1TB) {[string]::Format("{0:0.00} TB", $Size / 1TB)}
  ElseIf ($Size -gt 1GB) {[string]::Format("{0:0.00} GB", $Size / 1GB)}
  ElseIf ($Size -gt 1MB) {[string]::Format("{0:0.00} MB", $Size / 1MB)}
  ElseIf ($Size -gt 1KB) {[string]::Format("{0:0.00} kB", $Size / 1KB)}
  ElseIf ($Size -gt 0)   {[string]::Format("{0:0.00} B", $Size)}
  Else                   {""}
}

### End Functions

$Users = Get-Content -Path '.\users.json' | ConvertFrom-Json
$Channels = Get-Content -Path '.\channels.json' | ConvertFrom-Json
$Epoch = Get-Date 01.01.1970
$WebClient = New-Object System.Net.WebClient

Write-Host "Building user table"
$UserFromID = @{ }
$Users | ForEach-Object {
  $UserFromID.($_.id) = $_.profile.real_name_normalized
}

Write-Host "Building channel table"
$ChannelFromID = @{ }
$Channels | ForEach-Object {
  $ChannelFromID.($_.id) = $_.name
}

# If a single channel is specified, remove all others
if ($Channel) {
  [array]$Channels = $Channels | Where-Object { $_.name -eq $Channel }

  if ($null -eq $Channels) {
    Write-Host "Specified channel: `"$Channel`" Could not be found" -ForegroundColor Red
    Write-Host "Please check the name and try again." -ForegroundColor Red
    return
  }
}

Write-Host "Building HTML files"

# Loop through all the channels
for ($i = 0; $i -lt $Channels.Count; $i++) {
  Write-Host "Channel $($i+1)/$($Channels.Count)"
  $ChannelName = $Channels[$i].name
  $ChannelCreator = $UserFromID.($Channels[$i].id)
  $ChannelTopic = $Channels[$i].topic.value
  $ChannelPurpose = $Channels[$i].purpose.value
  $DestinationFolder = Join-Path $Destination $ChannelName
  $AttachmentFolder = Join-Path $DestinationFolder 'files'
  $HTMLFile = Join-Path $DestinationFolder 'index.html'
  $ChatFiles = Get-ChildItem -Path (Join-Path $ExportDirectory.FullName $Channels[$i].name) | Sort-Object -Property Name
  Write-Verbose "Channel: $ChannelName"

  if (-not (Test-Path $DestinationFolder)) {
    New-Item -ItemType Directory -Path $DestinationFolder | Out-Null
  }

  if (-not (Test-Path $AttachmentFolder)) {
    New-Item -ItemType Directory -Path $AttachmentFolder | Out-Null
  }

  # Loop through all the chat history files
  for ($ii = 0; $ii -lt $ChatFiles.Count; $ii++) {
    $ChatData = Get-Content $ChatFiles[$ii].FullName | ConvertFrom-Json

    if ($ii -eq 0) { Get-HTMLHead | Set-Content -Path $HTMLFile }

    Get-HTMLDaySeparator -Day $ChatFiles[$ii].BaseName | Add-Content -Path $HTMLFile

    # Loop through all the messages in each chat file
    for ($iii = 0; $iii -lt $ChatData.Count; $iii++) {
      $MessageDate = ($Epoch.AddSeconds($ChatData[$iii].ts)).ToString('H:M tt')
      $MessageText = $ChatData[$iii].text
      $MessageSubType = $ChatData[$iii].subtype
      $Files = $ChatData[$iii].files
      $FilesHTML = @()

      # If there is a subtype, username has some differences
      if ($MessageSubType -eq 'bot_message') { $MessageUser = $ChatData[$iii].username }
      elseif ($MessageSubType -eq 'file_comment') { $MessageUser = '' }
      else { $MessageUser = $UserFromID.($ChatData[$iii].user) }

      # Check for any specially formatted text
      $FormattedText = ($MessageText | Select-String -Pattern '<(.*?)>' -AllMatches).Matches
      for ($i = 0; $i -lt $FormattedText.Count; $i++) {
        switch -regex ($FormattedText[$i].Groups[1].Value) {
          # Channel links
          '^#(C.*)' {
            $Replacement = '<span class="mention">@' + $ChannelFromID[$Matches[1]] + '</span>'
            break
          }
          # User mentions
          '^@(U.*)' {
            $ID = $Matches[1] -split "\|"
            if ($ID.Count -gt 1) { $Name = $ID[1] }
            else { $Name = $UserFromID[$ID] }
            $Replacement = '<span class="mention">@' + $Name + '</span>'
            break
          }
          # Special mentions
          '^!(.*)' {
            $Replacement = '<span class="mention">@' + $Matches[1] + '</span>'
            break
          }
          # Links with alternative text
          '(.*)\|(.*)' {
            $Replacement = '<a href="' + $Matches[1] + '">' + $Matches[2] + '</a>'
            break
          }
          # If it doesn't match above, it's a link
          Default {
            $Replacement = '<a href="' + $FormattedText[$i].Groups[1].Value + '">' + $FormattedText[$i].Groups[1].Value + '</a>'
          }
        }

        $MessageText = $MessageText.Replace($FormattedText[$i].Groups[0].Value, $Replacement)
      }

      # Formatting
      $MessageText = $MessageText.Replace("`n",'<br />')

      # Get files
      if ($Files) {
        for ($j = 0; $j -lt $Files.Count; $j++) {
          $File = $Files[$j]
          $AttachmentFile = Join-Path $AttachmentFolder $File.name
          if (-not (Test-Path $AttachmentFile) -and $File.mode -ne "external") {
            try {
              $WebClient.DownloadFile($File.url_private_download, $AttachmentFile)
            }
            catch {
              Write-Host "Error downloading file:" $File.title
            }
          }

          $FilesHTML += Get-HTMLFile -Title $File.title -Size (Format-FileSize $File.size) -Type $File.filetype
        }
      }

      Get-HTMLMessage -Username $MessageUser -Date $MessageDate -Message $MessageText -Type $MessageSubType -Files $FilesHTML | Add-Content -Path $HTMLFile
    }
  }
}

Write-Host "Done!" -ForegroundColor Green