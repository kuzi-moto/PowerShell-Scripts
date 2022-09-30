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
        [ValidateSet("admin_api_key", "directory_id", "domain", "email", 'organization_id', "scim_api_key", "user_api_token")]
        [string[]]$Property,
        [string]$Path = "$PSScriptRoot\config.json"
    )

    $ReturnObj = @{}

    try {
        $File = Get-Content -Path $Path -ErrorAction Stop
        $Config = $File | ConvertFrom-Json -ErrorAction Stop
    }
    catch { throw }

    for ($i = 0; $i -lt $Property.Count; $i++) {

        [string]$PropertyName = $Property[$i]

        if ($Config.$Property) {
            $ReturnObj.$PropertyName = $Config.$PropertyName
        }
        else {
            switch ($PropertyName) {
                'admin_api_key' {
                    $NewValue = Read-Host "Enter your Atlassian Admin API key (https://support.atlassian.com/organization-administration/docs/manage-an-organization-with-the-admin-apis/)"
                    break
                }
                'directory_id' {
                    $NewValue = Read-Host "Enter the directory_id for your identity provider. `nThis can be found in the group called All members for directory - <directory_id>"
                    break
                }
                'domain' {
                    $NewValue = Read-Host "Enter your Atlassian Cloud domain (https://<your-domain>.atlassian.net)"
                    break
                }
                'email' {
                    $NewValue = Read-Host "Enter your Atlassian Cloud email address"
                    break
                }
                'organization_id' {
                    $NewValue = Read-Host "Enter the id for your organization. Can be found in the Admin URL: https://admin.atlassian.com/o/<organization_id>/overview"
                    break
                }
                'scim_api_key' {
                    $NewValue = Read-Host "Enter your SCIM API key for your IdP connection (https://developer.atlassian.com/cloud/admin/user-provisioning/rest/intro/) `nNote, this is separate from your Cloud admin API key"
                    break
                }
                'user_api_token' {
                    $NewValue = Read-Host "Enter your Atlassian Cloud API token"
                    break
                }
                Default { throw "Unhandled property $_" }
            }

            $ReturnObj.$PropertyName = $NewValue
            $Config | Add-Member -NotePropertyName $PropertyName -NotePropertyValue $NewValue
            Save-AtlassianConfig $Config

        } # End else

    } # End for loop

    if ($Property.Count -eq 1) {
        return $ReturnObj.$Property
    }
    else {
        return $ReturnObj
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
        [ValidateSet("Admin", "User", "SCIM")]
        [string]$ApiType,
        [string]$Method = "Get",
        [string]$ApiVersion = 3
    )

    Add-Type -AssemblyName System.Web

    $Headers = @{
        "Content-Type" = "application/json"
    }

    switch ($ApiType) {
        "Admin" {
            $Uri = "https://api.atlassian.com/$Request"
            $Headers.Authorization = "Bearer $(Get-AtlassianConfig 'admin_api_key')"
            break
        }
        "SCIM" {
            $Uri = "https://api.atlassian.com/$Request"
            $Headers.Authorization = "Bearer $(Get-AtlassianConfig 'scim_api_key')"
            break
        }
        "User" {
            $Config = Get-AtlassianConfig "domain", "email", "user_api_token"
            $Uri = "https://$($Config.domain).atlassian.net/rest/api/$ApiVersion/$Request"
            $Headers.Authorization = "Basic $(Get-AtlassianAuthHeader $Config.email $Config.user_api_token)"
            break
        }
        Default { throw "Unhandled API type $_" }
    }

    $NVCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)

    foreach ($Key in $QueryParameters.Keys) {
        $NVCollection.Add($Key, $QueryParameters.$Key)
    }

    $UriRequest = [System.UriBuilder]$Uri
    $UriRequest.Query = $NVCollection.ToString()

    try {
        $Response = Invoke-WebRequest -Uri $UriRequest.Uri.OriginalString -Headers $Headers -Method $Method -UseBasicParsing -ErrorAction Stop
    }
    catch { throw }

    switch ($Response.StatusCode) {
        200 { return ($Response.Content | ConvertFrom-Json); break }
        204 { return $true; break }
        Default { Write-Warning "Unhandled status code: $($Response.StatusCode). Description: $($Response.StatusDescription)" }
    }

    return $null

}

### Atlassian User Provisioning REST API functions

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

    $DirectoryID = Get-AtlassianConfig "directory_id"

    switch -regex ($User) {
        # id
        # Searching by the id provides a user object so it can be returned right away.
        '^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$' {
            Invoke-AtlassianApiRequest "scim/directory/$DirectoryID/Users/$User" -ApiType "SCIM"
            return
        }
        # externalId
        '^\d{2}\w{15}\dx\d$' {
            $ScimList = Invoke-AtlassianApiRequest "scim/directory/$DirectoryID/Users" @{'filter' = "externalId eq `"$User`"" } -ApiType "SCIM"
        }
        # userName
        '^.+?@.+?$' {
            $ScimList = Invoke-AtlassianApiRequest "scim/directory/$DirectoryID/Users" @{'filter' = "userName eq `"$User`"" } -ApiType "SCIM"
        }
        Default {
            throw "Entry doesn't seem to match id, externalId, or userName formats. This could also be a bug in the regex."
        }
    }

    switch ($ScimList.totalResults) {
        0 { throw "No accounts found" }
        1 { Return $ScimList.Resources }
        Default { throw "Multiple accounts found" }
    }

}

function Disable-AtlassianIdpDirectoryUser {

    param (
        [Parameter(Mandatory = $true)]
        [string]$UserId)

    Invoke-AtlassianApiRequest "scim/directory/$(Get-AtlassianConfig "directory_id")/Users/$UserId" -Method "Delete" -ApiType "SCIM"

}

function Get-AllAtlassianIdpDirectoryUsers {

    param ($StartIndex = 1)

    $ScimList = Invoke-AtlassianApiRequest "scim/directory/$(Get-AtlassianConfig "directory_id")/Users" @{'startIndex' = $StartIndex } -ApiType "SCIM"
    $ScimList.Resources

    if ($StartIndex + $ScimList.itemsPerPage -lt $ScimList.totalResults) {
        Get-AllAtlassianIdpDirectoryUsers ($StartIndex + $ScimList.itemsPerPage)
    }

}

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

function Get-AllAtlassianDirectoryUsers {
    param($Next)

    $UserList = Invoke-AtlassianApiRequest "admin/v1/orgs/$(Get-AtlassianConfig "organization_id")/users" @{cursor = $Next } -ApiType "Admin"
    $UserList.data

    if ($UserList.links.next -match 'cursor=(.+?)$') {
        Get-AllAtlassianDirectoryUsers ($Iteration + 1) $Matches[1]
    }

}

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

    $DirectoryID = Get-AtlassianConfig "directory_id"

    $StartIndex = 1
    do {
        $Accounts = Invoke-AtlassianApiRequest "scim/directory/$DirectoryID/Users" @{'startIndex' = $StartIndex } -ApiType "Cloud"
        $Account = $Accounts.Resources | Where-Object { $_.DisplayName -match "$userName" }
        $StartIndex += 100
    } until ($Account)

    switch ($ScimList.totalResults) {
        0 { throw "No accounts found" }
        1 { Return $ScimList.Resources }
        Default { throw "Multiple accounts found" }
    }

}