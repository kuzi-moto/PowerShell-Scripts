<#
.SYNOPSIS
    A short one-line action-based description, e.g. 'Tests if a function is valid'
.DESCRIPTION
Allows you to determine all of the places a group is being used.

https://jira.atlassian.com/browse/JRACLOUD-71967.NOTES
.LINK
    Specify a URI to a help page, this will show when Get-Help -Online is used.
.EXAMPLE
    Test-MyTestFunction -Verbose
    Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
#>

param (
    [Parameter(
        Position = 0,
        Mandatory = $true,
        ParameterSetName = 'group'
    )]
    [string[]]$Group,

    [Parameter(ParameterSetName = 'all')]
    [switch]$AllGroups,

    [Parameter(ParameterSetName = 'group')]
    [Parameter(ParameterSetName = 'all')]
    [string]$Path,

    [Parameter(ParameterSetName = 'group')]
    [Parameter(ParameterSetName = 'all')]
    [switch]$ResetCache,

    [Parameter(ParameterSetName = 'group')]
    [Parameter(ParameterSetName = 'all')]
    [switch]$Force
)

<# function Get-RecursiveValues($Obj) {
        
    if ($null -eq $Obj) { return }
        
    $objType = $Obj.GetType().Name
        
    switch ($objType) {
        'PSCustomObject' {
            $Obj.PSObject.properties | ForEach-Object {
                Get-RecursiveValues $_.Value
            }
            break
        }
        'Object[]' {
            $Obj | ForEach-Object {
                Get-RecursiveValues $_
            }
            break
        }
        'string' {
            $Obj
            break
        }
        'Int64' {
            return
        }
        'Boolean' {
            return
        }
        'DateTime' {
            return
        }
        Default { Write-Warning "`"$objType`" is not handled. OBJ: $Obj" }
    }
} #>

function Get-RecursiveValues($Obj, [array]$Property) {

    if ($null -eq $Obj) { return }

    switch ($Obj.GetType().Name) {
        'PSCustomObject' {
            $Obj.PSObject.properties | ForEach-Object {
                $Property += $_.Name
                Get-RecursiveValues $_.Value $Property
            }
            break
        }
        'Object[]' {
            $Obj | ForEach-Object {
                Get-RecursiveValues $_ $Property
            }
            break
        }
        'string' {
            [PSCustomObject]@{
                Property = $Property -join '.'
                Value    = $Obj
            }
            return
        }
        'Int64' {
            return
        }
        'Boolean' {
            return
        }
        'DateTime' {
            return
        }
        Default { Write-Warning "`"$objType`" is not handled. OBJ: $Obj" }
    }
}

. $PSScriptRoot\Atlassian_Functions.ps1
$Domain = Get-AtlassianConfig -Properties domain

$AtlassianSections = @(
    #'Site Access'
    #'Default Project Roles'
    #'Jira Global Permissions'
    #'Automations'
    #'Filters'
    #'Dashboards'
    #'Jira Application Navigator'
    #'Advanced Roadmaps'
    'Workflows'
)

if ($PSBoundParameters.ContainsKey('AllGroups')) {
    [array]$Group = Get-JiraGroups | Select-Object -ExpandProperty name
}

for ($i = 0; $i -lt $Group.Count; $i++) {

    $GroupName = $Group[$i]

    Write-Progress -Id 0 -Activity 'Processing Group' -Status "#$($i+1)/$($Group.Count) - $GroupName" -PercentComplete ($i / $Group.Count * 100)
    
    # Validation

    if ($PSBoundParameters.ContainsKey('Path')) {

        if ([System.IO.Path]::HasExtension($Path)) {

            if ($PSBoundParameters.ContainsKey('AllGroups')) {
                Write-Error 'Can only specify directory when using "-AllGroups" parameter.'
                return
            }
            elseif ($PSBoundParameters.Group.Count -gt 1) {
                Write-Error 'Can only specify directory when providing multiple group names.'
                return
            }

            if ([System.IO.Path]::GetExtension($Path) -ne '.json') {
                Write-Error 'Only ".json" is a valid extension.'
                return
            }

            $FileName = [System.IO.Path]::GetFileName($Path)

        }
        else {

            if (-not [System.IO.Path]::EndsInDirectorySeparator($Path)) {
                $Path = [System.IO.Path]::Join($Path, [System.IO.Path]::DirectorySeparatorChar)
            }

            $FileName = "group_$GroupName.json"
        }

        try {
            $DirectoryName = [System.IO.Path]::GetDirectoryName($Path) | Get-Item -ErrorAction Stop | Select-Object -ExpandProperty FullName
        }
        catch {
            Write-Error "`"$($_.Exception.ItemName)`" directory does not exist. Please select a valid directory."
            return
        }

        $OutputPath = Join-Path $DirectoryName $FileName

    }
    else {
        $OutputPath = Join-Path $PSScriptRoot "group_$GroupName.json"
    }

    if ((Test-Path $OutputPath) -and !$PSBoundParameters.ContainsKey('Force')) {
        Write-Error "File `"$OutputPath`" already exists. Use `"-Force`" parameter to overwrite"
        return
    }

    if ($PSBoundParameters.ContainsKey('Group') -and -not (Get-JiraGroups $GroupName)) {
        Write-Error "No group with name `"$GroupName`" found"
        return
    }

    $Global:Report = @{}

    <# 
All the various places we will need to look:
* Atlassian Admin
    * Product Access            ✓
    * Admin Access              ✓
    * Guest Access              ✓
    * Customer Access           ✓
* Jira System
    * Default Project roles     ✓
    * Global Permissions        ✓
    * Automation Rules          ✓
    * Filters (edit/view)       ✓
        * Filter Subscriptions  ✓
    * Dashboards                ✓
    * Application Navigator     ✓
* Jira Products
    * Advanced Roadmaps         ✓
* Jira Issues Admin
    * Workflow Conditions       ✓ (User Is In Any Group, User Is In Group, User Is In Group Custom Field, Value Field?)
    * Workflow Post Function (Update Issue Custom Field, Update Issue Field?)
    * Workflow Validator (Regular Expression Check)
    * Issue Security Schemes    ✓
    * Notification schemes      ✓
    * Permission Schemes        ✓
    * Custom Fields
        * Group Picker default  O
        * Picker fields in use  O - Get all the fields that are a group picker, and find tickets containing the group in those values.
* Jira Projects
    * Roles                     ✓
* Jira Service Management
    * Assets - schema roles     ✓
* Confluence
    * Global Permissions        ✓
    * Default Space Permissions ✓
    * Application Navigator     ✓
    * Spaces                    ✓
        * Pages                 ✓
#>



    for ($j = 0; $j -lt $AtlassianSections.Count; $j++) {

        Write-Progress -Id 1 -ParentId 0 -Activity 'Getting Permissions' -Status "#$j/$($AtlassianSections.Count) - $($AtlassianSections[$i])" -PercentComplete ($j / $AtlassianSections.Count * 100)
        Start-Sleep -Seconds 2
        switch ($AtlassianSections[$j]) {

            'Site Access' {

                $SiteAccess = @{
                    URL = "https://admin.atlassian.com/s/$(Get-AtlassianConfig 'cloud_id')/apps"
                }
                
                ##################
                # PRODUCT ACCESS #
                ##################

                $ProductAccess = @{}

                if ($null -eq $Cache_ProductAccess -or $ResetCache) {
                    $Global:Cache_ProductAccess = Get-AtlassianAdminProductUse
                }

                $Cache_ProductAccess | ForEach-Object {

                    $GroupPermissions = $_.groups | Where-Object { $_.name -eq $GroupName }

                    if ($GroupPermissions) {
                        $ProductAccess[$_.product.productName] = $GroupPermissions | Select-Object 'default'
                    }

                }

                if ($ProductAccess.count -gt 0) {
                    $SiteAccess.'Product Access' = $ProductAccess
                }



                ################
                # ADMIN ACCESS #
                ################

                $AdminAccess = @()

                if ($null -eq $Cache_AdminAccess -or $ResetCache) {
                    $Global:Cache_AdminAccess = Get-AtlassianAdminAdminAccess
                }

                $Cache_AdminAccess | ForEach-Object {

                    $GroupPermissions = $_.groups | Where-Object { $_.name -eq $GroupName }

                    if ($GroupPermissions) {
                        $AdminAccess += $_.product.productName
                    }
                }

                if ($AdminAccess.count -gt 0) {
                    $SiteAccess.'Admin Access' = $AdminAccess
                }



                #####################
                # SITE GUEST ACCESS #
                #####################

                $GuestAccess = @{}

                if ($null -eq $Cache_GuestAccess -or $ResetCache) {
                    $Global:Cache_GuestAccess = Get-AtlassianAdminGuestAccess
                }

                $Cache_GuestAccess | ForEach-Object {

                    $GroupPermissions = $_.groups | Where-Object { $_.name -eq $GroupName }

                    if ($GroupPermissions) {
                        $GuestAccess[$_.product.productName] = $GroupPermissions | Select-Object 'default'
                    }

                }

                if ($GuestAccess.count -gt 0) {
                    $SiteAccess.'Guest Access' = $GuestAccess
                }

                

                ########################
                # SITE CUSTOMER ACCESS #
                ########################

                if ($null -eq $Cache_CustomerAccess -or $ResetCache) {
                    $Global:Cache_CustomerAccess = Get-AtlassianAdminCustomerAccess
                }

                $CustomerAccess = @{}

                $Cache_CustomerAccess | ForEach-Object {

                    $GroupPermissions = $_.groups | Where-Object { $_.name -eq $GroupName }

                    if ($GroupPermissions) {
                        $CustomerAccess[$_.product.productName] = $GroupPermissions | Select-Object 'default'
                    }

                }

                if ($CustomerAccess.count -gt 0) {
                    $Report.'Customer Access' = $CustomerAccess
                }

                if ($SiteAccess.count -gt 1) {
                    $Report.'Site Access' = $SiteAccess
                }

                break
            }

            'Default Project Roles' {

                #########################
                # DEFAULT PROJECT ROLES #
                #########################

                $DefaultProjectRole = @()

                if ($null -eq $Cache_AllProjectRoles -or $ResetCache) {
                    $Global:Cache_AllProjectRoles = Get-JiraAllProjectRoles
                }

                $Cache_AllProjectRoles | ForEach-Object {

                    if ($_.actors.actorGroup.name -eq $GroupName) {
                        $DefaultProjectRole += $_.name
                    }

                }

                if ($DefaultProjectRole) {
                    $Report.'Default Project Roles' = $DefaultProjectRole
                }

                break
            }
        
            'Jira Global Permissions' {

                ###########################
                # JIRA GLOBAL PERMISSIONS #
                ###########################

                $JiraGlobalPermissions = @{
                    URL         = "https://$Domain.atlassian.net/secure/admin/GlobalPermissions!default.jspa"
                    Permissions = @()
                }

                if ($null -eq $Cache_JiraSystemGlobalPermissions -or $ResetCache) {
                    $Global:Cache_JiraSystemGlobalPermissions = Get-JiraSystemGlobalPermissions
                }

                foreach ($Item in $Cache_JiraSystemGlobalPermissions) {
                    if ($Item.Groups -contains $GroupName) {
                        $JiraGlobalPermissions.Permissions += $Item.Operation
                    }
                }

                if ($JiraGlobalPermissions.Permissions.Count -gt 0) {
                    $Report.'Jira Global Permissions' = $JiraGlobalPermissions
                }

                break
            }

            'Automations' {

                ###############
                # AUTOMATIONS #
                ###############

                $Automations = @()

                if ($null -eq $Cache_Automation -or $ResetCache) {
                    $Global:Cache_Automation = Get-JiraAllAutomationExport
                }

                for ($ii = 0; $ii -lt $Cache_Automation.Count; $ii++) {

                    if ((Get-RecursiveValues $Cache_Automation[$ii]).Value -contains $GroupName) {

                        $URL = "https://$Domain.atlassian.net/jira/settings/automation#/rule/$($Cache_Automation[$ii].id)"

                        $Automations += $Cache_Automation[$ii] | Select-Object id, name, @{l = 'URL'; e = { $URL } }

                    }

                }

                if ($Automations.count -gt 0) {
                    $Report.Automations = $Automations
                }

                break
            }

            'Filters' {

                ###########
                # FILTERS #
                ###########

                if ($null -eq $Cache_Filters -or $ResetCache) {
                    $Global:Cache_Filters = Search-JiraFilters -OverrideSharePermissions -Expand sharePermissions, editPermissions, subscriptions
                }

                $FilterPermissions = @()

                for ($ii = 0; $ii -lt $Cache_Filters.Count; $ii++) {

                    $Permissions = $()

                    $EditPermission = $Cache_Filters[$ii].editPermissions | Where-Object { $_.group.name -eq $GroupName }
                    $SharePermission = $Cache_Filters[$ii].sharePermissions | Where-Object { $_.group.name -eq $GroupName }
                    $ShareSubscription = $Cache_Filters[$ii].subscriptions | Where-Object { $_.group.name -eq $GroupName }

                    if ($EditPermission) { $Permissions += 'EDIT' }
                    if ($SharePermission) { $Permissions += 'SHARE' }
                    if ($ShareSubscription) { $Permissions += 'SUBSCRIPTION' }
                    if ($Permissions) {
                        $FilterPermissions += [PSCustomObject]@{
                            id          = $Cache_Filters[$ii].id
                            name        = $Cache_Filters[$ii].name
                            permissions = $Permissions
                            URL         = "https://$Domain.atlassian.net/issues/?filter=$($Cache_Filters[$ii].id)"
                        }
                    }

                }

                if ($FilterPermissions) { $Report.Filters = $FilterPermissions }

                break
            }

            'Dashboards' {

                ##############
                # DASHBOARDS #
                ##############

                $Dashboards = @{
                    URL         = "https://$Domain.atlassian.net/secure/admin/dashboards/ViewSharedDashboards.jspa"
                    Permissions = @()
                }

                if ($null -eq $Cache_Dashboards -or $ResetCache) {
                    $Global:Cache_Dashboards = Get-JiraAllDashboards -Expand sharePermissions, editPermissions, subscriptions
                }

                for ($ii = 0; $ii -lt $Cache_Dashboards.Count; $ii++) {

                    $Permissions = $()

                    $EditPermission = $Cache_Dashboards[$ii].editPermissions | Where-Object { $_.group.name -eq $GroupName }
                    $SharePermission = $Cache_Dashboards[$ii].sharePermissions | Where-Object { $_.group.name -eq $GroupName }

                    if ($EditPermission) { $Permissions += 'EDIT' }
                    if ($SharePermission) { $Permissions += 'SHARE' }
                    if ($Permissions) {
                        $Dashboards.Permissions += @{
                            id          = $Cache_Dashboards[$ii].id
                            name        = $Cache_Dashboards[$ii].name
                            permissions = $Permissions
                            URL         = "https://$Domain.atlassian.net/jira/dashboards/$($Cache_Dashboards[$ii].id)"
                        }
                    }

                }

                if ($Dashboards.Permissions.Count -gt 0) { $Report.Dashboards = $Dashboards }

                break
            }

            'Jira Application Navigator' {

                ##############################
                # JIRA APPLICATION NAVIGATOR #
                ##############################

                $JiraCustomApps = [pscustomobject]@{
                    URL          = "https://$Domain.atlassian.net/plugins/servlet/customize-application-navigator"
                    applications = @()
                }

                if ($null -eq $Cache_JiraCustomApps -or $ResetCache) {
                    $Global:Cache_JiraCustomApps = Get-JiraCustomApplications
                }

                for ($ii = 0; $ii -lt $Cache_JiraCustomApps.Count; $ii++) {
                    if ($Cache_JiraCustomApps[$ii].allowedGroups -contains $GroupName) {
                        $JiraCustomApps.applications += $Cache_JiraCustomApps[$ii] | Select-Object id, url, displayName
                    }
                }

                if ($JiraCustomApps.applications.Count -gt 0) {
                    $Report.'Confluence Custom Apps' = $JiraCustomApps
                }

                break
            }

            'Advanced Roadmaps' {

                #####################
                # ADVANCED ROADMAPS #
                #####################

                Write-Progress -Id 1 -ParentId 0 -Activity 'Advanced Roadmaps'

                $AdvancedRoadmaps = @{
                    URL         = "https://$Domain.atlassian.net/jira/plans/settings/permissions"
                    Permissions = @()
                }

                if ($null -eq $Cache_AdvancedRoadmaps -or $ResetCache) {
                    $Global:Cache_AdvancedRoadmaps = Get-JiraAdminAdvancedRoadmapsPermissions
                }

                $PermissionList = $Cache_AdvancedRoadmaps | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

                foreach ($Permission in $PermissionList) {
                    if ($Cache_AdvancedRoadmaps.$Permission -contains $GroupName) {
                        $AdvancedRoadmaps.Permissions += $Permission
                    }
                }

                if ($AdvancedRoadmaps.Permissions.Count -gt 0) {
                    $Report.'Advanced Roadmaps' = $AdvancedRoadmaps
                }

                Write-Progress -Id 1 -ParentId 0 -Activity 'Advanced Roadmaps' -Completed

                break
            }

            'Workflows' {

                #############
                # WORKFLOWS #
                #############

                $Workflows = @{}

                if ($null -eq $Cache_Workflows -or $ResetCache) {
                    $Global:Cache_Workflows = Get-JiraAllWorkflows -Expand transitions.rules
                }

                for ($ii = 0; $ii -lt $Cache_Workflows.Count; $ii++) {

                    $Workflow = @{
                        URL         = "https://$Domain.atlassian.net/secure/admin/workflows/ViewWorkflowSteps.jspa?workflowMode=live&workflowName=$([System.Web.HttpUtility]::UrlEncode($Cache_Workflows[$ii].id.name))"
                        Transitions = @()
                    }

                    $Cache_Workflows[$ii].transitions | ForEach-Object {

                        $Category = @()

                        Get-RecursiveValues $_ | Where-Object { $_.Value -eq $Group } | ForEach-Object {

                            switch ($_.Property) {
                                # Condition -  User is in group
                                'id.name.description.from.to.type.rules.conditionsTree.nodeType.type.configuration.group' {

                                }
                                Default { Write-Warning "Unhandled property: $_"}
                            }

                        }

                        if ($Category.Count -gt 0) {
                            $Workflow.Transitions += $_ | Select-Object 'id', 'name', @{l='category';e={$Category | Select-Object -Unique}}
                        }

                        #if ($_.rules.conditionsTree.configuration.group -eq $GroupName -or $_.rules.conditionsTree.conditions.configuration.group -eq $GroupName) {
                        #    $Workflow.Transitions += $_ | Select-Object 'id', 'name'
                        #}

                    }

                    if ($Workflow.Transitions.count -gt 0) {
                        $Workflows[$Cache_Workflows[$ii].id.name] = $Workflow
                    }

                }

                if ($Workflows.count -gt 0) {
                    $Report.'Workflows' = $Workflows
                }

                break
            }

        }

    }

    <#
    ##########################
    # PROJECT ISSUE SECURITY #
    ##########################

    Write-Progress -Id 1 -ParentId 0 -Activity 'Getting Jira Issue Security'

    $IssueSecurity = @{}

    if ($null -eq $Cache_IssueSecurityLevelMembers -or $ResetCache) {
        $Global:Cache_IssueSecurityLevelMembers = Get-JiraAllIssueSecurityLevelMembers
    }

    if ($null -eq $Cache_SecuritySchemes -or $ResetCache) {
        $Global:Cache_SecuritySchemes = @{}
    }

    if ($null -eq $Cache_SecurityLevels -or $ResetCache) {
        $Global:Cache_SecurityLevels = @{}
    }

    for ($ii = 0; $ii -lt $Cache_IssueSecurityLevelMembers.Count; $ii++) {

        if ($Cache_IssueSecurityLevelMembers[$ii].holder.parameter -ne $GroupName) {
            continue
        }

        $SecuritySchemeId = $Cache_IssueSecurityLevelMembers[$ii].issueSecuritySchemeId
        $SecurityLevelId = $Cache_IssueSecurityLevelMembers[$ii].issueSecurityLevelId

        if (-not $Cache_SecuritySchemes.$SecuritySchemeId) {
            $Cache_SecuritySchemes.$SecuritySchemeId = Get-JiraIssueSecurityScheme $SecuritySchemeId
        }

        $SecurityScheme = $Cache_SecuritySchemes.$SecuritySchemeId.name

        if (-not $Cache_SecurityLevels.$SecurityLevelId) {
            $Cache_SecurityLevels.$SecurityLevelId = Get-JiraIssueSecurityLevel $SecurityLevelId
        }

        if (-not $IssueSecurity.$SecurityScheme) {
            $URL = "https://$Domain.atlassian.net/secure/admin/EditIssueSecurities!default.jspa?schemeId=$SecuritySchemeId"
            $IssueSecurity.$SecurityScheme = $Cache_SecuritySchemes.$SecuritySchemeId | Select-Object id, description, @{l = 'URL'; e = { $URL } }, @{l = 'levels'; e = { , @() } }
        }

        $IssueSecurity.$SecurityScheme.levels += $Cache_SecurityLevels.$SecurityLevelId | Select-Object id, description, name

    }

    if ($IssueSecurity.Count -gt 0) {
        $Report.IssueSecurity = $IssueSecurity
    }

    Write-Progress -Id 1 -ParentId 0 -Activity 'Getting Jira Issue Security' -Completed



    ########################
    # NOTIFICATION SCHEMES #
    ########################

    Write-Progress -Id 1 -ParentId 0 -Activity 'Getting Notification Schemes'

    $NotificationScheme = @{}

    if ($null -eq $Cache_NotificationSchemes -or $ResetCache) {
        $Global:Cache_NotificationSchemes = Get-JiraAllNotificationSchemes -Expand group
    }

    for ($ii = 0; $ii -lt $Cache_NotificationSchemes.Count; $ii++) {

        $Events = @()

        $Cache_NotificationSchemes[$ii].notificationSchemeEvents | ForEach-Object {

            if ($_ | Where-Object { $_.notifications.parameter -eq $GroupName }) {

                $Events += $_.event.name

            }

        }

        if ($Events) {

            $NotificationScheme.($Cache_NotificationSchemes[$ii].name) = $Events

        }

    }

    if ($NotificationScheme.Count -gt 0) {
        $Report.NotificationScheme = $NotificationScheme
    }

    Write-Progress -Id 1 -ParentId 0 -Activity 'Getting Notification Schemes' -Completed



    ######################
    # PERMISSION SCHEMES #
    ######################

    Write-Progress -Id 1 -ParentId 0 'Getting Jira Permission Schemes'

    if ($null -eq $Cache_PermissionSchemes -or $ResetCache) {
        $Global:Cache_PermissionSchemes = Get-JiraAllPermissionSchemes -All -Expand 'group'
    }

    foreach ($scheme in $Cache_PermissionSchemes) {
        $Permissions = @()

        foreach ($grant in $scheme.permissions) {
    
            if ($grant.holder.parameter -eq $GroupName) {
                $Permissions += $grant.permission
            }

        }

        if ($Permissions.count -gt 0) {
    
            if (!$Report.PermissionScheme) { $Report.PermissionScheme = @{} }

            $Report.PermissionScheme.($scheme.name) = $Permissions

        }

    }

    Write-Progress -Id 1 -ParentId 0 'Getting Jira Permission Schemes' -Completed



    #################
    # PROJECT ROLES #
    #################

    Write-Progress -Id 1 -ParentId 0 -Activity 'Getting Jira Project Roles'

    $ProjectRolePermissions = @()

    # List of all projects
    if ($null -eq $Cache_Projects -or $ResetCache) {
        [array]$Global:Cache_Projects = Get-JiraAllProjects
    }

    for ($ii = 0; $ii -lt $Cache_Projects.Count; $ii++) {
        # Go through each project

        Write-Progress -Id 2 -ParentId 1 -Activity 'Projects' -Status "status: #$($ii+1)/$($Cache_Projects.Count)" -PercentComplete (($ii + 1) / $Cache_Projects.Count * 100)

        $ProjectKey = $Cache_Projects[$ii].key
        $FoundRoles = @()

        # Get the list of roles for the project
        if ($null -eq $Cache_Projects[$ii].roles) {
            $Cache_Projects[$ii] | Add-Member -NotePropertyName 'roles' -NotePropertyValue @{}
            # Convert the custom object to a hashtable.
            $RolesForProject = Get-JiraProjectRolesforProject $ProjectKey
            $RolesForProject | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {
                $Cache_Projects[$ii].roles.$_ = @{
                    id = [string]($RolesForProject.$_ | Select-String -Pattern '(\d+)$').Matches.Groups[0].Value
                }
            }
    
            [array]$RolesList = $RolesTable.Keys
        }
        else {
            [array]$RolesList = $Cache_Projects[$ii].roles.Keys
        }

        for ($iii = 0; $iii -lt $RolesList.Count; $iii++) {
            # Go through each role

            Write-Progress -ParentId 2 -Id 3 -Activity 'Roles' -Status "status: #$($iii+1)/$($RolesList.Count)" -PercentComplete ($iii / $RolesList.Count * 100)

            $RoleName = $RolesList[$iii]

            # Get the role details to determine actors
            if ($null -eq $Cache_Projects[$ii].roles.$RoleName.actors) {
                $RoleDetails = Get-JiraProjectRoleForProject -ProjectIdOrKey $ProjectKey -ID $Cache_Projects[$ii].roles.$RoleName.id
                $Cache_Projects[$ii].roles.$RoleName = $RoleDetails
            }
            else {
                $RoleDetails = $Cache_Projects[$ii].roles.$RoleName
            }

            if ($RoleDetails | ForEach-Object { $_.actors | Where-Object { $_.actorGroup.name -eq $GroupName } }) {
                $FoundRoles += $RoleName
            }
        }

        Write-Progress -ParentId 2 -Id 3 -Activity 'Roles' -Completed

        if ($FoundRoles.Count -gt 0) {
            $ProjectRolePermissions += [PSCustomObject]@{
                URL   = "https://$Domain.atlassian.net/plugins/servlet/project-config/$ProjectKey/people"
                key   = $ProjectKey
                roles = $FoundRoles
            }
        }
    }

    if ($ProjectRolePermissions.Count -gt 0) {
        $Report.'Project Roles' = $ProjectRolePermissions
    }

    Write-Progress -Id 1 -ParentId 0 -Activity 'Getting Jira Project Roles' -Completed



    ##########
    # ASSETS #
    ##########

    Write-Progress -Id 1 -ParentId 0 -Activity 'Assets'

    $Assets = @()

    if ($null -eq $Cache_ObjectSchema -or $ResetCache) {
        $Global:Cache_ObjectSchema = Get-AssetsObjectSchemas
    }

    for ($ii = 0; $ii -lt $Cache_ObjectSchema.Count; $ii++) {

        $GroupRoles = @()

        if ($null -eq $Cache_ObjectSchema[$ii].roles) {
            $NewRoles = @()
            $RolesList = Get-AssetsObjectSchemaRoles $Cache_ObjectSchema[$ii].id

            if ($RolesList) {
                # Some ObjectSchema don't have roles.
                for ($iii = 0; $iii -lt $RolesList.Count; $iii++) {
                    # The roles returned by Get-AssetsObjectSchemaRoles don't
                    # include actor information
                    $NewRoles += Get-AssetsRole $RolesList[$iii].id
                }
            }

            $Cache_ObjectSchema[$ii] | Add-Member -NotePropertyName 'roles' -NotePropertyValue $NewRoles
        }

        if ($Cache_ObjectSchema[$ii].roles.count -gt 0) {

            $Cache_ObjectSchema[$ii].roles | ForEach-Object {
                if ($_.actors.name -eq $GroupName ) { $GroupRoles += $_.name }
            }

        }

        if ($GroupRoles.Count -gt 0) {
            $Assets += [pscustomobject]@{
                URL   = "https://$Domain.atlassian.net/jira/servicedesk/assets/configure/object-schema/$($Cache_ObjectSchema[$ii].id)"
                name  = $Cache_ObjectSchema[$ii].name
                roles = $GroupRoles
            }
        }

    }

    if ($Assets.count -gt 0) {
        $Report.'Assets Object Schemas' = $Assets
    }

    Write-Progress -Id 1 -ParentId 0 -Activity 'Assets' -Completed



    #################################
    # CONFLUENCE GLOBAL PERMISSIONS #
    #################################

    Write-Progress -Id 1 -ParentId 0 -Activity 'Getting Confluence Global Permissions'

    $ConfluenceGlobalReport = @{
        URL         = "https://$Domain.atlassian.net/wiki/admin/permissions/global?tab=internal"
        Permissions = @()
    }

    if ($null -eq $Cache_ConfluenceGlobal -or $ResetCache) {
        $Global:Cache_ConfluenceGlobal = Get-ConfluenceGlobalGroupWithPermissions
    }

    for ($ii = 0; $ii -lt $Cache_ConfluenceGlobal.Count; $ii++) {
        if ($Cache_ConfluenceGlobal[$ii].name -eq $GroupName) {
            $ConfluenceGlobalReport.Permissions += $Cache_ConfluenceGlobal[$ii].operations | Select-Object targetType, operation
        }
    }

    if ($ConfluenceGlobalReport.Permissions.count -gt 0) {
        $Report['Confluence Global Permissions'] = $ConfluenceGlobalReport
    }

    Write-Progress -Id 1 -ParentId 0 -Activity 'Getting Confluence Global Permissions' -Completed



    ##################################
    # CONFLUENCE DEFAULT PERMISSIONS #
    ##################################

    Write-Progress -Id 1 -ParentId 0 -Activity 'Getting Confluence Default Space Permissions'

    $ConfluenceDefaultPermissions = @{
        URL         = "https://$Domain.atlassian.net/wiki/admin/permissions/viewdefaultspacepermissions.action"
        Permissions = @()
    }

    if ($null -eq $Cache_ConfluenceDefaultPermissions -or $ResetCache) {
        $Global:Cache_ConfluenceDefaultPermissions = Get-ConfluenceDefaultSpacePermissions
    }

    $ConfluenceDefaultPermissions.Permissions = $Cache_ConfluenceDefaultPermissions | Where-Object { $_.group -eq $GroupName } | ForEach-Object {
        $_ | Select-Object permission, permission-set
    }

    if ($ConfluenceDefaultPermissions.Permissions.Count -gt 0) {
        $Report.'Confluence Default Perissions' = $ConfluenceDefaultPermissions
    }

    Write-Progress -Id 1 -ParentId 0 -Activity 'Getting Confluence Default Space Permissions' -Completed



    ####################################
    # CONFLUENCE APPLICATION NAVIGATOR #
    ####################################

    Write-Progress -Id 1 -ParentId 0 -Activity 'Confluence Application Navigator'

    $ConfluenceCustomApps = [pscustomobject]@{
        URL          = "https://$Domain.atlassian.net/wiki/plugins/servlet/customize-application-navigator"
        applications = @()
    }

    if ($null -eq $Cache_ConfluenceCustomApps -or $ResetCache) {
        $Global:Cache_ConfluenceCustomApps = Get-ConfluenceCustomApplications
    }

    for ($ii = 0; $ii -lt $Cache_ConfluenceCustomApps.Count; $ii++) {
        if ($Cache_ConfluenceCustomApps[$ii].allowedGroups -contains $GroupName) {
            $ConfluenceCustomApps.applications += $Cache_ConfluenceCustomApps[$ii] | Select-Object id, url, displayName
        }
    }

    if ($ConfluenceCustomApps.applications.Count -gt 0) {
        $Report.'Confluence Custom Apps' = $ConfluenceCustomApps
    }

    Write-Progress -Id 1 -ParentId 0 -Activity 'Confluence Application Navigator' -Completed



    #####################
    # CONFLUENCE SPACES #
    #####################

    Write-Progress -Id 1 -ParentId 0 -Activity 'Getting All Confluence Spaces'

    $SpacesReport = @()

    if ($null -eq $Cache_Spaces -or $ResetCache) {
        $Global:Cache_Spaces = Get-ConfluenceAllSpaces -ApiVersion 1 -Expand permissions
    }

    for ($ii = 0; $ii -lt $Cache_Spaces.Count; $ii++) {

        $Permissions = @()

        for ($iii = 0; $iii -lt $Cache_Spaces[$ii].permissions.Count; $iii++) {

            if ($Cache_Spaces[$ii].permissions[$iii].subjects.group.results.name -eq $GroupName) {
                $Permissions += $Cache_Spaces[$ii].permissions[$iii] | Select-Object -Property id, operation
            }

        }

        if ($Permissions.count -gt 0) {
            $SpacesReport += @{
                Name        = $Cache_Spaces[$ii].name
                Key         = $Cache_Spaces[$ii].key
                Permissions = $Permissions
            } 
        }

    }

    Write-Progress -Id 1 -ParentId 0 -Activity 'Getting All Confluence Spaces' -Completed



    ####################
    # CONFLUENCE PAGES #
    ####################

    Write-Progress -Id 1 -ParentId 0 -Activity 'Getting All Confluence Pages'

    if ($null -eq $Cache_Pages -or $ResetCache) {
        $Global:Cache_Pages = Get-ConfluenceAllContent -Expand restrictions.read.restrictions.group, restrictions.update.restrictions.group, space
    }

    for ($ii = 0; $ii -lt $Cache_Pages.Count; $ii++) {

        $PagePermissions = @()

        if ($Cache_Pages[$ii].restrictions.read.restrictions.group.results | Where-Object { $_.name -eq $GroupName }) {
            $PagePermissions += 'READ'
        }
        if ($Cache_Pages[$ii].restrictions.update.restrictions.group.results | Where-Object { $_.name -eq $GroupName }) {
            $PagePermissions += 'UPDATE'
        }

        if ($PagePermissions.Count -gt 0) {

            if ($SpacesReport.Count -gt 0) {
                $SpaceIndex = [array]::FindIndex($SpacesReport, [Predicate[hashtable]] { param($item) $item['Key'] -eq $Cache_Pages[$ii].space.key })
            }
            else {
                $SpaceIndex = -1
            }

            if ($SpaceIndex -eq -1) {
                $SpacesReport += @{
                    Name            = $Cache_Pages[$ii].space.name
                    Key             = $Cache_Pages[$ii].space.key
                    PagePermissions = @()
                }
            }

            if ($null -eq $SpacesReport[$SpaceIndex].PagePermissions) {
                $SpacesReport[$SpaceIndex].PagePermissions = @()
            }

            $SpacesReport[$SpaceIndex].PagePermissions += @{
                ID          = $Cache_Pages[$ii].id
                Title       = $Cache_Pages[$ii].title
                Permissions = $PagePermissions
            }

        }

    }

    if ($SpacesReport.Count -gt 0) {
        $Report.'Confluence Spaces' = $SpacesReport
    }

    Write-Progress -Id 1 -ParentId 0 -Activity 'Getting All Confluence Pages' -Completed

 #>

    # Output file

    if ($PSBoundParameters.ContainsKey('Force')) {
        $Report | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Force
    }
    else {
        $Report | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Force
    }

}

Write-Progress -Id 0 -Activity 'Processing Group' -Completed
