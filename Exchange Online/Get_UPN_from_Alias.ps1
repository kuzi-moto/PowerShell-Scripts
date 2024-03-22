<#
.SYNOPSIS
    Fetches the Azure AD Object ID and the UPN from a list of aliases
.DESCRIPTION
    Fetches the Azure AD Object ID and the UPN from a list of aliases.
    We want to pull the Object ID because it's useful for running users
    through Azure AD commands, as AAD does not allow searching by an alias
    address of a user account.
.EXAMPLE
    PS C:\> <example usage>
    Explanation of what the example does
.INPUTS
    Inputs (if any)
.OUTPUTS
    Output (if any)
.NOTES
    General notes
#>

[CmdletBinding()]
param (
    [string]$Path,
    [switch]$ActiveSyncMailboxPolicy,
    [switch]$ActiveSyncMailboxPolicyIsDefaulted,
    [switch]$AddressBookPolicy,
    [switch]$AddressListMembership,
    [switch]$Alias,
    [switch]$ArchiveDatabase,
    [switch]$ArchiveGuid,
    [switch]$ArchiveRelease,
    [switch]$ArchiveState,
    [switch]$ArchiveStatus,
    [switch]$AuthenticationType,
    [switch]$BlockedSendersHash,
    [switch]$Capabilities,
    [switch]$City,
    [switch]$Company,
    [switch]$CountryOrRegion,
    [switch]$CustomAttribute1,
    [switch]$CustomAttribute10,
    [switch]$CustomAttribute11,
    [switch]$CustomAttribute12,
    [switch]$CustomAttribute13,
    [switch]$CustomAttribute14,
    [switch]$CustomAttribute15,
    [switch]$CustomAttribute2,
    [switch]$CustomAttribute3,
    [switch]$CustomAttribute4,
    [switch]$CustomAttribute5,
    [switch]$CustomAttribute6,
    [switch]$CustomAttribute7,
    [switch]$CustomAttribute8,
    [switch]$CustomAttribute9,
    [switch]$Database,
    [switch]$DatabaseName,
    [switch]$Department,
    [switch]$DisplayName,
    [switch]$DistinguishedName,
    [switch]$EmailAddresses,
    [switch]$EmailAddressPolicyEnabled,
    [switch]$ExchangeGuid,
    [switch]$ExchangeObjectId,
    [switch]$ExchangeVersion,
    [switch]$ExpansionServer,
    [switch]$ExtensionCustomAttribute1,
    [switch]$ExtensionCustomAttribute2,
    [switch]$ExtensionCustomAttribute3,
    [switch]$ExtensionCustomAttribute4,
    [switch]$ExtensionCustomAttribute5,
    [switch]$ExternalDirectoryObjectId = $true,
    [switch]$ExternalEmailAddress,
    [switch]$FirstName,
    [switch]$Guid,
    [switch]$HasActiveSyncDevicePartnership,
    [switch]$HiddenFromAddressListsEnabled,
    [switch]$Id,
    [switch]$Identity,
    [switch]$InformationBarrierSegments,
    [switch]$IsDirSynced,
    [switch]$IsValid,
    [switch]$IsValidSecurityPrincipal,
    [switch]$LastNameWindowsLiveID,
    [switch]$LitigationHoldEnabled,
    [switch]$MailboxMoveBatchName,
    [switch]$MailboxMoveFlags,
    [switch]$MailboxMoveRemoteHostName,
    [switch]$MailboxMoveSourceMDB,
    [switch]$MailboxMoveStatus,
    [switch]$MailboxMoveTargetMDB,
    [switch]$MailboxRelease,
    [switch]$ManagedBy,
    [switch]$ManagedFolderMailboxPolicy,
    [switch]$Manager,
    [switch]$Name,
    [switch]$Notes,
    [switch]$ObjectCategory,
    [switch]$ObjectClass,
    [switch]$ObjectState,
    [switch]$Office,
    [switch]$OrganizationalUnit,
    [switch]$OrganizationalUnitRoot,
    [switch]$OrganizationId,
    [switch]$OriginatingServer,
    [switch]$OwaMailboxPolicy,
    [switch]$Phone,
    [switch]$PoliciesExcluded,
    [switch]$PoliciesIncluded,
    [switch]$PostalCode,
    [switch]$PrimarySmtpAddress,
    [switch]$RecipientType,
    [switch]$RecipientTypeDetails,
    [switch]$ResourceType,
    [switch]$RetentionPolicy,
    [switch]$RootCapabilities,
    [switch]$SafeRecipientsHash,
    [switch]$SafeSendersHash,
    [switch]$SamAccountName,
    [switch]$ServerLegacyDN,
    [switch]$ServerName,
    [switch]$SharingPolicy,
    [switch]$ShouldUseDefaultRetentionPolicy,
    [switch]$SKUAssigned,
    [switch]$StateOrProvince,
    [switch]$StorageGroupName,
    [switch]$Title,
    [switch]$UMEnabled,
    [switch]$UMMailboxPolicy,
    [switch]$UMRecipientDialPlanId,
    [switch]$UnifiedGroupSKU,
    [switch]$UsageLocation,
    [switch]$WhenChanged,
    [switch]$WhenChangedUTC,
    [switch]$WhenCreated,
    [switch]$WhenCreatedUTC,
    [switch]$WhenIBSegmentChanged,
    [switch]$WhenMailboxCreated,
    [switch]$WhenSoftDeleted,
    [switch]$WindowsLiveID = $true
)

$PossibleOptions = @(
    'ActiveSyncMailboxPolicy',
    'ActiveSyncMailboxPolicyIsDefaulted',
    'AddressBookPolicy',
    'AddressListMembership',
    'Alias',
    'ArchiveDatabase',
    'ArchiveGuid',
    'ArchiveRelease',
    'ArchiveState',
    'ArchiveStatus',
    'AuthenticationType',
    'BlockedSendersHash',
    'Capabilities',
    'City',
    'Company',
    'CountryOrRegion',
    'CustomAttribute1',
    'CustomAttribute10',
    'CustomAttribute11',
    'CustomAttribute12',
    'CustomAttribute13',
    'CustomAttribute14',
    'CustomAttribute15',
    'CustomAttribute2',
    'CustomAttribute3',
    'CustomAttribute4',
    'CustomAttribute5',
    'CustomAttribute6',
    'CustomAttribute7',
    'CustomAttribute8',
    'CustomAttribute9',
    'Database',
    'DatabaseName',
    'Department',
    'DisplayName',
    'DistinguishedName',
    'EmailAddresses',
    'EmailAddressPolicyEnabled',
    'ExchangeGuid',
    'ExchangeObjectId',
    'ExchangeVersion',
    'ExpansionServer',
    'ExtensionCustomAttribute1',
    'ExtensionCustomAttribute2',
    'ExtensionCustomAttribute3',
    'ExtensionCustomAttribute4',
    'ExtensionCustomAttribute5',
    'ExternalDirectoryObjectId',
    'ExternalEmailAddress',
    'FirstName',
    'Guid',
    'HasActiveSyncDevicePartnership',
    'HiddenFromAddressListsEnabled',
    'Id',
    'Identity',
    'InformationBarrierSegments',
    'IsDirSynced',
    'IsValid',
    'IsValidSecurityPrincipal',
    'LastNameWindowsLiveID',
    'LitigationHoldEnabled',
    'MailboxMoveBatchName',
    'MailboxMoveFlags',
    'MailboxMoveRemoteHostName',
    'MailboxMoveSourceMDB',
    'MailboxMoveStatus',
    'MailboxMoveTargetMDB',
    'MailboxRelease',
    'ManagedBy',
    'ManagedFolderMailboxPolicy',
    'Manager',
    'Name',
    'Notes',
    'ObjectCategory',
    'ObjectClass',
    'ObjectState',
    'Office',
    'OrganizationalUnit',
    'OrganizationalUnitRoot',
    'OrganizationId',
    'OriginatingServer',
    'OwaMailboxPolicy',
    'Phone',
    'PoliciesExcluded',
    'PoliciesIncluded',
    'PostalCode',
    'PrimarySmtpAddress',
    'RecipientType',
    'RecipientTypeDetails',
    'ResourceType',
    'RetentionPolicy',
    'RootCapabilities',
    'SafeRecipientsHash',
    'SafeSendersHash',
    'SamAccountName',
    'ServerLegacyDN',
    'ServerName',
    'SharingPolicy',
    'ShouldUseDefaultRetentionPolicy',
    'SKUAssigned',
    'StateOrProvince',
    'StorageGroupName',
    'Title',
    'UMEnabled',
    'UMMailboxPolicy',
    'UMRecipientDialPlanId',
    'UnifiedGroupSKU',
    'UsageLocation',
    'WhenChanged',
    'WhenChangedUTC',
    'WhenCreated',
    'WhenCreatedUTC',
    'WhenIBSegmentChanged',
    'WhenMailboxCreated',
    'WhenSoftDeleted',
    'WindowsLiveID'
)

#--------------[ Includes ]--------------


$Lib = Join-Path (Get-Item -Path $PSScriptRoot).Parent.FullName 'lib'

. (Join-Path $Lib 'CSV_Functions.ps1')
. (Join-Path $PSScriptRoot 'Functions.ps1')


#-----------[ Main Execution ]-----------


Connect-ToEXO

$File = Import-FromCSV $Path

# Get the existing columns

$Columns = ($File | Get-Member | Where-Object { $_.MemberType -eq "NoteProperty" }).Name
$Table = @{}

foreach ($Column in $Columns) {
    $Table[$column] = $File[0].($Column)
}

# Determine which column contains the alias

$Table | Out-Host

do {
    $AliasColumn = Read-Host "Enter name of column which contains user alias"
    if ($Columns -notcontains $AliasColumn) {
        Write-Warning "`"$AliasColumn`" doesn't exist, try again"
        $AliasColumn = ""
    }
} until ($AliasColumn)

# Determine the desired columns from switches used

$SelectedColumns = @()

foreach ($Column in $PossibleOptions) {
    if (Get-Variable -Name $Column -ValueOnly) {$SelectedColumns += $Column}
}

for ($i = 0; $i -lt $File.Count; $i++) {

    Write-Progress -Activity "Getting user information" -Status "Progress: $($i+1)/$($File.Count)" -PercentComplete (($i+1) / $File.Count * 100)

    $User = Search-Alias $File[$i].$AliasColumn

    if ($User) {
        $SelectedColumns | ForEach-Object {
            $File[$i] | Add-Member -NotePropertyName $_ -NotePropertyValue $User.$_ -Force
        }
    }
    else {
        $SelectedColumns | ForEach-Object {
            $File[$i] | Add-Member -NotePropertyName $_ -NotePropertyValue "ERROR" -Force
        }
    }

}

Write-Progress -Activity "Getting user information" -Status "Completed" -Completed

Export-CsvToFile $File $Path