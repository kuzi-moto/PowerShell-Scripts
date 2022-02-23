<#
 #
 # Stolen from: https://www.sharepointdiary.com/2018/08/sharepoint-online-delete-all-files-and-sub-folders-recursively-from-folder-using-powershell.html?showComment=1600356869651
 #
#>

[CmdletBinding()]
param (
    [string]
    $SiteURL,

    [string]
    $ServerRelativeUrl
)

#Parameters
$SiteURL = "https://crescent.sharepoint.com/sites/Marketing"
$FolderSiteRelativeURL = "/Shared Documents/2018"

#Connect to the Site
Connect-PnPOnline -URL $SiteURL -Credentials (Get-Credential)

#Get the web & folder
$Web = Get-PnPWeb
$Folder = Get-PnPFolder -Url $FolderSiteRelativeURL

#Function to delete all Files and sub-folders from a Folder
Function Empty-PnPFolder([Microsoft.SharePoint.Client.Folder]$Folder)
{
    #Get the site relative path of the Folder
    If($Web.ServerRelativeURL -eq "/")
    {
        $FolderSiteRelativeURL = $Folder.ServerRelativeUrl
    }
    Else
    {
        $FolderSiteRelativeURL = $Folder.ServerRelativeUrl.Replace($Web.ServerRelativeURL,"")
    }

    #Delete all files in the Folder
    $Files = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderSiteRelativeURL -ItemType File
    ForEach ($File in $Files)
    {
        #Delete File
        Remove-PnPFile -ServerRelativeUrl $File.ServerRelativeURL -Force -Recycle
        Write-Host -f Green ("Deleted File: '{0}' at '{1}'" -f $File.Name, $File.ServerRelativeURL)
    }

    #Process all Sub-Folders
    $SubFolders = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderSiteRelativeURL -ItemType Folder
    Foreach($SubFolder in $SubFolders)
    {
        #Exclude "Forms" and Hidden folders
        If(($SubFolder.Name -ne "Forms") -and (-Not($SubFolder.Name.StartsWith("_"))))
        {
            #Call the function recursively
            Empty-PnPFolder -Folder $SubFolder

            #Delete the folder
            Remove-PnPFolder -Name $SubFolder.Name -Folder $FolderSiteRelativeURL -Force -Recycle
            Write-Host -f Green ("Deleted Folder: '{0}' at '{1}'" -f $SubFolder.Name, $SubFolder.ServerRelativeURL)
        }
    }
}

#Call the function to empty folder
Empty-PnPFolder -Folder $Folder