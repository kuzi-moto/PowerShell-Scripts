<#
.SYNOPSIS
    Gets mailboxes that are forwarding to the requested account.
.DESCRIPTION
    When a name or email alias is supplied, this script will return a list of mailboxes that are forwarding to the address.
.NOTES
    This script should work with PowerShell 5 and up.
.LINK
    Specify a URI to a help page, this will show when Get-Help -Online is used.
.EXAMPLE
    Get_Forwarding_Mailboxes.ps1 john.doe@example.com
    This will search for all mailboxes that are forwarding to john.doe@example.com as well as any aliases that belong to the user.
#>


param (
    [Parameter(Mandatory=$true)]
    [string]$Search
)

#--------------[ Includes ]--------------


$Lib = Join-Path (Get-Item -Path $PSScriptRoot).Parent.FullName 'lib'

. (Join-Path $PSScriptRoot 'Functions.ps1')


#-----------[ Main Execution ]-----------

# Work in progress...

# 1. Determine if input is name or alias
# 2. If Name try to resolve the name to an mailbox
# 3. if alias try to resolve to a mailbox
# 4. if alias does not resolve inform the user and continue trying to match on the result.
# 5. if name or alias resolve then attempt to search for all mailboxes that forward to the users's addresses.

# Attributes:
# ForwardingAddress
#   this is a Name, match against the name of the mailbox
#   Do not attempt to search against this attribute if an external email is provided.
# ForwardingSmtpAddress
#   This is an email address with the layout: smtp:user.name@example.com
#   Loop through all accounts to see if any match on any of the matched mailbox aliases

if ($Search -match '@') {
    Get-Mailbox
}

# Gets any mailbox that has a forwarding address set.
$ForwardingMailboxes = Get-Mailbox -Filter { ForwardingAddress -like "*" -or ForwardingSmtpAddress -like "*" } -ResultSize unlimited

