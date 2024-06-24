### Configuration File Operations
function Get-AtlassianConfig {
    <#
    .SYNOPSIS
        Returns the values for the specified Atlassian configuration properties.
    .DESCRIPTION
        Returns a value if only one property is specified otherwise it will
        return a hashtable of the names and values when multiple properties
        are requested.
    .NOTES
        Available values:
        * admin_api_key
        * cloud_id
        * cloud_session_toekn
        * directory_id
        * domain
        * email
        * organization_id
        * scim_api_key
        * user_api_token
    .LINK
        Specify a URI to a help page, this will show when Get-Help -Online is used.
    .EXAMPLE
        Test-MyTestFunction -Verbose
        Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
    #>

    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('admin_api_key', 'cloud_id', 'cloud_session_token', 'directory_id', 'domain', 'email', 'organization_id', 'scim_api_key', 'user_api_token')]
        [string[]]$Properties,
        [switch]$Update,
        [string]$Path = "$PSScriptRoot\config.json"
    )

    $ReturnObj = @{}

    if (-not (Test-Path $Path)) {

        $Config = New-Object -TypeName pscustomobject

    }
    else {

        try {
            $File = Get-Content -Path $Path -ErrorAction Stop
            $Config = $File | ConvertFrom-Json -ErrorAction Stop
        }
        catch { throw }

    }

    foreach ($Property in $Properties) {

        if ($Config.$Property -and -not $Update) {

            $ReturnObj.$Property = $Config.$Property

        }
        else {

            switch ($Property) {
                'admin_api_key' {
                    $NewValue = Read-Host 'Enter your Atlassian Admin API key (https://support.atlassian.com/organization-administration/docs/manage-an-organization-with-the-admin-apis/)'
                    break
                }
                'cloud_id' {
                    $NewValue = Read-Host "Enter your Atlassian site Cloud ID.`nThis can be found by going to https://admin.atlassian.com/, manage users for a product, and get the id from the URL: https://admin.atlassian.com/s/<CLOUD-ID>/users"
                    break
                }
                'cloud_session_token' {
                    Write-Host "Copy your cloud.session.token cookie.`nThis can be obtained from your browser cookies for the site https://admin.atlassian.com"
                    $null = Read-Host "Press `"Enter`" when you have copied the token to extract from the system clipboard. The string can be too long to enter fully in the shell.`nThis only works for Windows, and Linux with xclip."
                    $NewValue = Get-Clipboard
                    break
                }
                'directory_id' {
                    $NewValue = Read-Host "Enter the directory_id for your identity provider. `nThis can be found in the group called All members for directory - <directory_id>"
                    break
                }
                'domain' {
                    $NewValue = Read-Host 'Enter your Atlassian Cloud domain (https://<your-domain>.atlassian.net)'
                    break
                }
                'email' {
                    $NewValue = Read-Host 'Enter your Atlassian Cloud email address'
                    break
                }
                'organization_id' {
                    $NewValue = Read-Host 'Enter the id for your organization. Can be found in the Admin URL: https://admin.atlassian.com/o/<organization_id>/overview'
                    break
                }
                'scim_api_key' {
                    $NewValue = Read-Host "Enter your SCIM API key for your IdP connection (https://developer.atlassian.com/cloud/admin/user-provisioning/rest/intro/) `nNote, this is separate from your Cloud admin API key"
                    break
                }
                'user_api_token' {
                    $NewValue = Read-Host 'Enter your Atlassian Cloud personal API token'
                    break
                }
                Default { throw "Unhandled property $_" }
            }

            if ($NewValue) {
                $ReturnObj.$Property = $NewValue
                $Config | Add-Member -NotePropertyName $Property -NotePropertyValue $NewValue -Force
                Save-AtlassianConfig $Config
            }
            else {
                throw 'No value provided.'
            }
        }

    } # End foreach

    if ($Properties.Count -eq 1) {
        $ReturnObj.($Properties[0])
    }
    else {
        $ReturnObj
    }

}

function Save-AtlassianConfig {
    param (
        $Config,
        [string] $Path = "$PSScriptRoot\config.json"
    )

    try {
        $File = $Config | ConvertTo-Json -ErrorAction Stop
        $File | Set-Content -Path $Path -ErrorAction Stop
    }
    catch { throw }

}

### Interating with the API

function Get-AtlassianAuthHeader {

    param (
        [string]$email,
        [string]$token
    )

    $Text = "$email`:$token"
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $EncodedText = [Convert]::ToBase64String($Bytes)

    return $EncodedText

}

function Invoke-AtlassianApiRequest {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Request,

        [hashtable]$QueryParameters,

        [ValidateSet(
            'Admin',
            'AdminUI',
            'Assets',
            'Confluence',
            'Generic',
            'JiraEmail',
            'SCIM',
            'ServiceDesk',
            'User'
        )]
        [string]$ApiType = 'User',

        [ValidateSet('GET', 'POST', 'DELETE')]
        [string]$Method = 'GET',

        [hashtable]$Body,

        [string]$ApiVersion
    )

    Add-Type -AssemblyName System.Web

    if (-not $AtlassianRateLimit) {
        $Global:AtlassianRateLimit = @{
            Delay = 0
            Last  = $null
        }
    }
    elseif ($AtlassianRateLimit.Last) {
        if ((Get-Date).AddMinutes(-10) -gt $AtlassianRateLimit.Last) {
            $Global:AtlassianRateLimit.Delay = 0
            $Global:AtlassianRateLimit.Last = $null
        }
    }

    $RequestParameters = @{
        Headers            = @{ContentType = 'application/json' }
        Method             = $Method
        UseBasicParsing    = $true
        ErrorAction        = 'stop'
        ContentType        = 'application/json'
        Body               = if ($Body) { $Body | ConvertTo-Json -Depth 10 }
        SkipHttpErrorCheck = $true
    }
    
    do {

        Start-Sleep -Milliseconds $AtlassianRateLimit.Delay
        
        $Retry = $false

        switch ($ApiType) {
            'Admin' {
                $Uri = "https://api.atlassian.com/$Request"
                $RequestParameters.Headers.Authorization = "Bearer $(Get-AtlassianConfig 'admin_api_key')"
                break
            }
            'AdminUI' {
                $Uri = "https://admin.atlassian.com/gateway/api/$Request"
                $WebSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                $WebSession.Cookies.Add((New-Object System.Net.Cookie('cloud.session.token', (Get-AtlassianConfig 'cloud_session_token'), '/', 'admin.atlassian.com')))
                $RequestParameters.WebSession = $WebSession
                $RequestParameters.Headers.Accept = '*/*'
                $RequestParameters.Headers.Origin = 'https://admin.atlassian.com'
                if ($Request -match '^users\/([a-z0-9:\-]+)\/') {
                    # "users/<ID>/manage/api-tokens" requires this header
                    $RequestParameters.Headers.Referer = "https://admin.atlassian.com/o/$(Get-AtlassianConfig 'organization_id')/members/$($Matches[1])"

                    # This API seems to hit the rate-limit very quickly
                    if ($AtlassianRateLimit.Delay -lt 4000) { $Global:AtlassianRateLimit.delay = 4000 }
                }
            }
            'Assets' {
                $Config = Get-AtlassianConfig 'email', 'user_api_token'
                if ($PSBoundParameters.ContainsKey('ApiVersion')) {
                    if ($ApiVersion -notin @('1')) {
                        throw "Only '1' is supported for -Version paramter for '-ApiType Assets'"
                    }
                }
                else { $ApiVersion = '1' }
                $Uri = "https://api.atlassian.com/jsm/assets/workspace/$(Get-JiraAssetsWorkspaceId)/v$ApiVersion/$Request"
                $RequestParameters.Headers.Authorization = "Basic $(Get-AtlassianAuthHeader $Config.email $Config.user_api_token)"
            }
            'Confluence' {
                $Config = Get-AtlassianConfig 'domain', 'email', 'user_api_token'
                if ($PSBoundParameters.ContainsKey('ApiVersion')) {
                    switch ($ApiVersion) {
                        1 {
                            $Uri = "https://$($Config.domain).atlassian.net/wiki/rest/api/$Request"
                            break
                        }
                        2 {
                            $Uri = "https://$($Config.domain).atlassian.net/wiki/api/v2/$Request"
                            break
                        }
                        Default { throw "Unhandled ApiVersion '$ApiVersion' for Confluence ApiType. Accepted values are '1' and '2'." }
                    }
                }
                else { $Uri = "https://$($Config.domain).atlassian.net/wiki/api/v2/$Request" }
                $RequestParameters.Headers.Authorization = "Basic $(Get-AtlassianAuthHeader $Config.email $Config.user_api_token)"
                break
            }
            'Generic' {
                $Config = Get-AtlassianConfig 'domain', 'email', 'user_api_token'
                $Uri = "https://$($Config.domain).atlassian.net/$Request"
                $RequestParameters.Headers.Authorization = "Basic $(Get-AtlassianAuthHeader $Config.email $Config.user_api_token)"
                break
            }
            'SCIM' {
                $Uri = "https://api.atlassian.com/$Request"
                $RequestParameters.Headers.Authorization = "Bearer $(Get-AtlassianConfig 'scim_api_key')"
                break
            }
            'ServiceDesk' {
                $Config = Get-AtlassianConfig 'domain', 'email', 'user_api_token'
                $Uri = "https://$($Config.domain).atlassian.net/rest/servicedeskapi/$Request"
                $RequestParameters.Headers.Authorization = "Basic $(Get-AtlassianAuthHeader $Config.email $Config.user_api_token)"

                # Required as this API is experimental.
                if ($Request -eq 'requesttype') { $RequestParameters.Headers.'X-ExperimentalApi' = 'opt-in' }
                
                break
            }
            'User' {
                $Config = Get-AtlassianConfig 'domain', 'email', 'user_api_token'
                if ($PSBoundParameters.ContainsKey('ApiVersion')) {
                    if ($ApiVersion -notin @('2', '3')) {
                        throw "Version $ApiVersion is not supported for ApiType User."
                    }
                }
                else { $ApiVersion = '3' }
                $Uri = "https://$($Config.domain).atlassian.net/rest/api/$ApiVersion/$Request"
                $RequestParameters.Headers.Authorization = "Basic $(Get-AtlassianAuthHeader $Config.email $Config.user_api_token)"
                break
            }
            'JiraEmail' {
                $Config = Get-AtlassianConfig 'domain', 'email', 'user_api_token'
                $Uri = "https://$($Config.domain).atlassian.net/rest/jira-email-processor-plugin/1.0/mail/audit/process/$Request"
                $RequestParameters.Headers.Authorization = "Basic $(Get-AtlassianAuthHeader $Config.email $Config.user_api_token)"
                break
            }
        }

        $NVCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)

        foreach ($Key in $QueryParameters.Keys) {
            $NVCollection.Add($Key, $QueryParameters.$Key)
        }

        $UriRequest = [System.UriBuilder]$Uri
        $UriRequest.Query = $NVCollection.ToString()
        $UriRequest.Port = -1
        $RequestParameters.Uri = $UriRequest.Uri.OriginalString


        try {
            $Response = Invoke-WebRequest @RequestParameters
            $Global:ResponseDebug = $Response
            if ($Response.Content -match '^<\?xml') {
                $Content = [xml]$Response.Content
            }
            elseif ($Response.Content) {

                if ($Response.Content -is [byte[]]) {
                    # For some reason when querying Assets API without access,
                    # the error response is a byte array.
                    $ResponseContent = [System.Text.Encoding]::UTF8.GetString($Response.Content)
                }
                else {
                    $ResponseContent = $Response.Content
                }

                try {
                    # Some responses come in JSON. Try to convert these first.
                    $Content = $ResponseContent | ConvertFrom-Json -ErrorAction Stop
                }
                catch {
                    $Content = $ResponseContent
                }
                
            }
            else {
                # No content
            }
        }
        catch { throw }

        $Message = `
            if ($Content.context.message) { $Content.context.message } `
            elseif ($Content.context) { $Content.context } `
            elseif ($Content.status.message) { $Content.status.message } `
            elseif ($Content.errorMessages) { $Content.errorMessages } `
            elseif ($Content.detail) { $Content.detail } `
            elseif ($Content.message) { $Content.message }
    
        switch ($Response.StatusCode) {
            # Indicates success, with output
            200 {
                $Content
            }
            # Indicates success, no output
            204 {
                $true
                break
            }
            # Request was successful, but was formed incorrectly
            400 {
                Write-Error "HTTP 400 Bad Request: $Message"
                break
            }
            # Request failed, token is wrong or expired
            401 {
                Write-Warning 'HTTP 401 Unauthorized: Token has likely expired'
                $Retry = $true
                switch ($ApiType) {
                    'Admin' { $null = Get-AtlassianConfig 'admin_api_key' -Update; break }
                    'AdminUI' { $null = Get-AtlassianConfig 'cloud_session_token' -Update; break }
                    'Assets' { $null = Get-AtlassianConfig '' }
                    'SCIM' { $null = Get-AtlassianConfig 'scim_api_key' -Update; break }
                    'User' { $null = Get-AtlassianConfig 'user_api_token' -Update; break }
                    default {
                        $Retry = $false
                        Write-Warning "Unhandled ApiType '$ApiType'"
                    }
                }
                break
            }
            # Forbidden
            403 {
                Write-Error "HTTP 403 Forbidden: $Message"
                break
            }
            # The requested resource does not exist
            404 {
                Write-Warning "HTTP 404: $Message"
                break
            }
            # Rate limited due to too many requests
            429 {
                $Retry = $true
                $NewDelay = if ($AtlassianRateLimit.Delay -eq 0) { 1000 } else { $AtlassianRateLimit.Delay }
                $Global:AtlassianRateLimit.Delay += $NewDelay
                $Global:AtlassianRateLimit.Last = Get-Date
                Write-Warning "Rate limit reached. Set a $($NewDelay*2/1000) second delay"
                break
            }
            Default { $Response; Write-Error "Unhandled status code: $($Response.StatusCode). Description: $($Response.StatusDescription)" }

        }

        if ($AtlassianRateLimit.Delay -gt 0 -and $Response.StatusCode -ne 429 ) {
            $Global:AtlassianRateLimit.Delay -= 1000
        }

    } while ( $Retry -eq $true )
   

    return

}


###########################################
# User Commands / Jira Cloud Platform API #
###########################################

## Announcement banner

## Application roles

### GET/rest/api/3/applicationrole

function Get-JiraAllApplicationRoles {
    $Params = @{
        Request = 'applicationrole'
    }
    # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-application-roles/#api-rest-api-3-applicationrole-get

    Invoke-AtlassianApiRequest @Params
    
}

### GET/rest/api/3/applicationrole/{key}

## Audit records

## Avatars

## Dashboards

### GET  /rest/api/3/dashboard

function Get-JiraAllDashboards {

    $Params = @{
        Request         = 'dashboard'
        QueryParameters = @{
            startAt    = 0
            maxResults = 50
        }
    }

    do {

        $Response = Invoke-AtlassianApiRequest @Params

        $Response.dashboards

        $Params.QueryParameters.startAt = $Response.startAt + $Response.maxResults

    } until ($Params.QueryParameters.startAt -gt $Response.total)

}

### POST /rest/api/3/dashboard
### PUT  /rest/api/3/dashboard/bulk/edit
### GET  /rest/api/3/dashboard/gadgets
### GET  /rest/api/3/dashboard/search
### GET  /rest/api/3/dashboard/{dashboardId}/gadget
### POST /rest/api/3/dashboard/{dashboardId}/gadget
### PUT  /rest/api/3/dashboard/{dashboardId}/gadget/{gadgetId}
### DEL  /rest/api/3/dashboard/{dashboardId}/gadget/{gadgetId}
### GET  /rest/api/3/dashboard/{dashboardId}/items/{itemId}/properties
### GET  /rest/api/3/dashboard/{dashboardId}/items/{itemId}/properties/{propertyKey}
### PUT  /rest/api/3/dashboard/{dashboardId}/items/{itemId}/properties/{propertyKey}
### DEL  /rest/api/3/dashboard/{dashboardId}/items/{itemId}/properties/{propertyKey}
### GET  /rest/api/3/dashboard/{id}
### PUT  /rest/api/3/dashboard/{id}
### DEL  /rest/api/3/dashboard/{id}
### POST /rest/api/3/dashboard/{id}/copy

## Filters

### POST/rest/api/3/filter
### GET/rest/api/3/filter/favourite
### GET/rest/api/3/filter/my
### GET/rest/api/3/filter/search

function Search-JiraFilters {
    param (
        [string]$Filtername,
        [string]$AccountId,
        [string]$GroupName,
        [string]$GroupId,
        [int]$ProjectId,
        [int[]]$ID,
        [ValidateSet('description', '-description', '+description', 'favourite_count', '-favourite_count', '+favourite_count', 'id', '-id', '+id', 'is_favourite', '-is_favourite', '+is_favourite', 'name', '-name', '+name', 'owner', '-owner', '+owner', 'is_shared', '-is_shared', '+is_shared')]
        [string]$OrderBy,
        [int]$StartAt = 0,
        [int]$MaxResults,
        [ValidateSet('description', 'favourite', 'favouritedCount', 'jql', 'owner', 'searchUrl', 'sharePermissions', 'editPermissions', 'isWritable', 'subscriptions', 'viewUrl')]
        [string[]]$Expand,
        [switch]$OverrideSharePermissions
    )

    $Params = @{
        Request         = 'filter/search'
        QueryParameters = @{
            startAt = $StartAt
        }
    }

    if ($PSBoundParameters.ContainsKey('GroupName') -and $PSBoundParameters.ContainsKey('GroupId')) {
        throw "Can't use both -GroupName and -GroupId"
    }

    $PSBoundParameters.Keys | ForEach-Object {

        switch ($_) {
            'Filtername' {
                $Params.QueryParameters.filterName = $PSBoundParameters[$_]
                break
            }
            'AccountId' { $Params.QueryParameters.$_ = $PSBoundParameters[$_] }
            'GroupName' { $Params.QueryParameters.$_ = $PSBoundParameters[$_] }
            'ProjectId' { $Params.QueryParameters.$_ = $PSBoundParameters[$_] }
            'ID' {
                $IDs = $PSBoundParameters[$_]
                if ($IDs.count -gt 1) { $Value = $IDs -join '&id=' } else { $Value = $IDs }
                $Params.QueryParameters.$_ = $value
            }
            'OrderBy' { $Params.QueryParameters.$_ = $PSBoundParameters[$_] }
            'MaxResults' { $Params.QueryParameters.$_ = $PSBoundParameters[$_] }
            'Expand' {
                $Params.QueryParameters.expand = $PSBoundParameters[$_] -join ','
            }
            'OverrideSharePermissions' {
                $Params.QueryParameters.$_ = $true
                break
            }
            Default {}
        }
    }

    Write-Progress -Activity 'Getting filters' -PercentComplete 0

    do {

        $Response = Invoke-AtlassianApiRequest @Params

        $i = $Response.startAt + $Response.maxResults

        Write-Progress -Activity 'Getting filters' -Status "#$i/$($Response.total)" -PercentComplete ($i / $Response.total)

        $Response.values

        $Params.QueryParameters.startAt = $i

    } until ($Response.isLast)

    Write-Progress -Activity 'Getting filters' -Completed

}

### GET/rest/api/3/filter/{id}
### PUT/rest/api/3/filter/{id}
### DEL/rest/api/3/filter/{id}
### GET/rest/api/3/filter/{id}/columns
### PUT/rest/api/3/filter/{id}/columns
### DEL/rest/api/3/filter/{id}/columns
### PUT/rest/api/3/filter/{id}/favourite
### DEL/rest/api/3/filter/{id}/favourite
### PUT/rest/api/3/filter/{id}/owner

## Filter sharing

## Group and user picker

### GET /rest/api/3/groupuserpicker

## Groups

### GET/rest/api/3/group [DEPRECATED] (use group/member)
### POST/rest/api/3/group
### DEL/rest/api/3/group
### GET/rest/api/3/group/bulk [EXPERIMENTAL]

function Get-JiraGroups {
  
    # Returns all groups. If -GroupName is specified returns a result with an exact name match.
    # According to the documentation you should be able to specify multiple names but it
    # doesn't seem to be working.
    
    param (
        [string[]]$GroupName
    )

    $Params = @{
        Request         = 'group/bulk'
        QueryParameters = @{}
    }

    if ($PSBoundParameters.ContainsKey('GroupName')) {
        $Params.QueryParameters.groupName = $GroupName -join '&groupName='
    }

    do {

        $Response = Invoke-AtlassianApiRequest @Params

        $Response.values

        $Params.QueryParameters.startAt = $Response.startAt + $Response.maxResults
        
    } until ($Response.isLast)

}

<# Helper Function #>

function Get-JiraGroupIdFromName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$GroupName
    )

    $Group = Get-JiraGroups $GroupName

    switch ($Group.count) {
        0 {
            Write-Error 'No group found'
            return
        }
        1 {
            $Group.groupId
            return
        }
        Default {
            Write-Error 'Multiple groups found'
            return
        }
    }

}

### GET/rest/api/3/group/member

function Get-JiraGroupMembers {
    param(
        [string]$GroupName
    )

    $Params = @{
        Request         = 'group/member'
        QueryParameters = @{}
    }

    if ($PSBoundParameters.ContainsKey('GroupName')) {
        $Params.QueryParameters.groupname = $GroupName
    }

    do {

        $Response = Invoke-AtlassianApiRequest @Params

        $Response.values

        $Params.QueryParameters.startAt = $Response.startAt + $Response.maxResults
        
    } until ($Response.isLast)
    
}

### POST/rest/api/3/group/user

function Add-AtlassianGroupMember {
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'GroupSet')]
        [string]$Group,

        [Parameter(Mandatory = $true, ParameterSetName = 'GroupNameSet')]
        [string]$GroupName,

        [Parameter(Mandatory = $true, ParameterSetName = 'GroupId')]
        [string]$GroupId,

        [Parameter(Mandatory = $true)]
        [string]$AccountId
    )

    $Params = @{
        Request         = 'group/user'
        Method          = 'POST'
        QueryParameters = @{}
        Body            = @{
            accountId = $AccountId
        }
    }

    if ($PSBoundParameters.ContainsKey('Group')) {

        if ($PSBoundParameters['Group'].ToLower() -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            $GroupId = $PSBoundParameters['Group']
        }
        else {
            $GroupName = $PSBoundParameters['Group']
        }

    }

    if ($GroupId) { $Params.QueryParameters.groupId = $GroupId }
    else { $Params.QueryParameters.groupname = $GroupName }

    $Params | ConvertTo-Json | Out-Host

    Invoke-AtlassianApiRequest @Params

}

### DEL/rest/api/3/group/user

function Remove-AtlassianGroupMember {
    param (
        [Parameter(
            Position = 0,
            Mandatory = $true
        )]
        [string]$AccountId,
        [Parameter(
            Position = 1,
            Mandatory = $true
        )]
        [string]$GroupId
    )
    # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-groups/#api-rest-api-3-group-user-delete

    $Params = @{
        Request         = 'group/user'
        QueryParameters = @{
            accountId = $AccountId
            groupId   = $GroupId
        }
        Method          = 'DELETE'
    }

    Invoke-AtlassianApiRequest @Params
    
}

### GET/rest/api/3/groups/picker

function Search-JiraGroup {
    param(
        [string]$Query
        #[string[]]$Exclude,
        #[string[]]$ExcludeId,
        #[int]$MaxResults
        #[switch]$CaseInsensitive
    )

    $Params = @{
        Request         = 'groups/picker'
        QueryParameters = @{}
    }

    if ($PSBoundParameters.ContainsKey('Query')) {
        $Params.QueryParameters.query = $Query
    }

    Invoke-AtlassianApiRequest @Params

}

## Issues

### GET/rest/api/3/events
### POST/rest/api/3/issue
### PUT/rest/api/3/issue/archive
### POST/rest/api/3/issue/archive
### POST/rest/api/3/issue/bulk
### GET/rest/api/3/issue/createmeta

function Get-JiraCreateIssueMetadata {
    param (
        [ValidateSet('projects.issuetypes.fields')]
        $Expand
    )

    $Params = @{
        Request         = 'issue/createmeta'
        QueryParameters = @{}
    }

    if ($PSBoundParameters.ContainsKey('Expand')) {
        $Params.QueryParameters.expand = $Expand
    }

    Invoke-AtlassianApiRequest @Params
    
}

### GET/rest/api/3/issue/createmeta/{projectIdOrKey}/issueTypes
### PUT/rest/api/3/issue/unarchive
### GET/rest/api/3/issue/{issueIdOrKey}
### PUT/rest/api/3/issue/{issueIdOrKey}

function Edit-JiraIssue {
    param (
        [Parameter(
            Position = 0,
            Mandatory = $true
        )]
        [string]$IssueIdOrKey,
        [string]$Property,
        $Value,
        [string]$Operation,
        [bool]$NotifyUsers = $false
    )
    # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-put

    $QueryParameters = @{
        notifyUsers = $NotifyUsers
    }

    $FunctionParamters = @{
        Request         = "issue/$IssueIdOrKey"
        Method          = 'Put'
        QueryParameters = $QueryParameters
        <#         Body = @{
            update = @{
                $Property = @(
                    @{
                        $Operation = $Value
                    }
                )
            }
        } #>
        Body            = @{
            fields = @{
                $Property = $Value
            }
        }
    }

    Invoke-AtlassianApiRequest @FunctionParamters

}

### DEL/rest/api/3/issue/{issueIdOrKey}
### PUT/rest/api/3/issue/{issueIdOrKey}/assignee
### GET/rest/api/3/issue/{issueIdOrKey}/changelog
### POST/rest/api/3/issue/{issueIdOrKey}/changelog/list
### GET/rest/api/3/issue/{issueIdOrKey}/editmeta

function Get-EditIssueMetadata {
    param (
        [Parameter(Mandatory = $true)]
        [string]$IssueIdOrKey
    )
    # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-editmeta-get
    
    Invoke-AtlassianApiRequest "issue/$IssueIdOrKey/editmeta" | Select-Object -ExpandProperty fields

}

### POST/rest/api/3/issue/{issueIdOrKey}/notify
### GET/rest/api/3/issue/{issueIdOrKey}/transitions
### POST/rest/api/3/issue/{issueIdOrKey}/transitions
### PUT/rest/api/3/issues/archive/export


## UI Modifications (apps)

## Issue attachments

## Issue comments

## Issue comment properties

## Issue fields

### GET /rest/api/3/field

function Get-JiraFields {
    param (
        $id
    )

    $Params = @{
        Request = 'field'
    }

    Invoke-AtlassianApiRequest @Params
    
}

### GET /rest/api/3/field/search

function Get-JiraFieldsPaginated {
    param (
        $id
    )

    $Params = @{
        Request         = 'field/search'
        QueryParameters = @{
            startAt = $null
        }
    }

    Write-Progress -Activity 'Getting fields'

    do {

        $Response = Invoke-AtlassianApiRequest @Params

        $Count = $Params.QueryParameters.startAt
        Write-Progress -Activity 'Getting fields' -Status "#$Count/$($Response.total)" -PercentComplete ($Count / $Response.total * 100)

        $Response.values

        $Params.QueryParameters.startAt = $Response.startAt + $Response.maxResults
        
    } until ($Response.isLast)

    Write-Progress -Activity 'Getting fields' -Completed

}

## Issue field configurations

## Issue custom field contexts

## Issue custom field options

### GET /rest/api/3/customFieldOption/{id}

function Get-JiraCustomFieldOption {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    $Params = @{
        Request = "customFieldOption/$Id"
    }

    Invoke-AtlassianApiRequest @Params
    
}

## Issue custom field options (apps)

## Issue custom field values (apps)

## Issue links

## Issue link types

## Issue Navigator settings

## Issue notification schemes

### GET  /rest/api/3/notificationscheme

<# 
function Get-JiraNotificationSchemes {
    param (
        $StartAt,
        $MaxResults,
        $ID,
        $ProjectID,
        $OnlyDefault,
        $Expand
    )
}
#>

function Get-JiraAllNotificationSchemes {
    param(
        [ValidateSet('all', 'field', 'group', 'notificationSchemeEvents', 'projectRole', 'user')]
        [string[]]$Expand
    )

    $Params = @{
        Request         = 'notificationscheme'
        QueryParameters = @{
            startAt = 0
        }
    }

    if ($PSBoundParameters.ContainsKey('Expand')) {
        $Params.QueryParameters.expand = $Expand -join ','
    }

    do {

        $Response = Invoke-AtlassianApiRequest @Params

        $Response.values

        $Params.QueryParameters.startAt = $Response.startAt + $Response.maxResults
        
    } until ($Response.isLast)
    
}

### POST /rest/api/3/notificationscheme
### GET  /rest/api/3/notificationscheme/project
### GET  /rest/api/3/notificationscheme/{id}
### PUT  /rest/api/3/notificationscheme/{id}
### PUT  /rest/api/3/notificationscheme/{id}/notification
### DEL  /rest/api/3/notificationscheme/{notificationSchemeId}
### DEL  /rest/api/3/notificationscheme/{notificationSchemeId}/notification/{notificationId}

## Issue priorities

## Issue properties

## Issue remote links

## Issue resolutions

## Issue Search

### GET/rest/api/3/issue/picker - Not Implemented
### POST/rest/api/3/jql/match - Not Implemented
### GET/rest/api/3/search

function Search-JiraIssues {
    param (
        [string]$JQL,
        [array]$Fields = '*navigable',
        [array]$Expand,
        [int]$Start = 0,
        [int]$PercentComplete = 0
    )

    # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-search/#api-rest-api-3-search-get

    Write-Progress -Activity 'Getting issues' -Status "Complete: $PercentComplete%" -PercentComplete $PercentComplete

    $IssueList = Invoke-AtlassianApiRequest 'search' @{ jql = $JQL; fields = ($Fields -join ','); expand = ($Expand -join ','); startAt = $Start }

    $IssueList.issues

    $Start += $IssueList.maxResults

    if ($Start -lt $IssueList.total) {
        Search-JiraIssues $JQL $Fields $Expand $Start ($Start / $IssueList.total * 100)
    }
    else {
        Write-Progress -Activity 'Getting issues' -Completed
    }

}

### POST/rest/api/3/search - Not Implemented

## Issue security level

### GET /rest/api/3/issuesecurityschemes/{issueSecuritySchemeId}/members
### GET /rest/api/3/securitylevel/{id}

function Get-JiraIssueSecurityLevel {
    param (
        [int]$ID
    )

    $Params = @{
        Request = "securitylevel/$ID"
    }

    Invoke-AtlassianApiRequest @Params
    
}

## Issue security Schemes

### GET  /rest/api/3/issuesecurityschemes

function Get-JiraAllIssueSecuritySchemes {

    $Params = @{
        Request = 'issuesecurityschemes'
    }

    Invoke-AtlassianApiRequest @Params | Select-Object -ExpandProperty issueSecuritySchemes

}

### POST /rest/api/3/issuesecurityschemes
### GET  /rest/api/3/issuesecurityschemes/level

function Get-JiraAllIssueSecurityLevels {

    $Params = @{
        Request         = 'issuesecurityschemes/level'
        QueryParameters = @{
            startAt = 0
        }
    }

    do {

        $Response = Invoke-AtlassianApiRequest @Params

        $Response.values

        $Params.QueryParameters.startAt = $Response.startAt + $Response.maxResults
        
    } until ($Response.isLast)
    
}
### PUT  /rest/api/3/issuesecurityschemes/level/default
### GET  /rest/api/3/issuesecurityschemes/level/member

function Get-JiraAllIssueSecurityLevelMembers {
    $Params = @{
        Request         = 'issuesecurityschemes/level/member'
        QueryParameters = @{
            startAt = 0
        }
    }

    do {

        $Response = Invoke-AtlassianApiRequest @Params

        $Response.values

        $Params.QueryParameters.startAt = $Response.startAt + $Response.maxResults
        
    } until ($Response.isLast)

}

### GET  /rest/api/3/issuesecurityschemes/project
### PUT  /rest/api/3/issuesecurityschemes/project
### GET  /rest/api/3/issuesecurityschemes/search
### GET  /rest/api/3/issuesecurityschemes/{id}

function Get-JiraIssueSecurityScheme {
    param (
        [int]$ID
    )

    $Params = @{
        Request = "issuesecurityschemes/$ID"
    }

    Invoke-AtlassianApiRequest @Params
    
}

### PUT  /rest/api/3/issuesecurityschemes/{id}
### DEL  /rest/api/3/issuesecurityschemes/{schemeId}
### PUT  /rest/api/3/issuesecurityschemes/{schemeId}/level
### PUT  /rest/api/3/issuesecurityschemes/{schemeId}/level/{levelId}
### DEL  /rest/api/3/issuesecurityschemes/{schemeId}/level/{levelId}
### PUT  /rest/api/3/issuesecurityschemes/{schemeId}/level/{levelId}/member
### DEL  /rest/api/3/issuesecurityschemes/{schemeId}/level/{levelId}/member/{memberId}

## Issue types

## Issue type schemes

## Issue type screen schemes

## Issue type properties

## Issue Votes

## Issue Watchers

## Issue worklogs

## Issue worklog properties

## Jira expressions

## Jira settings

## JQL

## JQL functions (apps)

## Labels

## License metrics

## Myself

## Permissions

## Permission schemes

### GET/rest/api/3/permissionscheme

function Get-JiraAllPermissionSchemes {
    param (
        [ValidateSet('all', 'field', 'group', 'permissions', 'projectRole', 'user')]
        [string]$Expand
    )
    # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-permission-schemes/#api-rest-api-3-permissionscheme-get

    $Params = @{
        Request = 'permissionscheme'
    }

    if ($PSBoundParameters.ContainsKey('Expand')) {
        $Params.QueryParameters = @{
            expand = $Expand
        }
    }

    (Invoke-AtlassianApiRequest @Params).permissionSchemes

}

### POST/rest/api/3/permissionscheme
### GET/rest/api/3/permissionscheme/{schemeId}

function Get-JiraPermissionScheme {
    param (
        [Parameter(
            Position = 0,
            Mandatory = $true
        )]
        [int]$SchemeId,
        [ValidateSet('all', 'field', 'group', 'permissions', 'projectRole', 'user')]
        [string]$Expand
    )
    # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-permission-schemes/#api-rest-api-3-permissionscheme-get

    $Params = @{
        Request = "permissionscheme/$SchemeId"
    }

    if ($PSBoundParameters.ContainsKey('Expand')) {
        $Params.QueryParameters = @{
            expand = $Expand
        }
    }

    Invoke-AtlassianApiRequest @Params

}

### PUT/rest/api/3/permissionscheme/{schemeId}
### DEL/rest/api/3/permissionscheme/{schemeId}
### GET/rest/api/3/permissionscheme/{schemeId}/permission

function Get-JiraPermissionSchemeGrant {
    param (
        [string]$SchemeId
    )
    # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-permission-schemes/#api-rest-api-3-permissionscheme-schemeid-permission-get

    $Params = @{
        Request         = "permissionscheme/$SchemeId/permission"
        QueryParameters = @{
            expand = 'group'
        }
    }

    Invoke-AtlassianApiRequest @Params
    
}

### POST /rest/api/3/permissionscheme/{schemeId}/permission
### GET  /rest/api/3/permissionscheme/{schemeId}/permission/{permissionId}
### DEL  /rest/api/3/permissionscheme/{schemeId}/permission/{permissionId}

## Projects

### GET  /rest/api/3/project [DEPRECATED]
### POST /rest/api/3/project
### GET  /rest/api/3/project/recent
### GET  /rest/api/3/project/search

function Get-JiraAllProjects {
    param(
        [ValidateSet('description', 'projectKeys', 'lead', 'issueTypes', 'url', 'insight')]
        [string[]]$Expand
    )

    $Params = @{
        Request         = 'project/search'
        QueryParameters = @{
            startAt = 0
        }
    }

    if ($PSBoundParameters.ContainsKey('Expand')) {
        $Params.QueryParameters.expand = $Expand -join ','
    }

    do {

        $Response = Invoke-AtlassianApiRequest @Params

        $Response.values

        $Params.QueryParameters.startAt = $Response.startAt + $Response.maxResults
        
    } until ($Response.isLast)
}

### GET  /rest/api/3/project/{projectIdOrKey}

function Get-JiraProject {
    param (
        [string]$ProjectIdOrKey,
        [ValidateSet('description', 'projectKeys', 'lead', 'issueTypes', 'url', 'insight', 'permissions')]
        [string[]]$Expand
    )
    
    $Params = @{
        Request = "project/$ProjectIdOrKey"
    }

    Invoke-AtlassianApiRequest @Params

}
### PUT  /rest/api/3/project/{projectIdOrKey}
### DEL  /rest/api/3/project/{projectIdOrKey}
### POST /rest/api/3/project/{projectIdOrKey}/archive
### POST /rest/api/3/project/{projectIdOrKey}/delete
### POST /rest/api/3/project/{projectIdOrKey}/restore
### GET  /rest/api/3/project/{projectIdOrKey}/statuses
### GET  /rest/api/3/project/{projectId}/hierarchy
### GET  /rest/api/3/project/{projectKeyOrId}/notificationscheme

## Project avatars

## Project categories

## Project components

## Project email

## Project features

## Project key and name validation

## Project permission schemes

## Project properties

## Project roles

### GET  /rest/api/3/project/{projectIdOrKey}/role

function Get-JiraProjectRolesforProject {
    param (
        [string]$ProjectIdOrKey
    )

    $Params = @{
        Request = "project/$ProjectIdOrKey/role"
    }

    Invoke-AtlassianApiRequest @Params
    
}

### GET  /rest/api/3/project/{projectIdOrKey}/role/{id}

function Get-JiraProjectRoleForProject {
    param (
        [string]$ProjectIdOrKey,
        [int]$ID
    )

    $Params = @{
        Request = "project/$ProjectIdOrKey/role/$ID"
    }

    Invoke-AtlassianApiRequest @Params

}

### GET  /rest/api/3/project/{projectIdOrKey}/roledetails

function Get-JiraProjectRoleDetails {
    param (
        [string]$ProjectIdOrKey
    )

    $Params = @{
        Request = "project/$ProjectIdOrKey/roledetails"
    }

    Invoke-AtlassianApiRequest @Params
    
}

### GET  /rest/api/3/role

function Get-JiraAllProjectRoles {

    $Params = @{
        Request = 'role'
    }

    Invoke-AtlassianApiRequest @Params

}

### POST /rest/api/3/role
### GET  /rest/api/3/role/{id}
### PUT  /rest/api/3/role/{id}
### POST /rest/api/3/role/{id}
### DEL  /rest/api/3/role/{id}

## Project role actors

## Project types

## Project versions

## Screens

## Screen tabs

## Screen tab fields

## Screen schemes

## Sever info

## Status

## Tasks

## Time tracking

## Users

### GET/rest/api/3/user

function Get-AtlassianUser {
    param (
        [Parameter(
            Position = 0,
            Mandatory = $true
        )]
        [string]$AccountId,
        [Parameter(
            Position = 1
        )]
        [ValidateSet('groups', 'applicationRoles')]
        [string[]]$Expand
    )
    # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-users/#api-rest-api-3-user-get

    $Params = @{
        Request         = 'user'
        QueryParameters = @{
            accountId = $AccountId
        }
    }

    if ($PSBoundParameters.ContainsKey('Expand')) {
        $Params.QueryParameters.expand = $Expand
    }

    Invoke-AtlassianApiRequest @Params
    
}

### POST/rest/api/3/user
### DEL/rest/api/3/user
### GET/rest/api/3/user/bulk
### GET/rest/api/3/user/bulk/migration
### GET/rest/api/3/user/columns
### PUT/rest/api/3/user/columns
### DEL/rest/api/3/user/columns
### GET/rest/api/3/user/email
### GET/rest/api/3/user/email/bulk
### GET/rest/api/3/user/groups
### GET/rest/api/3/users
### GET/rest/api/3/users/search

## User properties

## User search

### GET/rest/api/3/user/assignable/multiProjectSearch
### GET/rest/api/3/user/assignable/search

function Get-JiraAssignableUsers {
    param ([string]$Query, [string]$Project)
    # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-user-search/#api-rest-api-3-user-assignable-search-get

    Invoke-AtlassianApiRequest 'user/assignable/search' @{query = $Query; project = $Project }

}

### GET/rest/api/3/user/permission/search
### GET/rest/api/3/user/picker
### GET/rest/api/3/user/search

function Search-AtlassianUser {
    param (
        [string]$Query
    )
    # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-user-search/#api-rest-api-3-user-search-get

    # Will attempt to match against displayName and emailAddress.

    Invoke-AtlassianApiRequest 'user/search' @{query = $Query }
    
}

### GET/rest/api/3/user/search/query
### GET/rest/api/3/user/search/query/key
### GET/rest/api/3/user/viewissue/search

## Webhooks

## Workflows

### GET  /rest/api/3/workflow [DEPRECATED]
### POST /rest/api/3/workflow [DEPRECATED]
### GET  /rest/api/3/workflow/search

function Get-JiraAllWorkflows {
    param (
        [ValidateSet('transitions', 'transitions.rules', 'transitions.properties', 'statuses', 'statuses.properties', 'default', 'schemes', 'projects', 'hasDraftWorkflow', 'operations')]
        $Expand
    )

    $Params = @{
        Request         = 'workflow/search'
        QueryParameters = @{
            startAt = 0
        }
    }

    if ($PSBoundParameters.ContainsKey('Expand')) {

        $Params.QueryParameters.expand = $Expand -join ','
    
    }

    do {

        $Response = Invoke-AtlassianApiRequest @Params

        $Response.values

        $Params.QueryParameters.startAt = $Response.startAt + $Response.maxResults
        
    } until ($Response.isLast)
    
}

### DEL  /rest/api/3/workflow/{entityId}
### POST /rest/api/3/workflows [EXPERIMENTAL]

function Get-JiraBulkWorkflows {

    $Params = @{
        Request = 'workflows'
        Method  = 'POST'
        Body    = @{
            workflowNames = @('workflow')
        }
    }

    Invoke-AtlassianApiRequest @Params

}

### GET  /rest/api/3/workflows/capabilities
### POST /rest/api/3/workflows/create
### POST /rest/api/3/workflows/create/validation
### POST /rest/api/3/workflows/update
### POST /rest/api/3/workflows/update/validation

## Workflow transition rules

## Workflow schemes

## Wrokflow scheme project associations

## Workflow scheme drafts

## Workflow statuses

## Workflow status categories

## Workflow transition properties

## App properties

## Dynamic modules

## App migration

######################
# END Jira Cloud API #
######################







##################
# Jira Admin Web UI #
##################

function Get-JiraSystemGlobalPermissions {

    $Params = @{
        Request = 'secure/admin/GlobalPermissions!default.jspa'
        ApiType = 'Generic'
    }

    $Response = (Invoke-AtlassianApiRequest @Params) -replace '\n', ''

    # Permissions are contained within a table tag with the id "global_perms"
    $PermissionTable = ($Response | Select-String -Pattern '<table id="global_perms".+?<\/table>').Matches.Value

    $TableBody = ($PermissionTable | Select-String -Pattern '<tbody>.+?<\/tbody>').Matches.Value

    $TableRows = ($TableBody | Select-String -Pattern '<tr>.+?<\/tr>' -AllMatches).Matches.Value

    for ($i = 0; $i -lt $TableRows.Count; $i++) {
        $TableData = ($TableRows[$i] | Select-String -Pattern '<td>.+?<\/td>' -AllMatches).Matches.Value

        # The operation name is contained between a <strong> tag in the first <td> element
        [string]$Operation = ($TableData[0] | Select-String -Pattern '<strong>(.+?)<\/strong>').Matches.Groups[1].Value

        # Groups are contained within <span> tags in the second <td> element
        [array]$GroupList = ($TableData[1] | Select-String -Pattern '<span>(.+?)<\/span>' -AllMatches).Matches | ForEach-Object { $_.Groups[1].Value.Trim() }

        [PSCustomObject]@{
            Operation = $Operation
            Groups    = $GroupList
        }
    }
    
}

function Get-JiraSystemDashboards {
    <#
    .SYNOPSIS
        Gets all the Dashboards available from the Jira System administration web interface.
    .DESCRIPTION
        Gets all the Dashboards available from the Jira System administration web interface.
        Using the official API you can only return the Dashboards that are shared with the
        user that is calling the API. This function scrapes the web page to return all of
        the dashboards in the Jira instance including private ones.
    .NOTES
        This function is dependent on a very specific page structure, should it change
        slightly then it might not work properly.
    .LINK
        
    .EXAMPLE
        Get-JiraSystemDashboards
        Returns all the dashboards in a Jira instance. Mimics the official Atlassian
        dashboard endpoint as much as possible with the information provided.
    #>    

    $Params = @{
        Request         = '/secure/admin/dashboards/ViewSharedDashboards.jspa'
        ApiType         = 'Generic'
        QueryParameters = @{
            Search        = 'search'
            view          = 'search'
            pagingOffset  = 0
            contentOnly   = $true
            sortColumn    = 'name'
            showTrashList = $false
        }
    }

    do {

        $Response = [System.Web.HttpUtility]::HtmlDecode(((Invoke-AtlassianApiRequest @Params) -replace '\n', ''))

        $Table = ($Response | Select-String -Pattern '<table id="pp_browse".+?<\/table>').Matches.Value

        # It appears the HTML is malformed and tbody doesn't have the appropriate closing '/'
        $Body = ($Table | Select-String -Pattern '<tbody>.+?<\/?tbody>').Matches.Value

        $Rows = ($Body | Select-String -Pattern '<tr.+?<\/tr>' -AllMatches).Matches.Value

        for ($i = 0; $i -lt $Rows.Count; $i++) {

            $Id = ($Rows[$i] | Select-String -Pattern 'id="pp_(\d+)"' -AllMatches).Matches.Groups[1].Value
            [array]$Data = ($Rows[$i] | Select-String -Pattern '<td.+?<\/td>' -AllMatches).Matches.Value
            $Name = ($Data[0] | Select-String -Pattern '<span data-field="name">(.+?)<\/span>').Matches.Groups[1].Value.Trim()
            $Owner = ($Data[1] | Select-String -Pattern '<span data-field="owner">(.+?)<\/span>').Matches.Groups[1].Value.Trim()
            $ShareListMatch = $Data[2] | Select-String -Pattern '<ul class="shareList">(.+?)<\/ul>'
            if (!$ShareListMatch) {
                # When a dashboard has 3 or more permissions, they are hidden by default and there is additional markup.
                $ShareListMatch = $Data[2] | Select-String -Pattern '<ul class="shareList" .+?>(.+?)<\/ul>' -AllMatches
                $ShareListMatch.Matches = $ShareListMatch.Matches[1]
            }
            $ShareList = $ShareListMatch.Matches.Groups[1].Value.Trim()
            [array]$ShareListItems = ($ShareList | Select-String -Pattern '<li.+?<\/li>').Matches.Value
            $SharePermissions = @()

            for ($ii = 0; $ii -lt $ShareListItems.Count; $ii++) {
            
                $Title = ($ShareListItems[$ii] | Select-String -Pattern 'title="(.+?)"').Matches.Groups[1].Value.Trim()

                switch -regex ($Title) {
                    'Not shared with any other users' {
                        $SharePermissions += [PSCustomObject]@{ type = 'private' }
                        break
                    }
                    'Shared with logged-in users' {
                        $SharePermissions += [PSCustomObject]@{ type = 'loggedin' }
                        break
                    }
                    'Shared with everyone with permission to browse the ''.+?'' project' {
                        $SharePermissions += [PSCustomObject]@{
                            type    = 'project'
                            project = [PSCustomObject]@{
                                name = ($ShareListItems[$ii] | Select-String -Pattern '''(.+?)''').Matches.Groups[1].Value.Trim()
                            }
                        }
                        break
                    }
                    'Shared with everyone in the project role ''.+?'' for project ''.+?''' {
                        $ShareNames = ($ShareListItems[$ii] | Select-String -Pattern '''(.+?)''' -AllMatches).Matches.Groups[1].Value.Trim()
                        $SharePermissions += [PSCustomObject]@{
                            type    = 'project'
                            project = [PSCustomObject]@{
                                name = $ShareNames[1]
                            }
                            role    = [PSCustomObject]@{
                                name = $ShareNames[0]
                            }
                        }
                        break
                    }
                    'Shared with everyone in the ''.+?'' group' {
                        $SharePermissions += [PSCustomObject]@{
                            type  = 'group'
                            group = [PSCustomObject]@{
                                name = ($ShareListItems[$ii] | Select-String -Pattern '''(.+?)''').Matches.Groups[1].Value.Trim()
                            }
                        }
                        break
                    }
                    'Shared with user ''.+?'' \(VIEW\)' {
                        $SharePermissions += [PSCustomObject]@{
                            type = 'user'
                            user = [PSCustomObject]@{
                                name = ($ShareListItems[$ii] | Select-String -Pattern '''(.+?)''').Matches.Groups[1].Value.Trim()
                            }
                        }
                        break
                    }
                    Default { Write-Error "SHARE: coudn't match permission for '$Title'" }
                }

            }

            $EditListMatch = $Data[3] | Select-String -Pattern '<ul class="editList">(.+?)<\/ul>'
            if (!$EditListMatch) {
                # When a dashboard has 3 or more permissions, they are hidden by default and there is additional markup.
                $EditListMatch = $Data[3] | Select-String -Pattern '<ul class="editList" .+?>(.+?)<\/ul>' -AllMatches
                $EditListMatch.Matches = $EditListMatch.Matches[1]
            }
            $EditList = $EditListMatch.Matches.Groups[1].Value.Trim()
            [array]$EditListItems = ($EditList | Select-String -Pattern '<li.+?<\/li>').Matches.Value
            $EditPermissions = @()

            for ($ii = 0; $ii -lt $EditListItems.Count; $ii++) {
            
                $Title = ($EditListItems[$ii] | Select-String -Pattern 'title="(.+?)"').Matches.Groups[1].Value.Trim()

                switch -regex ($Title) {
                    'Not shared with any other users' {
                        $EditPermissions += [PSCustomObject]@{ type = 'private' }
                        break
                    }
                    'Shared with logged-in users' {
                        $EditPermissions += [PSCustomObject]@{ type = 'loggedin' }
                        break
                    }
                    'Shared with everyone with permission to browse the ''.+?'' project' {
                        $EditPermissions += [PSCustomObject]@{
                            type    = 'project'
                            project = [PSCustomObject]@{
                                name = ($EditListItems[$ii] | Select-String -Pattern '''(.+?)''').Matches.Groups[1].Value.Trim()
                            }
                        }
                        break
                    }
                    'Shared with everyone in the project role ''.+?'' for project ''.+?''' {
                        $ShareNames = ($EditListItems[$ii] | Select-String -Pattern '''(.+?)''' -AllMatches).Matches.Groups[1].Value.Trim()
                        $EditPermissions += [PSCustomObject]@{
                            type    = 'project'
                            project = [PSCustomObject]@{
                                name = $ShareNames[1]
                            }
                            role    = [PSCustomObject]@{
                                name = $ShareNames[0]
                            }
                        }
                        break
                    }
                    'Shared with everyone in the ''.+?'' group' {
                        $EditPermissions += [PSCustomObject]@{
                            type  = 'group'
                            group = [PSCustomObject]@{
                                name = ($EditListItems[$ii] | Select-String -Pattern '''(.+?)''').Matches.Groups[1].Value.Trim()
                            }
                        }
                        break
                    }
                    'Shared with user ''.+?'' \(EDIT\)' {
                        $EditPermissions += [PSCustomObject]@{
                            type = 'user'
                            user = [PSCustomObject]@{
                                name = ($EditListItems[$ii] | Select-String -Pattern '''(.+?)''').Matches.Groups[1].Value.Trim()
                            }
                        }
                        break
                    }
                    Default { Write-Error "EDIT: coudn't match permission for '$Title'" }
                }

            }

            $Popularity = ($Data[4] | Select-String -Pattern '<td>(.+?)<\/td>').Matches.Groups[1].Value.Trim()

            # Try to match the output from the official API as much as possible
            # with the information that is provided.
            [PSCustomObject]@{
                id               = $Id
                name             = $Name
                owner            = [PSCustomObject]@{ displayName = $Owner }
                sharePermissions = $SharePermissions
                editPermissions  = $EditPermissions
                Popularity       = $Popularity
            }

        }

        # This div only appears when there are more than one page of results.
        $Pagination = ($Response | Select-String -Pattern '<div class="pagination aui-item">.*?</div>').Matches.Value
        if ($Pagination) {

            $PaginationValue = $Pagination | Select-String -Pattern '\d+ - (\d+) of (\d+)'
            [int]$Count = $PaginationValue.Matches.Groups[1].Value
            [int]$Total = $PaginationValue.Matches.Groups[2].Value

            Write-Progress 'Getting Dashboards' -Status "#$Count/$Total" -PercentComplete ($Count / $Total * 100)

            if ($Count -lt $Total) {
                $NextPage = $true
                $PageQueryParameters = ($Pagination | Select-String -Pattern '<a class="icon icon-next" href="ViewSharedDashboards.jspa\?(.+?)"').Matches.Groups[1].Value -split '&'

                for ($i = 0; $i -lt $PageQueryParameters.Count; $i++) {
                    $NameValuePair = $PageQueryParameters[$i] -split '='
                    $Params['QueryParameters'][$NameValuePair[0]] = $NameValuePair[1]
                }

            }
            else {
                $NextPage = $false
            }

        }
        else {
            $NextPage = $false
            Write-Progress 'Getting Dashboards' -Completed
        }

    }
    while ($NextPage)
   
}

# GET https://sub-domain.atlassian.net/jira/plans/settings/permissions

function Get-JiraAdminAdvancedRoadmapsPermissions {

    $Params = @{
        Request = 'jira/plans/settings/permissions'
        ApiType = 'Generic'
    }

    try {
        $Response = Invoke-AtlassianApiRequest @Params -ErrorAction Stop
    }
    catch { throw }

    # Information is contained within a JSON object in the markup
    $MatchInformation = $Response | Select-String 'window.SPA_STATE=({.+?});'

    if ($null -eq $MatchInformation) {
        throw 'Information not available. Maybe the HTML changed.'
    }
    else {
        $Object = $MatchInformation.Matches.Groups[1].Value | ConvertFrom-Json
    }

    # Returns the following members: 
    # If there are no permissions assigned to the permission, 
    $Object.ARJ_GLOBAL_PERMISSIONS_GRANTED.'arj-granted-permissions'.data.permissions.permissions | Select-Object 'admin', 'user', 'viewer', 'labs', 'team-mgmt'
    
}

function Get-JiraCustomApplications {

    <#
    https://domain.atlassian.net/wiki/plugins/servlet/customize-application-navigator
    Undocumented API for the Application Navigator list.
    Returns an array of objects with the following properties:
     * id
     * url
     * displayName
     * applicationType
     * hide
     * editable
     * allowedGroups
     * sourceApplicationUrl
     * sourceApplicationName
     * self
    #>
    
    $Params = @{
        Request = 'rest/custom-apps/1.0/customapps/list' #?_=1701312375445
        ApiType = 'Generic'
    }

    Invoke-AtlassianApiRequest @Params
    
}

function Get-JiraCustomFieldConfiguration {
    param (
        [Parameter(Mandatory = $true)]
        $Id
    )

    $Params = @{
        Request         = 'secure/admin/ConfigureCustomField!default.jspa'
        ApiType         = 'Generic'
        QueryParameters = @{
            customFieldId = $Id
        }
    }

    $Response = (Invoke-AtlassianApiRequest @Params) -replace '\n', ''

    $Response
    
}


<# Helper Function #>

function Get-AtlassianUserGroups {
    param (
        [Parameter(
            Position = 0,
            Mandatory = $true
        )]
        [string]$AccountId
    )

    try {
        (Get-AtlassianUser $AccountId groups).groups.items
    }
    catch { throw }
    
}



#################################
# Jira Service Management Cloud #
#################################

## Assets

### GET /rest/servicedeskapi/assets/workspace

function Get-JiraAssetsWorkspaces {

    $Params = @{
        Request = 'assets/workspace'
        ApiType = 'ServiceDesk'
    }

    Invoke-AtlassianApiRequest @Params
    
}

function Get-JiraAssetsWorkspaceId {
    <# Helper Function #>
    # Meant to return a single workspace ID, and throw an error if not.

    $Response = Get-JiraAssetsWorkspaces

    switch ($Response.size) {
        0 { throw 'No workspaces found' }
        1 {
            $Response.values[0].workspaceId
            break
        }
        Default { throw 'Multiple workspaces found' }
    }

}

## Customer

## Info

## Knowledgebase

## Organization

## Request

## Requesttype

### GET/rest/servicedeskapi/requesttype [Experimental]

function Get-JiraRequestType {

    param (
        [string]$SearchQuery,
        [int]$ServiceDeskId,
        [int]$Start = 0,
        [int]$Limit = 50,
        [string[]]$Expand
    )

    $Params = @{
        Request         = 'requesttype'
        ApiType         = 'ServiceDesk'
        QueryParameters = @{
            start = $Start
            limit = $Limit
        }
    }

    $Response = Invoke-AtlassianApiRequest @Params

    $Response.values

    if ($Response.isLastPage -eq $false) {

        $Params.Start = $Start + $Response.size
        Get-JiraRequestType @Params

    }

}

## Servicedesk

### GET/rest/servicedeskapi/servicedesk

function Get-AtlassianServiceDesks {

    $Params = @{
        Request = 'servicedesk'
        ApiType = 'ServiceDesk'
    }

    Invoke-AtlassianApiRequest @Params | Select-Object -ExpandProperty values

}

### GET/rest/servicedeskapi/servicedesk/{serviceDeskId}

function Get-AtlassianServiceDeskById {
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [string]$ServiceDeskId
    )

    $Params = @{
        Request = "servicedesk/$ServiceDeskId"
        ApiType = 'ServiceDesk'
    }

    Invoke-AtlassianApiRequest @Params | Select-Object -ExpandProperty values

}

### POST/rest/servicedeskapi/servicedesk/{serviceDeskId}/attachTemporaryFile
### GET/rest/servicedeskapi/servicedesk/{serviceDeskId}/customer
### POST/rest/servicedeskapi/servicedesk/{serviceDeskId}/customer
### DEL/rest/servicedeskapi/servicedesk/{serviceDeskId}/customer
### GET/rest/servicedeskapi/servicedesk/{serviceDeskId}/knowledgebase/article
### GET/rest/servicedeskapi/servicedesk/{serviceDeskId}/queue
### GET/rest/servicedeskapi/servicedesk/{serviceDeskId}/queue/{queueId}
### GET/rest/servicedeskapi/servicedesk/{serviceDeskId}/queue/{queueId}/issue
### GET/rest/servicedeskapi/servicedesk/{serviceDeskId}/requesttype

function Get-AtlassianRequestTypes {
    <# 
        This allows you to get all of the request types for a JSM project.
        You can provide a project key or the service desk ID when using the
        `-ServiceDeskId` paramter for easy use.
    #>
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [string]$ServiceDeskId,

        [Parameter(
            Position = 1
        )]
        [int]$Start = 0,

        [string]$SearchQuery
    )

    # https://developer.atlassian.com/cloud/jira/service-desk/rest/api-group-servicedesk/#api-rest-servicedeskapi-servicedesk-servicedeskid-requesttype-get

    if ($ServiceDeskId -notmatch '^\d+$') {
        $SDList = Get-AtlassianServiceDesks

        $ProjectByKey = $SDList | Where-Object { $_.projectKey -eq $ServiceDeskId }

        if (!$ProjectByKey) {

            $ProjectByName = $SDList | Where-Object { $_.projectName -like "*$ServiceDeskId*" }

            if ($ProjectByName.count -gt 1) {
                $ProjectByName | Select-Object id, projectId, projectKey | Out-Host
                Write-Warning 'Found more than one service desk. Use the id or projectKey.'
                return
            }

            $ServiceDeskId = $ProjectByName.id

        }
        else {
            $ServiceDeskId = $ProjectByKey.id
        }
    }

    $Params = @{
        Request         = "servicedesk/$ServiceDeskId/requesttype"
        ApiType         = 'ServiceDesk'
        QueryParameters = @{
            start = $Start
        }
    }

    if ($PSBoundParameters.ContainsKey('SearchQuery')) {

        $Params.QueryParameters.searchQuery = $SearchQuery

    }

    $Response = Invoke-AtlassianApiRequest @Params

    $Response.values

    if ($Response.isLastPage -eq $false) {
        Get-AtlassianRequestTypes $ServiceDeskId ($Start + $Response.size)
    }
    
}

### POST/rest/servicedeskapi/servicedesk/{serviceDeskId}/requesttype
### GET/rest/servicedeskapi/servicedesk/{serviceDeskId}/requesttype/{requestTypeId}
### DEL/rest/servicedeskapi/servicedesk/{serviceDeskId}/requesttype/{requestTypeId}
### GET/rest/servicedeskapi/servicedesk/{serviceDeskId}/requesttype/{requestTypeId}/field
### GET/rest/servicedeskapi/servicedesk/{serviceDeskId}/requesttype/{requestTypeId}/property
### GET/rest/servicedeskapi/servicedesk/{serviceDeskId}/requesttype/{requestTypeId}/property/{propertyKey}
### PUT/rest/servicedeskapi/servicedesk/{serviceDeskId}/requesttype/{requestTypeId}/property/{propertyKey}
### DEL/rest/servicedeskapi/servicedesk/{serviceDeskId}/requesttype/{requestTypeId}/property/{propertyKey}
### GET/rest/servicedeskapi/servicedesk/{serviceDeskId}/requesttypegroup

function Get-AtlassianRequestTypeGroups {
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [string]$ServiceDeskId,

        [Parameter(
            Position = 1
        )]
        [int]$Start = 0
    )

    if ($ServiceDeskId -notmatch '^\d+$') {
        $SDList = Get-AtlassianServiceDesks

        $ProjectByKey = $SDList | Where-Object { $_.projectKey -eq $ServiceDeskId }

        if (!$ProjectByKey) {

            $ProjectByName = $SDList | Where-Object { $_.projectName -like "*$ServiceDeskId*" }

            if ($ProjectByName.count -gt 1) {
                $ProjectByName | Select-Object id, projectId, projectKey | Out-Host
                Write-Warning 'Found more than one service desk. Use the id or projectKey.'
                return
            }

            $ServiceDeskId = $ProjectByName.id

        }
        else {
            $ServiceDeskId = $ProjectByKey.id
        }
    }

    $Params = @{
        Request = "servicedesk/$ServiceDeskId/requesttypegroup"
        ApiType = 'ServiceDesk'
    }

    $Response = Invoke-AtlassianApiRequest @Params

    $Response.values

    if ($Response.isLastPage -eq $false) {
        Get-AtlassianRequestTypeGroups $ServiceDeskId ($Start + $Response.size)
    }

}



###################
# Assets REST API #
###################

function Get-AssetsObjectSchemas {
    
    $Params = @{
        Request         = 'objectschema/list'
        ApiType         = 'Assets'
        QueryParameters = @{
            startAt = $null
        }
    }

    do {

        try {
            # If you do not have access to Assets, command will fail.
            $Response = Invoke-AtlassianApiRequest @Params -ErrorAction Stop
        }
        catch {
            throw
        }

        $i = $Response.startAt + $Response.maxResults

        $Response.values

        $Params.QueryParameters.startAt = $i

    } until ($Response.isLast -or $null)

}

function Get-AssetsObjectSchemaRoles {
    <#
    Gets the list of roles for an Object Schema.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [int]$SchemaId,

        [string]$WorkspaceId = (Get-JiraAssetsWorkspaceId)
    )

    $Params = @{
        Request = "gateway/api/jsm/assets/workspace/$WorkspaceId/v1/config/role/objectschema/$SchemaId"
        ApiType = 'Generic'
    }

    try {
        <#
        Returns a custom object where each role is a property and the value is a
        URL which can be used to retrieve the role's information.
        Properties:
            * Object Schema Developers
            * Object Schema Users
            * Object Schema Developers
        Value example: https://<domain>.atlassian.net/gateway/api/jsm/insight/workspace/<Workspace guid>/v1/config/role/1
        #>
        $Response = Invoke-AtlassianApiRequest @Params -ErrorAction Stop
    }
    catch { throw }

    $Response | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {
        # Transform the output from Atlassian for easier use.
        [pscustomobject]@{
            name = $_
            url  = $Response.$_
            id   = ($Response.$_ | Select-String 'role\/(\d+)').Matches[0].Groups[1].Value
        }
    }

}

function Get-AssetsRole {
    # Returns a role's name, id, description, and actors.
    # Get the ID by using Get-AssetsObejctSchemaRoles
    param (
        [Parameter(Mandatory = $true)]
        [string]$RoleId,

        [string]$WorkspaceId = (Get-JiraAssetsWorkspaceId)
    )

    $Params = @{
        Request = "gateway/api/jsm/insight/workspace/$WorkspaceId/v1/config/role/$RoleId"
        ApiType = 'Generic'
    }

    Invoke-AtlassianApiRequest @Params

}



##############################
# User provisioning REST API #
##############################

## Users

### GET   /scim/directory/{directoryId}/Users/{userId}

function Get-AtlassianIdpDirectoryUser {
    <#
    .SYNOPSIS
        Gets a user from a SCIM directory.
    .DESCRIPTION
        Gets a user from the directory using the id, userName, or
        externalId. It will attempt to guess the input type and will return
        a custom object containing the user's properties.
    .NOTES
        Atlassian has two types of directories. A local directory, and an
        identity provider directory. This function concerns the latter.

        User properties explained:

        id: Unique identifier defined by Atlassian SCIM Service. In OKTA this
            is the "External Id" in the Atlassian Cloud user assignment.

        userName: Unique identifier defined by the provisioning client. In OKTA
            this value is the "User Name" in the Atlassian Cloud user assignment.

        externalId: Identifier defined by provisioning client. This field is
            case-sensitive. Unsure where this value can be located.
    .LINK
        https://developer.atlassian.com/cloud/admin/user-provisioning/rest/api-group-users/#api-scim-directory-directoryid-users-userid-get
    .EXAMPLE
        Get-AtlassianIdpDirectoryUser john.smith@example.com
        Will attempt to search by userName for john.smith@example.com in the directory.
    #>

    param (
        [string]$User
    )

    $DirectoryID = Get-AtlassianConfig 'directory_id'

    switch -regex ($User) {
        # id
        # Searching by the id provides a user object so it can be returned right away.
        '^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$' {
            Invoke-AtlassianApiRequest "scim/directory/$DirectoryID/Users/$User" -ApiType 'SCIM'
            return
        }
        # externalId
        '^\d{2}\w{15}\dx\d$' {
            $ScimList = Invoke-AtlassianApiRequest "scim/directory/$DirectoryID/Users" @{'filter' = "externalId eq `"$User`"" } -ApiType 'SCIM'
        }
        # userName
        '^.+?@.+?$' {
            $ScimList = Invoke-AtlassianApiRequest "scim/directory/$DirectoryID/Users" @{'filter' = "userName eq `"$User`"" } -ApiType 'SCIM'
        }
        Default {
            throw "Entry doesn't seem to match id, externalId, or userName formats. This could also be a bug in the regex."
        }
    }

    switch ($ScimList.totalResults) {
        0 { throw 'No accounts found' }
        1 { Return $ScimList.Resources }
        Default { throw 'Multiple accounts found' }
    }

}
### PUT   /scim/directory/{directoryId}/Users/{userId}
### DEL   /scim/directory/{directoryId}/Users/{userId}

function Disable-AtlassianIdpDirectoryUser {

    param (
        [Parameter(Mandatory = $true)]
        [string]$UserId
    )

    $Params = @{
        Request = "scim/directory/$(Get-AtlassianConfig 'directory_id')/Users/$UserId"
        Method  = 'Delete'
        ApiType = 'SCIM'
    }

    Invoke-AtlassianApiRequest @Params

}

### PATCH /scim/directory/{directoryId}/Users/{userId}
### GET   /scim/directory/{directoryId}/Users

function Find-AtlassianDirectoryUsers {
    <#
    .SYNOPSIS

    .DESCRIPTION

    .NOTES

    .EXAMPLE
        Find-AtlassianDirectoryUsers john.smith@example.com
        Will attempt to search by userName for john.smith@example.com in the directory.
    #>

    # This is under construction

    param (
        [string]$userName,
        [ValidateSet('userName', 'emails', 'displayName')]
        [string]$Attribute
    )

    $DirectoryID = Get-AtlassianConfig 'directory_id'

    $StartIndex = 1
    do {
        $Accounts = Invoke-AtlassianApiRequest "scim/directory/$DirectoryID/Users" @{'startIndex' = $StartIndex } -ApiType 'Cloud'
        $Account = $Accounts.Resources | Where-Object { $_.DisplayName -match "$userName" }
        $StartIndex += 100
    } until ($Account)

    switch ($ScimList.totalResults) {
        0 { throw 'No accounts found' }
        1 { Return $ScimList.Resources }
        Default { throw 'Multiple accounts found' }
    }

}

function Get-AllAtlassianIdpDirectoryUsers {

    param ($StartIndex = 1)

    $ScimList = Invoke-AtlassianApiRequest "scim/directory/$(Get-AtlassianConfig 'directory_id')/Users" @{'startIndex' = $StartIndex } -ApiType 'SCIM'
    $ScimList.Resources

    if ($StartIndex + $ScimList.itemsPerPage -lt $ScimList.totalResults) {
        Get-AllAtlassianIdpDirectoryUsers ($StartIndex + $ScimList.itemsPerPage)
    }

}

### POST  /scim/directory/{directoryId}/Users



## Groups

### GET   /scim/directory/{directoryId}/Groups/{id}
### PUT   /scim/directory/{directoryId}/Groups/{id}
### DEL   /scim/directory/{directoryId}/Groups/{id}
### PATCH /scim/directory/{directoryId}/Groups/{id}
### GET   /scim/directory/{directoryId}/Groups
### POST  /scim/directory/{directoryId}/Groups

## Schemas

### GET /scim/directory/{directoryId}/Schemas
### GET /scim/directory/{directoryId}/Schemas/urn:ietf:params:scim:schemas:core:2.0:User
### GET /scim/directory/{directoryId}/Schemas/urn:ietf:params:scim:schemas:core:2.0:Group
### GET /scim/directory/{directoryId}/Schemas/urn:ietf:params:scim:schemas:extension:enterprise:2.0:User
### GET /scim/directory/{directoryId}/ServiceProviderConfig

## Service Provider Configuration

### GET /scim/directory/{directoryId}/ResourceTypes
### GET /scim/directory/{directoryId}/ResourceTypes/User
### GET /scim/directory/{directoryId}/ResourceTypes/Group


<# function Get-AllAtlassianDirectoryUsers {

    $Accounts = @()
    $Parameters = @{}

    do {
        $UserList = Invoke-AtlassianApiRequest "admin/v1/orgs/$(Get-AtlassianConfig "organization_id")/users" $Parameters -ApiType "Admin"
        $Accounts += $UserList.data
        "$($Accounts.count)" | Out-Host
        if ($UserList.links.next) {
            $UserList.links.next -match 'cursor=(.+?)$'
            $Parameters.cursor = $Matches[1]
        }
    } while ($UserList.links.next)

    return $Accounts

} #>



############################
# User management REST API #
############################

## Manage

### GET /users/{account_id}/manage

## Profile

### GET   /users/{account_id}/manage/profile
### PATCH /users/{account_id}/manage/profile

##  Email

### PUT /users/{account_id}/manage/email

## Api Tokens

### GET /users/{account_id}/manage/api-tokens

function Get-AtlassianUserApiTokens {
    param (
        [string]$AccountId
    )

    try {
        Invoke-AtlassianApiRequest -Request "users/$AccountId/manage/api-tokens"
    }
    catch { throw }

}

### DEL /users/{account_id}/manage/api-tokens/{tokenId}

## Lifecycle

### POST/users/{account_id}/manage/lifecycle/disable

function Disable-AtlassianUser {
    [CmdletBinding()]
    param (
        [string]$AccountId
    )

    $Params = @{
        Request = "users/$AccountId/manage/lifecycle/disable"
        ApiType = 'Admin'
        Method  = 'POST'
    }

    Invoke-AtlassianApiRequest @Params
    
}

### POST/users/{account_id}/manage/lifecycle/enable
### POST/users/{account_id}/manage/lifecycle/delete
### POST/users/{account_id}/manage/lifecycle/cancel-delete




##########################
# Organizations REST API #
##########################

## Orgs

### GET /v1/orgs
### GET /v1/orgs/{orgId}

## Users

### GET /v1/orgs/{orgId}/users

function Get-AllAtlassianDirectoryUsers {
    param($Next, $Count = 0)

    Write-Progress -Activity 'Fetching all directory users' -Status "$Count/??? users"

    $UserList = Invoke-AtlassianApiRequest "admin/v1/orgs/$(Get-AtlassianConfig 'organization_id')/users" @{cursor = $Next } -ApiType 'Admin'
    
    $UserList.data

    if ($UserList.links.next -match 'cursor=(.+?)$') {
        Get-AllAtlassianDirectoryUsers $Matches[1] ($Count + $UserList.data.Count)
    }
    else {
        Write-Progress -Activity 'Fetching all directory users' -Completed
    }

}

## Domains

### GET /v1/orgs/{orgId}/domains
### GET /v1/orgs/{orgId}/domains/{domainId}

## Events

### GET /v1/orgs/{orgId}/events
### GET /v1/orgs/{orgId}/events/{eventId}
### GET /v1/orgs/{orgId}/event-actions

## Policies

### GET  /v1/orgs/{orgId}/policies
### POST /v1/orgs/{orgId}/policies
### GET  /v1/orgs/{orgId}/policies/{policyId}
### PUT  /v1/orgs/{orgId}/policies/{policyId}
### DEL  /v1/orgs/{orgId}/policies/{policyId}
### POST /v1/orgs/{orgId}/policies/{policyId}/resources
### PUT  /v1/orgs/{orgId}/policies/{policyId}/resources/{resourceId}
### DEL  /v1/orgs/{orgId}/policies/{policyId}/resources/{resourceId}
### GET  /v1/orgs/{orgId}/policies/{policyId}/validate

## Directory

### GET  /v1/orgs/{orgId}/directory/users/{accountId}/last-active-dates
### DEL  /v1/orgs/{orgId}/directory/users/{accountId}
### POST /v1/orgs/{orgId}/directory/users/{accountId}/suspend-access
### POST /v1/orgs/{orgId}/directory/users/{accountId}/restore-access
### POST /v1/orgs/{orgId}/directory/groups
### DEL  /v1/orgs/{orgId}/directory/groups/{groupId}
### POST /v1/orgs/{orgId}/directory/groups/{groupId}/memberships
### DEL  /v1/orgs/{orgId}/directory/groups/{groupId}/memberships/{accountId}

## Workspaces

### POST /v2/orgs/{orgId}/workspaces


#######################
# Confluence Cloud V1 #
#######################

## Content restrictions

### GET  /wiki/rest/api/content/{id}/restriction

function Get-ConfluenceContentRestrictions {
    param (
        [string]$Id
    )

    $Params = @{
        Request         = "content/$Id/restriction"
        ApiType         = 'Confluence'
        ApiVersion      = 1
        QueryParameters = @{}
    }

    do {
    
        $Response = Invoke-AtlassianApiRequest @Params

        $Response

        if ($null = $Response._links.next -match ('\/rest\/api\/content\?(.+)')) {
            
            $Matches[1] -split '&' | ForEach-Object {
            
                $NameValuePair = $_ -split '='

                $Params['QueryParameters'][$NameValuePair[0]] = [System.Web.HttpUtility]::UrlDecode($NameValuePair[1])

            }
        }
        else {
            $Params.QueryParameters.next = $false
        }

    } while ($Params.QueryParameters.next)

}

### PUT  /wiki/rest/api/content/{id}/restriction
### POST /wiki/rest/api/content/{id}/restriction

function Add-ConfluenceContentRestrictions {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'read',
            'update'
        )]
        [string]$Operation,

        [string[]]$GroupId,

        [string[]]$UserId
    )

    $Params = @{
        Request    = "content/$Id/restriction"
        Method     = 'POST'
        ApiVersion = 1
        ApiType    = 'Confluence'
        Body       = @{
            results = @(
                @{
                    operation    = $Operation
                    restrictions = @{}
                }
            )
        }
    }

    if (-not $PSBoundParameters.ContainsKey('GroupId') -and -not $PSBoundParameters.ContainsKey('UserId')) {
        Write-Error 'Must use at least one of -GroupId or -UserId'
        return
    }

    if ($PSBoundParameters.ContainsKey('GroupId')) {
        [array]$Params.Body.results[0].restrictions.group = $GroupId | ForEach-Object {
            @{
                type = 'group'
                id   = $_
            }
        }
    }
    if ($PSBoundParameters.ContainsKey('UserId')) {
        [array]$Params.Body.results[0].restrictions.user = $UserId | ForEach-Object {
            @{
                type      = 'user'
                accountId = $_
            }
        }
    }

    Invoke-AtlassianApiRequest @Params

}

### DEL  /wiki/rest/api/content/{id}/restriction
### GET  /wiki/rest/api/content/{id}/restriction/byOperation
### GET  /wiki/rest/api/content/{id}/restriction/byOperation/{operationKey}
### GET  /wiki/rest/api/content/{id}/restriction/byOperation/{operationKey}/group/{groupName}
### PUT  /wiki/rest/api/content/{id}/restriction/byOperation/{operationKey}/group/{groupName}
### DEL  /wiki/rest/api/content/{id}/restriction/byOperation/{operationKey}/group/{groupName}
### GET  /wiki/rest/api/content/{id}/restriction/byOperation/{operationKey}/byGroupId/{groupId}
### PUT  /wiki/rest/api/content/{id}/restriction/byOperation/{operationKey}/byGroupId/{groupId}
### DEL  /wiki/rest/api/content/{id}/restriction/byOperation/{operationKey}/byGroupId/{groupId}
### GET  /wiki/rest/api/content/{id}/restriction/byOperation/{operationKey}/user
### PUT  /wiki/rest/api/content/{id}/restriction/byOperation/{operationKey}/user
### DEL  /wiki/rest/api/content/{id}/restriction/byOperation/{operationKey}/user

## Space permissions

### POST /wiki/rest/api/space/{spaceKey}/permission

function Add-ConfluenceSpacePermission {
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Key')]
        [string]$SpaceKey,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet(
            'administer',
            'archive',
            'copy',
            'create',
            'delete',
            'export',
            'move',
            'purge',
            'purge_version',
            'read',
            'restore',
            'restrict_content',
            'update',
            'use'
        )]
        [string]$Operation,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('TargetType')]
        [ValidateSet(
            'page',
            'blogpost',
            'comment',
            'attachment',
            'space'
        )]
        [string]$Target,

        [string]$GroupId,

        [string]$UserId
    )

    process {

        $Params = @{
            Request    = "space/$SpaceKey/permission"
            Method     = 'POST'
            ApiType    = 'Confluence'
            ApiVersion = 1
            Body       = @{
                subject   = @{
                    type       = ''
                    identifier = ''
                }
                operation = @{
                    key    = $Operation
                    target = $Target
                }
            }
        }
    
        if ($PSBoundParameters.ContainsKey('GroupId') -and $PSBoundParameters.ContainsKey('UserId')) {
            Write-Warning 'Must supply only one of -GroupId, -UserId.'
            return
        }
        elseif ($PSBoundParameters.ContainsKey('GroupId')) {
            $Params.Body.subject.type = 'group'
            $Params.Body.subject.identifier = $GroupId
        }
        elseif ($PSBoundParameters.ContainsKey('UserId')) {
            $Params.Body.subject.type = 'user'
            $Params.Body.subject.identifier = $UserId
        }
        else {
            Write-Warning 'Must supply either -GroupId or -UserId.'
            return
        }
    
        Invoke-AtlassianApiRequest @Params

    }

}

### POST /wiki/rest/api/space/{spaceKey}/permission/custom-content
### DEL  /wiki/rest/api/space/{spaceKey}/permission/{id}

function Remove-ConfluenceSpacePermission {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpaceKey,

        [Parameter(Mandatory = $true)]
        [int64]$Id
    )

    $Params = @{
        Request    = "space/$SpaceKey/permission/$Id"
        ApiType    = 'Confluence'
        ApiVersion = 1
        Method     = 'DELETE'
    }

    Invoke-AtlassianApiRequest @Params

}

#######################
# Confluence Cloud V2 #
#######################

## Attachment

## Ancestors

## Blog Post

## Children

## Comment

## Content

function Get-ConfluenceAllContent {
    # GET /wiki/rest/api/content
    param(
        [ValidateSet(
            'childTypes.all',
            'childTypes.attachment',
            'childTypes.comment',
            'childTypes.page',
            'container',
            'metadata.currentuser',
            'metadata.properties',
            'metadata.labels',
            'metadata.frontend',
            'operations',
            'children.page',
            'children.attachment',
            'children.comment',
            'restrictions.read.restrictions.user',
            'restrictions.read.restrictions.group',
            'restrictions.update.restrictions.user',
            'restrictions.update.restrictions.group',
            'history', 
            'history.lastUpdated',
            'history.previousVersion',
            'history.contributors',
            'history.nextVersion',
            'ancestors',
            'body',
            'body.storage',
            'body.view',
            'version',
            'descendants.page',
            'descendants.attachment',
            'descendants.comment',
            'space',
            'extensions.inlineProperties',
            'extensions.resolution'
        )]
        [string[]]$Expand
    )

    $Params = @{
        Request         = 'content'
        ApiType         = 'Confluence'
        ApiVersion      = 1
        QueryParameters = @{
            limit = 200
        }
    }

    if ($PSBoundParameters.ContainsKey('Expand')) {

        $Params.QueryParameters.expand = $Expand -join ','

    }


    do {

        Write-Progress -Id 0 -Activity 'Gettting content' -Status "#$(if ($Response.start) {$Response.start} else {0})"

        $Response = Invoke-AtlassianApiRequest @Params

        $Response.results

        if ($null = $Response._links.next -match ('\/rest\/api\/content\?(.+)')) {

            $Matches[1] -split '&' | ForEach-Object {

                $NameValuePair = $_ -split '='

                $Params['QueryParameters'][$NameValuePair[0]] = [System.Web.HttpUtility]::UrlDecode($NameValuePair[1])

            }
        }
        else {
            $Params.QueryParameters.next = $false
        }

    } while ($Params.QueryParameters.next)

    Write-Progress -Id 0 -Activity 'Gettting spaces' -Completed

}

## Content Properties

## Custom Content

## Label

## Like

## Operation

## Page

## Space

### GET /spaces
function Get-ConfluenceAllSpaces {
    [CmdletBinding()]
    param(
        [ValidateSet(1, 2)]
        [int]$ApiVersion = 2,
        [string[]]$Expand
    )

    <# DynamicParam {
        if ($ApiVersion -eq '1') {
            $AttributeCollection = [System.Management.Automation.ParameterAttribute]@{
                #Name             = 'Expand'
                ParameterSetName = 'ApiVersion1'
                Mandatory        = $false
                HelpMessage      = 'Valid values: settings, metadata, metadata.labels, operations, lookAndFeel, permissions, icon, description, description.plain, description.view, theme, homepage, history'
                #ValidateSet      = 'settings', 'metadata', 'metadata.labels', 'operations', 'lookAndFeel', 'permissions', 'icon', 'description', 'description.plain', 'description.view', 'theme', 'homepage', 'history'
            }

            $DynParam1 = [System.Management.Automation.RuntimeDefinedParameter]::new(
                'Expand', [string[]], $AttributeCollection
            )
            
            $ParamDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
            $ParamDictionary.Add('Expand', $DynParam1)
            return $paramDictionary
        }
    } #>
    # V1 API: GET /wiki/rest/api/space
    # Added this one because V2 doesn't support expand.

    process {

        $Params = @{
            ApiType         = 'Confluence'
            QueryParameters = @{}
        }

        switch ($ApiVersion) {
            1 {
                $Params.Request = 'space'
                $Params.ApiVersion = 1
                $Params.QueryParameters.limit = 100

                if ($PSBoundParameters.ContainsKey('Expand')) {
                    $Params.QueryParameters.expand = $Expand -join ','
                }

                do {

                    Write-Progress -Id 0 -Activity 'Gettting spaces' -Status "#$(if ($Response.start) {$Response.start} else {0})"
    
                    $Response = Invoke-AtlassianApiRequest @Params
    
                    $Response.results
    
                    if ($null = $Response._links.next -match ('\/rest\/api\/space\?(.+)')) {
                        
                        $Matches[1] -split '&' | ForEach-Object {
                        
                            $NameValuePair = $_ -split '='
        
                            $Params['QueryParameters'][$NameValuePair[0]] = $NameValuePair[1]

                        }
                    }
                    else {
                        $Params.QueryParameters.next = $false
                    }

                } while ($Params.QueryParameters.next)
    
                break
            }
            2 {
                $Params.Request = 'spaces'
                $Params.QueryParameters.limit = 250

                do {
                    $Response = Invoke-AtlassianApiRequest @Params

                    $Response.results
            
                    $Cursor = if ($Response._links.next -match 'cursor=(.+?)(?:$|&)') { $Matches[1] } else { $false }
            
                    $Params.QueryParameters.cursor = $Cursor
            
                } while ($Cursor)
    
                break
            }

        }

        Write-Progress -Id 0 -Activity 'Gettting spaces' -Completed

    }

}
### GET /spaces/{id}

## Space Permissions

## Space Properties

## Task

## User

## Version



#####################
# Confluence Web UI #
#####################


function Get-ConfluenceDefaultSpacePermissions {
    
    $Params = @{
        Request         = 'cgraphql'
        ApiType         = 'Generic'
        Method          = 'POST'
        QueryParameters = @{
            q = 'spacePermissionsDefaults'
        }
        Body            = @{
            operationName = 'spacePermissionsDefaults'
            variables     = @{}
            query         = @'
query spacePermissionsDefaults {
  defaultSpacePermissions {
    editable
    groupsWithDefaultSpacePermissions(first: 25, after: "", filterText: "") {
      nodes {
        subjectKey {
          id
          principalType
          displayName
          __typename
        }
        permissions
        __typename
      }
      __typename
    }
    __typename
  }
}
'@        
        }
    }

    $response = Invoke-AtlassianApiRequest @Params

    $Response.data.defaultSpacePermissions.groupsWithDefaultSpacePermissions.nodes

}

function Get-ConfluenceCustomApplications {

    <#
    https://domain.atlassian.net/wiki/plugins/servlet/customize-application-navigator
    Undocumented API for the Application Navigator list.
    Returns an array of objects with the following properties:
     * id
     * url
     * displayName
     * applicationType
     * hide
     * editable
     * allowedGroups
     * sourceApplicationUrl
     * sourceApplicationName
     * self
    #>
    
    $Params = @{
        Request = 'wiki/rest/custom-apps/1.0/customapps/list'
        ApiType = 'Generic'
    }

    Invoke-AtlassianApiRequest @Params
    
}



#####################
# Admin UI Commands #
#####################


function Revoke-AtlassianProductAccess {
    [CmdletBinding()]
    param (
        [string]$UserId,
        [string]$ProductId
    )

    $Body = @{
        users      = @(
            $UserId
        )
        productIds = @(
            $ProductId
        )
    }

    Invoke-AtlassianApiRequest -Request "adminhub/um/site/$(Get-AtlassianConfig 'cloud_id' )/users/revoke-access" -ApiType AdminUI -Method POST -Body $Body

}

function Get-AtlassianAdminUserApiTokens {
    param (
        [string]$AccountId
    )

    Invoke-AtlassianApiRequest -Request "users/$AccountId/manage/api-tokens" -ApiType AdminUI

}

function Get-AtlassianSessionHeartbeat {

    $Params = @{
        Request = 'session/heartbeat'
        ApiType = 'AdminUI'
        Method  = 'POST'
    }

    Invoke-AtlassianApiRequest @Params
}

function Get-AtlassianAdminLicenses {
    Invoke-AtlassianApiRequest -Request "adminhub/um/site/$(Get-AtlassianConfig 'cloud_id' )/product/licences" -ApiType AdminUI
}

function Get-AtlassianAdminProductUse {
    [CmdletBinding()]
    param()

    try {
        $Response = Invoke-AtlassianApiRequest -Request "adminhub/um/site/$(Get-AtlassianConfig 'cloud_id')/product/access-config/use" -ApiType AdminUI -ErrorAction Stop
    }
    catch { throw }

    $Response | Select-Object -ExpandProperty useAccessConfig
    
}

# GET https://<domain>.atlassian.com/gateway/api/adminhub/um/site/<site ID>/product/access-config/admin

function Get-AtlassianAdminAdminAccess {
    
    
    try {
        $Response = Invoke-AtlassianApiRequest -Request "adminhub/um/site/$(Get-AtlassianConfig 'cloud_id')/product/access-config/admin" -ApiType AdminUI -ErrorAction Stop
    }
    catch { throw }

    $Response | Select-Object -ExpandProperty AdminAccessConfig
    
}

function Get-AtlassianAdminGuestAccess {
    # Allows the ability to view groups that have "Guest access" when browsing Product access on the Atlassian admin interface.
    
    try {
        $Response = Invoke-AtlassianApiRequest -Request "adminhub/um/site/$(Get-AtlassianConfig 'cloud_id')/product/access-config/external-collaborator" -ApiType AdminUI -ErrorAction Stop
    }
    catch { throw }

    $Response | Select-Object -ExpandProperty externalCollaboratorConfig

}

function Get-AtlassianAdminCustomerAccess {
    # Allows the ability to view groups that have "Customer access" when browsing Product access on the Atlassian admin interface.
    
    try {
        $Response = Invoke-AtlassianApiRequest -Request "adminhub/um/site/$(Get-AtlassianConfig 'cloud_id')/product/access-config/helpseeker" -ApiType AdminUI -ErrorAction Stop
    }
    catch { throw }

    $Response | Select-Object -ExpandProperty helpseekerConfig

}

function Get-AtlassianAdminAllGroups {
    param(
        [Parameter(
            Position = 0
        )]
        [int]$StartIndex = 1
    )

    Write-Host "Index: $StartIndex"

    $Params = @{
        Request         = "adminhub/um/site/$(Get-AtlassianConfig 'cloud_id')/groups"
        QueryParameters = @{
            'start-index' = $StartIndex
        }
        ApiType         = 'AdminUI'
    }

    $Response = Invoke-AtlassianApiRequest @Params

    $Response.groups

    $NewIndex = $StartIndex + $Response.groups.count

    if ($NewIndex -lt $Response.total) {
        Get-AtlassianAdminAllGroups $NewIndex
    }
    
}

function Get-AtlassianAdminAllUsers {
    param(
        [Parameter(
            Position = 0
        )]
        [int]$StartIndex = 1,
        [Parameter(
            Position = 1
        )]
        [int]$Total = 1000
    )

    Write-Progress -Activity 'Fetching users' -Status "#$StartIndex/$Total" -PercentComplete ($StartIndex / $Total * 100)

    $Params = @{
        Request         = "adminhub/organization/$(Get-AtlassianConfig 'organization_id')/members"
        QueryParameters = @{
            'start-index' = $StartIndex
        }
        ApiType         = 'AdminUI'
    }

    $Response = Invoke-AtlassianApiRequest @Params

    $Response.users

    $NewIndex = $StartIndex + $Response.users.count

    if ($NewIndex -lt $Response.total) {
        Get-AtlassianAdminAllUsers $NewIndex $Response.total
    }

}

# GET https://<domain>.atlassian.net//gateway/api/automation/internal-api/jira/<cloud id>/pro/rest/GLOBAL/rule/export

function Get-JiraAllAutomationExport {

    $Params = @{
        Request = "gateway/api/automation/internal-api/jira/$(Get-AtlassianConfig 'cloud_id')/pro/rest/GLOBAL/rule/export"
        ApiType = 'Generic'
    }

    Invoke-AtlassianApiRequest @Params | Select-Object -ExpandProperty 'rules'

}

# GET https://<domain>.atlassian.net/gateway/api/automation/internal-api/jira/<cloud id>/pro/rest/GLOBAL/highestUsages

function Get-JiraGlobalAutomationUsage {

    <#
    This function returns the list of automations that appear on the global automation usage page.
    Modified the output slightly, typically the rules details are included in a 'rule' property,
    so I moved them out to make the output easier to work with.
    #>

    param(
        [string]$Month,
        
        [ValidateSet('All products', 'Jira Software', 'Jira Service Management', 'Jira Product Discovery')]
        [string]$Product
    )

    $ProductMap = @{
        'All products'            = ''
        'Jira Software'           = 'JIRA_SOFTWARE'
        'Jira Service Management' = 'JIRA_SERVICE_MANAGEMENT'
        'Jira Product Discovery'  = 'JIRA_PRODUCT_DISCOVERY'
    }

    $Domain = Get-AtlassianConfig domain

    $Params = @{
        Request         = "gateway/api/automation/internal-api/jira/$(Get-AtlassianConfig 'cloud_id')/pro/rest/GLOBAL/highestUsages"
        ApiType         = 'Generic'
        QueryParameters = @{
            limit = 100
        }
    }

    if ($PSBoundParameters.ContainsKey('Month')) {

        if ($PSBoundParameters.'Month' -notmatch '\d{4}-\d{2}') {
            throw "`"$($PSBoundParameters.'Month')`" is not a valid input. Use the format YYYY-MM"
        }

        $Params.QueryParameters.month = $PSBoundParameters.'Month'
    }

    if ($PSBoundParameters.ContainsKey('Product')) {
        $Params.QueryParameters.workspace = $ProductMap[$PSBoundParameters.'Product']
    }

    $Response = Invoke-AtlassianApiRequest @Params

    if ($Response.Count -eq 100) {
        Write-Warning 'Reached the limit of 100 rules, could be missing some.'
    }

    $Response | Select-Object @{l = 'id'; e = { $_.rule.id } }, @{l = 'url'; e = { "https://$Domain.atlassian.net/jira/settings/automation#/rule/$($_.rule.id)" } }, @{l = 'name'; e = { $_.rule.name } }, @{l = 'state'; e = { $_.rule.state } }, @{l = 'ruleScope'; e = { $_.rule.ruleScope } }, @{l = 'authorAccountId'; e = { $_.rule.authorAccountId } }, @{l = 'projects'; e = { $_.rule.projects } }, @{l = 'billingType'; e = { $_.rule.billingType } }, executionCount

}


###################################
### Jira Email Processor Plugin ###
###################################

function Get-JiraEmailLogs {
    param (
        [string]$Channel
    )

    $Params = @{
        Request = "$Channel"
        ApiType = 'JiraEmail'
    }

    Invoke-AtlassianApiRequest @Params

    #$URL = 'https://<domain>.atlassian.net/rest/jira-email-processor-plugin/1.0/mail/audit/process/CHANNEL4f2406546d18?limit=50&page=1&from=1676577481126&_=1680551884393'
    
}

function Get-ConfluenceGlobalGroupWithPermissions {
    # cgraphql?q=SitePermissionsListQuery
    
    $Params = @{
        Request         = 'cgraphql'
        ApiType         = 'Generic'
        Method          = 'POST'
        QueryParameters = @{
            q = 'SitePermissionsListQuery'
        }
        Body            = @{
            operationName = 'SitePermissionsListQuery'
            variables     = @{
                includeGroups                        = $true
                includeUsers                         = $false
                includeAnonymous                     = $false
                includeUnlicensedUserWithPermissions = $false
                first                                = 25
                permissionTypes                      = @(
                    'INTERNAL'
                )
                filterText                           = ''
                operations                           = @()
            }
            #query         = 'query SitePermissionsListQuery($first: Int, $afterGroup: String, $afterUser: String, $filterText: String, $permissionTypes: [SitePermissionType], $operations: [SitePermissionOperationType], $includeGroups: Boolean = true, $includeUsers: Boolean = false, $includeAnonymous: Boolean = false, $includeUnlicensedUserWithPermissions: Boolean = false) {\n  sitePermissions(permissionTypes: $permissionTypes, operations: $operations) {\n    groups(after: $afterGroup, first: $first, filterText: $filterText) @include(if: $includeGroups) {\n      count\n      nodes {\n        id\n        name\n        currentUserCanEdit\n        operations {\n          operation\n          targetType\n          __typename\n        }\n        __typename\n      }\n      pageInfo {\n        endCursor\n        hasNextPage\n        __typename\n      }\n      __typename\n    }\n    users(after: $afterUser, first: $first, filterText: $filterText) @include(if: $includeUsers) {\n      count\n      nodes {\n        accountId\n        displayName\n        profilePicture {\n          path\n          __typename\n        }\n        operations {\n          operation\n          targetType\n          __typename\n        }\n        __typename\n      }\n      pageInfo {\n        endCursor\n        hasNextPage\n        __typename\n      }\n      __typename\n    }\n    anonymous @include(if: $includeAnonymous) {\n      operations {\n        operation\n        targetType\n        __typename\n      }\n      __typename\n    }\n    unlicensedUserWithPermissions @include(if: $includeUnlicensedUserWithPermissions) {\n      operations {\n        operation\n        targetType\n        __typename\n      }\n      __typename\n    }\n    __typename\n  }\n}\n'
            query         = @'
query SitePermissionsListQuery($first: Int, $afterGroup: String, $afterUser: String, $filterText: String, $permissionTypes: [SitePermissionType], $operations: [SitePermissionOperationType], $includeGroups: Boolean = true, $includeUsers: Boolean = false, $includeAnonymous: Boolean = false, $includeUnlicensedUserWithPermissions: Boolean = false) {
    sitePermissions(permissionTypes: $permissionTypes, operations: $operations) {
        groups(after: $afterGroup, first: $first, filterText: $filterText) @include(if: $includeGroups) {
        count
        nodes {
            id
            name
            currentUserCanEdit
            operations {
            operation
            targetType
            __typename
            }
            __typename
        }
        pageInfo {
            endCursor
            hasNextPage
            __typename
        }
        __typename
        }
        users(after: $afterUser, first: $first, filterText: $filterText) @include(if: $includeUsers) {
        count
        nodes {
            accountId
            displayName
            profilePicture {
            path
            __typename
            }
            operations {
            operation
            targetType
            __typename
            }
            __typename
        }
        pageInfo {
            endCursor
            hasNextPage
            __typename
        }
        __typename
        }
        anonymous @include(if: $includeAnonymous) {
        operations {
            operation
            targetType
            __typename
        }
        __typename
        }
        unlicensedUserWithPermissions @include(if: $includeUnlicensedUserWithPermissions) {
        operations {
            operation
            targetType
            __typename
        }
        __typename
        }
        __typename
    }
    }
'@
        
        
        }
    }

    (Invoke-AtlassianApiRequest @Params).data.sitePermissions.groups.nodes

}

function Get-AtlassianCustomAppsList {

    $Params = @{
        Request = 'wiki/rest/custom-apps/1.0/customapps/list'
        ApiType = 'Generic'
    }

    Invoke-AtlassianApiRequest @Params
    
}