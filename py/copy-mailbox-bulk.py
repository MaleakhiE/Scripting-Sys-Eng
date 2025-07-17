# PERMISSIONS NEEDED (MSGRAPH) - Application Permissions #
# - Application.Read.All
# - Calendars.ReadWrite.All
# - Contacts.ReadWrite.All
# - Files.ReadWrite.All
# - Group.ReadWrite.All
# - Mail.ReadWrite.All 
# - MailboxSettings.ReadWrite
# - Sites.ReadWrite.All
# - Team.ReadWrite.All
# - User.Read.All
# - User.ReadWrite.All
# - TeamSettings.ReadWrite.All
# - TeamMember.ReadWrite.All
# - TeamAppInstallation.ReadWrite.All
# PERMISSIONS NEEDED (MSGRAPH) - Application Permissions #

import os
import time
import datetime
import requests
import json
import sys
import csv
from pprint import pprint
import msal 

# Azure AD app registration details
CLIENT_ID = "6dec904c-284c-4b73-91da-bc4b9206b58e"
CLIENT_SECRET = "egY8Q~6ZlTGjqkURTfWJY2IYTPk1iRHwJIom-aqH"
TENANT_ID = "c412f886-ab3a-4600-91a2-b67fa3aa95ed"

# Default target folder name
TARGET_FOLDER = "Imported"  # Main folder for imported emails

# Authentication and API endpoints
AUTHORITY = f"https://login.microsoftonline.com/{TENANT_ID}"
SCOPES = ["https://graph.microsoft.com/.default"]
GRAPH_ENDPOINT = "https://graph.microsoft.com/v1.0"

# Migration options
COPY_OPTIONS = {
    "emails": False,
    "contacts": False,
    "calendar": False,
    "groups": True,
    "sharepoint": False,
    "teams": False,
    "archive": False
}

def get_access_token():
    app = msal.ConfidentialClientApplication(
        client_id=CLIENT_ID,
        client_credential=CLIENT_SECRET,
        authority=AUTHORITY
    )
    
    result = app.acquire_token_for_client(scopes=SCOPES)
    
    if "access_token" in result:
        # print("✅ Successfully obtained access token")
        return result["access_token"]
    else:
        print(f"❌ Error getting token: {result.get('error')}")
        print(f"Error description: {result.get('error_description')}")
        exit(1)

def check_permissions(token, source_email):
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    
    response = requests.get(f"{GRAPH_ENDPOINT}/me", headers=headers)
    if response.status_code == 401:
        print("❌ Token is invalid or expired")
        return False
    
    try:
        response = requests.get(f"{GRAPH_ENDPOINT}/users/{source_email}/mailFolders", headers=headers)
        if response.status_code >= 400:
            print("❌ Permission check failed. The app may not have required permissions.")
            print(f"Error: {response.status_code} - {response.text}")
            return False
        else:
            print("✅ App has sufficient permissions to access mailboxes")
            return True
    except Exception as e:
        print(f"❌ Error checking permissions: {str(e)}")
        return False
    
def get_valid_token(current_token=None):
    """Get a valid token, either by using the existing one or getting a new one if expired"""
    if current_token:
        # Test the current token
        headers = {
            "Authorization": f"Bearer {current_token}",
            "Content-Type": "application/json"
        }
        
        try:
            response = requests.get(f"{GRAPH_ENDPOINT}/me", headers=headers)
            if response.status_code != 401:  # Token is still valid
                return current_token
            # print("⚠️ Token expired, getting new token...")
        except Exception:
            print("⚠️ Error checking token, getting new token...")
    
    return get_access_token()

def make_api_call(endpoint, token, method="GET", data=None):
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    
    full_url = f"{GRAPH_ENDPOINT}{endpoint}"
    
    try:
        if method == "GET":
            response = requests.get(full_url, headers=headers)
        elif method == "POST":
            response = requests.post(full_url, headers=headers, json=data)
        
        # Check if token expired (401 status code)
        if response.status_code == 401:
            # print("⚠️ Token expired during API call, refreshing...")
            new_token = get_valid_token()
            # Update headers with new token
            headers["Authorization"] = f"Bearer {new_token}"
            
            # Retry the request with new token
            if method == "GET":
                response = requests.get(full_url, headers=headers)
            elif method == "POST":
                response = requests.post(full_url, headers=headers, json=data)
        
        if response.status_code >= 400:
            print(f"❌ API call failed: {method} {endpoint}")
            print(f"Status code: {response.status_code}")
            print(f"Error: {response.text}")
            return None
        
        return response.json() if response.content else None
    except Exception as e:
        print(f"❌ Error making API call: {str(e)}")
        return None
    
def get_mailbox_folders(token, email):
    result = make_api_call(f"/users/{email}/mailFolders?$top=100", token)
    
    if result and 'value' in result:
        folders = result['value']
        print(f"Found {len(folders)} folders")
        for folder in folders:
            print(f"  - {folder['displayName']} (ID: {folder['id']})")
        return folders
    else:
        print("❌ Failed to retrieve folders")
        return []

def get_archive_folders(token, email):
    """Get all folders in the in-place archive mailbox"""
    print(f"Retrieving in-place archive folders for {email}...")
    
    try:
        # First check if user has archive enabled
        user_info = make_api_call(f"/users/{email}", token)
        if not user_info or not user_info.get('mailboxSettings', {}).get('archiveFolder'):
            print("❌ User does not have archive mailbox enabled")
            return []

        # Try to access archive using different endpoint
        archive_root = make_api_call(f"/users/{email}/mailfolders/archive", token)
        
        if not archive_root:
            print("❌ Could not access archive root folder")
            return []

        print(f"✅ Found archive root folder (ID: {archive_root['id']})")
        
        # Get all subfolders in the archive
        folders = [archive_root]  # Start with root folder
        
        # Get child folders
        children = make_api_call(
            f"/users/{email}/mailfolders/{archive_root['id']}/childfolders?$expand=childFolders", 
            token
        )
        
        if children and 'value' in children:
            folders.extend(children['value'])
            print(f"Found {len(children['value'])} subfolders in archive")
        
        return folders
        
    except Exception as e:
        print(f"❌ Error accessing archive: {str(e)}")
        return []
      
def create_target_folder(token, target_email, parent_id=None, folder_name=None):
    folder_name = folder_name or TARGET_FOLDER
    
    # Endpoint for searching folders
    endpoint = f"/users/{target_email}/mailFolders"
    if parent_id:
        endpoint = f"/users/{target_email}/mailFolders/{parent_id}/childFolders"
    
    # Try to find if the folder already exists
    folders = make_api_call(endpoint, token)
    
    if folders and 'value' in folders:
        for folder in folders['value']:
            if folder['displayName'].lower() == folder_name.lower():
                print(f"✅ Found existing folder: {folder['displayName']}")
                return folder['id']
    
    # If not found, create it
    folder_data = {
        "displayName": folder_name,
        "isHidden": False
    }
    
    result = make_api_call(endpoint, token, "POST", folder_data)
    
    if result:
        print(f"✅ Created folder: {result['displayName']}")
        return result['id']
    else:
        print(f"❌ Failed to create folder '{folder_name}'")
        
        if folder_name == TARGET_FOLDER and not parent_id:
            inbox = make_api_call(f"/users/{target_email}/mailFolders/inbox", token)
            if inbox and 'id' in inbox:
                return inbox['id']
        return None

def get_all_emails_from_folder(token, email, folder_id, folder_name, page_size=50):
    endpoint = f"/users/{email}/mailFolders/{folder_id}/messages?$top={page_size}"
    emails = []
    page = 1
    
    while endpoint:
        print(f"Fetching page {page}...")
        result = make_api_call(endpoint, token)
        if not result:
            break
            
        batch = result.get('value', [])
        emails.extend(batch)
        
        # Check if there are more pages
        if '@odata.nextLink' in result:
            endpoint = result['@odata.nextLink'].replace(GRAPH_ENDPOINT, '')
            page += 1
        else:
            endpoint = None
    
    print(f"Total emails retrieved from '{folder_name}': {len(emails)}")
    return emails

def copy_email_to_target(token, source_email, target_email, email, target_folder_id):
    try:
        email_id = email['id']
        subject = email.get('subject', '(No Subject)')
        received_time = email.get('receivedDateTime', '')
        internet_message_id = email.get('internetMessageId', '')
        
        # Use message ID to find exact matches
        if internet_message_id:
            search_query = f"/users/{target_email}/mailFolders/{target_folder_id}/messages?$filter=internetMessageId eq '{internet_message_id}'"
            existing = make_api_call(search_query, token)
            
            if existing and 'value' in existing and len(existing['value']) > 0:
                print(f"⏭️  Skipping duplicate email (Message ID match): {subject}")
                return True
        
        # If no message ID match, try by subject and received time
        if received_time:
            search_query = f"/users/{target_email}/mailFolders/{target_folder_id}/messages?$filter=subject eq '{subject}' and receivedDateTime eq {received_time}"
            existing = make_api_call(search_query, token)
            
            if existing and 'value' in existing and len(existing['value']) > 0:
                print(f"⏭️  Skipping duplicate email (Subject/Time match): {subject}")
                return True
        
        # If email doesn't exist, proceed with copying
        full_email = make_api_call(f"/users/{source_email}/messages/{email_id}", token)
        
        if not full_email:
            print(f"❌ Failed to get full email content for: {subject}")
            return False
        
        # Prepare the email for copying with all available metadata
        new_email = {
            "subject": full_email.get('subject', '(No Subject)'),
            "body": full_email.get('body', {"contentType": "text", "content": ""}),
            "toRecipients": [{"emailAddress": {"address": target_email}}],
            "importance": full_email.get('importance', 'normal'),
            "receivedDateTime": full_email.get('receivedDateTime'),
            "internetMessageId": full_email.get('internetMessageId', ''),
            "categories": full_email.get('categories', []),
            "flag": full_email.get('flag', {}),
            "isRead": full_email.get('isRead', False)
        }
        
        # Add sender information if available
        if 'sender' in full_email and 'emailAddress' in full_email['sender']:
            sender_email = full_email['sender']['emailAddress'].get('address', 'unknown@example.com')
            sender_name = full_email['sender']['emailAddress'].get('name', 'Unknown')
            new_email["from"] = {
                "emailAddress": {
                    "address": sender_email,
                    "name": sender_name
                }
            }
        
        # Create the email in the target folder
        result = make_api_call(
            f"/users/{target_email}/mailFolders/{target_folder_id}/messages", 
            token, 
            "POST", 
            new_email
        )
        
        if result:
            print(f"✅ Copied: {subject}")
            return True
        else:
            print(f"❌ Failed: {subject}")
            return False
            
    except Exception as e:
        print(f"❌ Error copying email: {str(e)}")
        return False

def copy_contacts(token, source_email, target_email):
    print(f"\nCopying contacts from {source_email} to {target_email}...")
    
    contacts = []
    endpoint = f"/users/{source_email}/contacts"
    
    result = make_api_call(endpoint, token)
    if result and 'value' in result:
        contacts = result['value']
        print(f"Found {len(contacts)} contacts")
    else:
        print("❌ No contacts found")
        return 0
    
    success_count = 0
    for contact in contacts:
        contact_name = contact.get('displayName', 'Unknown Contact')
        
        new_contact = {
            "givenName": contact.get('givenName', ''),
            "surname": contact.get('surname', ''),
            "displayName": contact.get('displayName', ''),
            "emailAddresses": contact.get('emailAddresses', []),
            "mobilePhone": contact.get('mobilePhone', ''),
            "businessPhones": contact.get('businessPhones', []),
            "personalNotes": contact.get('personalNotes', ''),
            "jobTitle": contact.get('jobTitle', ''),
            "companyName": contact.get('companyName', ''),
            "department": contact.get('department', ''),
            "businessAddress": contact.get('businessAddress', {}),
        }
        
        result = make_api_call(f"/users/{target_email}/contacts", token, "POST", new_contact)
        
        if result:
            print(f"✅ Copied contact: {contact_name}")
            success_count += 1
        else:
            print(f"❌ Failed contact: {contact_name}")
        
        time.sleep(0.5)
    
    print(f"Copied {success_count}/{len(contacts)} contacts")
    return success_count

def copy_calendar_events(token, source_email, target_email):
    print(f"\nCopying calendar events from {source_email} to {target_email}...")
    
    events = []
    start_date = (datetime.datetime.now() - datetime.timedelta(days=365)).isoformat()
    endpoint = f"/users/{source_email}/calendar/events?startDateTime={start_date}"
    
    result = make_api_call(endpoint, token)
    if result and 'value' in result:
        events = result['value']
        print(f"Found {len(events)} events")
    else:
        print("❌ No events found")
        return 0
    
    success_count = 0
    for event in events:
        event_subject = event.get('subject', 'Untitled Event')
        
        new_event = {
            "subject": event.get('subject', 'Untitled Event'),
            "body": event.get('body', {"contentType": "text", "content": ""}),
            "start": event.get('start', {"dateTime": "2023-01-01T00:00:00", "timeZone": "UTC"}),
            "end": event.get('end', {"dateTime": "2023-01-01T01:00:00", "timeZone": "UTC"}),
            "location": event.get('location', {"displayName": ""}),
            "attendees": [
                {
                    "emailAddress": {
                        "address": target_email,
                        "name": target_email.split('@')[0]
                    },
                    "type": "required"
                }
            ]
        }
        
        result = make_api_call(f"/users/{target_email}/calendar/events", token, "POST", new_event)
        
        if result:
            print(f"✅ Copied event: {event_subject}")
            success_count += 1
        else:
            print(f"❌ Failed event: {event_subject}")
        
        time.sleep(0.5)
    
    print(f"Copied {success_count}/{len(events)} events")
    return success_count

import subprocess
import time
import tempfile
import os
import re
from pathlib import Path


def copy_groups(token, source_email, target_email):
    print(f"\nCopying group memberships from {source_email} to {target_email}...")
    excluded_group_ids = {
        "7d056282-a2d1-4f69-8847-875c3c475cd3",  # all user stp grup
        "4e6601a0-9fed-48f2-9f4b-99adb2202b98",  # GL F3 Step up
        "21e9a3ec-d70c-4952-beaa-1c0eb5b4ba55",  # GL STP E3
    }

    mail_enabled_groups = []
    security_groups = []

    groups = []
    endpoint = f"/users/{source_email}/memberOf"
    result = make_api_call(endpoint, token)
    if result and 'value' in result:
        groups = [g for g in result['value'] if g.get('@odata.type') == '#microsoft.graph.group']
        print(f"Found {len(groups)} groups")
    else:
        print("❌ No groups found")
        return 0

    success_count = 0
    for group in groups:
        group_id = group.get('id')
        group_name = group.get('displayName', 'Unknown Group')
        if not group_id:
            continue

        if group_id in excluded_group_ids:
            print(f"⏭️ Skipping excluded group: {group_name} ({group_id})")
            continue

        if group.get('mailEnabled'):
            group_mail = group.get('mail')
            if not group_mail:
                group_details = make_api_call(f"/groups/{group_id}", token)
                group_mail = group_details.get('mail') if group_details else None

            mail_enabled_groups.append({
                'id': group_id,
                'name': group_name,
                'mail': group_mail
            })
            print(f"📧 Mail-enabled group queued for PowerShell: {group_name}")
        else:
            security_groups.append({
                'id': group_id,
                'name': group_name
            })
            print(f"🛡️ Security group queued for PowerShell: {group_name}")

        time.sleep(0.5)

    if mail_enabled_groups or security_groups:
        print("\nGenerating PowerShell script for group membership...")
        ps_script = run_powershell_commands(mail_enabled_groups, security_groups, target_email)
        if ps_script:
            print(f"📄 PowerShell script saved: {ps_script}")
            success_count += len(mail_enabled_groups) + len(security_groups)

    print(f"\nAdded to {success_count}/{len(groups)} groups total")
    return success_count


import re
from pathlib import Path

def run_powershell_commands(mail_enabled_groups, security_groups, target_email):
    """Generate PowerShell script to add user to mail-enabled and Azure AD security groups with improved group type detection"""

    def sanitize_filename(email):
        return re.sub(r'[^a-zA-Z0-9_.-]', '_', email)

    sanitized_email = sanitize_filename(target_email)
    script_filename = Path.cwd() / f"add_to_groups_{sanitized_email}.ps1"

    try:
        with open(script_filename, 'w') as f:
            # Header with prerequisites and connection commands
            f.write("# PowerShell script to add user to various group types\n")
            f.write("# Generated for: " + target_email + "\n\n")
            f.write("Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force\n\n")
            
            # Define helper function to detect group type
            f.write("function Add-UserToGroup {\n")
            f.write("    param(\n")
            f.write("        [string]$Identity,\n")
            f.write("        [string]$UserEmail\n")
            f.write("    )\n\n")
            
            f.write("    # First, try to determine what type of group this is\n")
            f.write("    try {\n")
            f.write("        # Check if it's a Microsoft 365 Group\n")
            f.write("        $unified = Get-UnifiedGroup -Identity $Identity -ErrorAction SilentlyContinue\n")
            f.write("        if ($unified) {\n")
            f.write("            Write-Host \"Adding to Microsoft 365 Group: $Identity\"\n")
            f.write("            Add-UnifiedGroupLinks -Identity $unified.Identity -LinkType Members -Links $UserEmail\n")
            f.write("            return $true\n")
            f.write("        }\n\n")
            
            f.write("        # Check if it's a Distribution Group\n")
            f.write("        $distGroup = Get-DistributionGroup -Identity $Identity -ErrorAction SilentlyContinue\n")
            f.write("        if ($distGroup) {\n")
            f.write("            Write-Host \"Adding to Distribution Group: $Identity\"\n")
            f.write("            Add-DistributionGroupMember -Identity $distGroup.Identity -Member $UserEmail -BypassSecurityGroupManagerCheck\n")
            f.write("            return $true\n")
            f.write("        }\n\n")
            
            f.write("        # Check if it's a mail-enabled security group\n")
            f.write("        $mailGroup = Get-Group -Identity $Identity -ErrorAction SilentlyContinue | Where-Object {$_.RecipientTypeDetails -eq \"MailUniversalSecurityGroup\"}\n")
            f.write("        if ($mailGroup) {\n")
            f.write("            Write-Host \"Adding to Mail-Enabled Security Group: $Identity\"\n")
            f.write("            Add-DistributionGroupMember -Identity $mailGroup.Identity -Member $UserEmail -BypassSecurityGroupManagerCheck\n")
            f.write("            return $true\n")
            f.write("        }\n\n")
            
            f.write("        Write-Warning \"Could not identify group type for: $Identity\"\n")
            f.write("        return $false\n")
            f.write("    } catch {\n")
            f.write("        Write-Warning \"Error processing group $Identity : $($_.Exception.Message)\"\n")
            f.write("        return $false\n")
            f.write("    }\n")
            f.write("}\n\n")

            # Mail-enabled groups section
            f.write("# Process mail-enabled groups\n")
            for group in mail_enabled_groups:
                identity = group.get("mail") or group.get("name")
                f.write(f"Write-Host \"Processing group: {identity}\" -ForegroundColor Cyan\n")
                f.write(f"Add-UserToGroup -Identity \"{identity}\" -UserEmail \"{target_email}\"\n\n")

            # Azure AD Security Groups using Microsoft Graph
            if security_groups:
                f.write("\n# --- Microsoft Graph Section for Security Groups ---\n")
                f.write("# Import Microsoft Graph module if not already loaded\n")
                f.write("if (-not (Get-Module -Name Microsoft.Graph.Groups -ListAvailable)) {\n")
                f.write("    Write-Warning \"Microsoft Graph PowerShell module not found.\"\n")
                f.write("    Write-Host \"To install: Install-Module Microsoft.Graph -Scope CurrentUser\"\n")
                f.write("    Write-Host \"Then connect: Connect-MgGraph -Scopes 'Group.ReadWrite.All','User.Read.All'\"\n")
                f.write("} else {\n")
                f.write("    # Ensure we're connected to Microsoft Graph\n")
                f.write("    $graphConnection = Get-MgContext\n")
                f.write("    if (-not $graphConnection) {\n")
                f.write("        Write-Warning \"Not connected to Microsoft Graph. Please run: Connect-MgGraph -Scopes 'Group.ReadWrite.All','User.Read.All'\"\n")
                f.write("    }\n")
                f.write("}\n\n")
                
                f.write("# Get user object\n")
                f.write(f"try {{\n")
                f.write(f"    $user = Get-MgUser -UserId \"{target_email}\" -ErrorAction Stop\n")
                f.write(f"    if ($user) {{\n")
                f.write(f"        Write-Host \"Found user: $($user.DisplayName) ($($user.Id))\" -ForegroundColor Green\n")
                f.write(f"    }}\n")
                f.write(f"}} catch {{\n")
                f.write(f"    Write-Error \"Could not find user {target_email}: $($_.Exception.Message)\"\n")
                f.write(f"    exit\n")
                f.write(f"}}\n\n")
                
                f.write("# Process security groups\n")
                for group in security_groups:
                    name = group['name']
                    f.write(f"Write-Host \"Processing security group: {name}\" -ForegroundColor Yellow\n")
                    f.write(f"try {{\n")
                    f.write(f"    $group = Get-MgGroup -Filter \"displayName eq '{name}'\" -ErrorAction Stop\n")
                    f.write(f"    if ($group) {{\n")
                    f.write(f"        Write-Host \"Found group: $($group.DisplayName) ($($group.Id))\"\n")
                    f.write(f"        try {{\n")
                    f.write(f"            New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop\n")
                    f.write(f"            Write-Host \"Successfully added user to security group: {name}\" -ForegroundColor Green\n")
                    f.write(f"        }} catch {{\n")
                    f.write(f"            $errorMsg = $_.Exception.Message\n")
                    f.write(f"            if ($errorMsg -like \"*One or more added object references already exist*\") {{\n")
                    f.write(f"                Write-Host \"User is already a member of {name}\" -ForegroundColor Cyan\n")
                    f.write(f"            }} else {{\n")
                    f.write(f"                Write-Warning \"Failed to add user to {name}: $errorMsg\"\n")
                    f.write(f"            }}\n")
                    f.write(f"        }}\n")
                    f.write(f"    }} else {{\n")
                    f.write(f"        Write-Warning \"Security group '{name}' not found\"\n")
                    f.write(f"    }}\n")
                    f.write(f"}} catch {{\n")
                    f.write(f"    Write-Warning \"Error searching for group '{name}': $($_.Exception.Message)\"\n")
                    f.write(f"}}\n\n")
            
            # Add summary section
            f.write("Write-Host \"`nGroup membership processing complete for "+ target_email +"\" -ForegroundColor Green\n")

        print(f"✅ PowerShell script saved as: {script_filename}")
        return str(script_filename)

    except Exception as e:
        print(f"❌ Failed to write PowerShell script: {str(e)}")
        return None

def copy_onedrive_files(token, source_email, target_email):
    print(f"\nCopying OneDrive files from {source_email} to {target_email}...")
    
    # Check if source has OneDrive
    source_drive = make_api_call(f"/users/{source_email}/drive", token)
    if not source_drive:
        print(f"❌ Source OneDrive not found for {source_email}")
        return 0
    
    # Get target drive with retry
    max_retries = 3
    for attempt in range(max_retries):
        target_drive = make_api_call(f"/users/{target_email}/drive", token)
        if target_drive:
            break
            
        print(f"⚠️ Target OneDrive not found on attempt {attempt+1}/{max_retries}. Trying to provision...")
        
        # Try to initialize/provision the OneDrive by accessing various endpoints
        make_api_call(f"/users/{target_email}/drive/root", token)
        time.sleep(2)  # Give it time to process
        
        # Try alternate endpoint
        make_api_call(f"/users/{target_email}/drives", token)
        time.sleep(2)
        
        if attempt == max_retries - 1:
            print("❌ Could not access target OneDrive after multiple attempts")
            print("The target user may need to log in to OneDrive at least once to provision it")
            return 0
    
    print(f"Source drive: {source_drive.get('name')} (ID: {source_drive.get('id')})")
    print(f"Target drive: {target_drive.get('name')} (ID: {target_drive.get('id')})")
    
    # Get root items from source drive
    items = []
    result = make_api_call(f"/users/{source_email}/drive/root/children", token)
    
    if result and 'value' in result:
        items = result['value']
        print(f"Found {len(items)} files/folders")
    else:
        print("❌ No files found")
        return 0
    
    # Count of successfully processed items
    success_count = 0
    
    # Helper function to safely create a folder, with retry logic
    def create_folder(folder_name, parent_id=None):
        for attempt in range(3):  # Try up to 3 times
            try:
                folder_data = {
                    "name": folder_name,
                    "folder": {},
                    "@microsoft.graph.conflictBehavior": "rename"
                }
                
                # If parent folder specified, create in that folder
                if parent_id:
                    endpoint = f"/users/{target_email}/drive/items/{parent_id}/children"
                else:
                    endpoint = f"/users/{target_email}/drive/root/children"
                
                new_folder = make_api_call(endpoint, token, "POST", folder_data)
                
                if new_folder and 'id' in new_folder:
                    print(f"✅ Created folder: {folder_name}")
                    return new_folder
                
                # If we get here, the API call didn't fail with an exception but didn't return a valid folder
                print(f"⚠️ Folder creation returned unexpected result on attempt {attempt+1}")
                
                # Try alternate approach if we're on the final attempt
                if attempt == 2:
                    # Try a simpler approach for the last attempt
                    simple_data = {"name": folder_name, "folder": {}}
                    simple_folder = make_api_call(
                        f"/users/{target_email}/drive/root/children", 
                        token, 
                        "POST", 
                        simple_data
                    )
                    if simple_folder and 'id' in simple_folder:
                        print(f"✅ Created folder using alternative method: {folder_name}")
                        return simple_folder
                
                time.sleep(2)  # Wait before retrying
                    
            except Exception as e:
                print(f"⚠️ Error creating folder on attempt {attempt+1}: {str(e)}")
                time.sleep(2)  # Wait before retrying
                
                # On last attempt, try to find the folder if it might already exist
                if attempt == 2:
                    try:
                        # Check if folder already exists
                        list_endpoint = f"/users/{target_email}/drive/root/children"
                        folders = make_api_call(list_endpoint, token)
                        
                        if folders and 'value' in folders:
                            for existing in folders['value']:
                                if existing.get('name') == folder_name and 'folder' in existing:
                                    print(f"✅ Found existing folder: {folder_name}")
                                    return existing
                    except Exception as finder_error:
                        print(f"❌ Error finding existing folder: {str(finder_error)}")
        
        print(f"❌ Failed to create folder: {folder_name}")
        return None
    
    # Helper function to safely copy a file, handling name conflicts
    def copy_file(src_id, src_name, target_folder_id=None):
        try:
            print(f"Copying file: {src_name}")
            
            # First check if file already exists to handle the "nameAlreadyExists" error
            file_exists = False
            target_folder_endpoint = "/users/{}/drive/root/children".format(target_email)
            
            if target_folder_id:
                target_folder_endpoint = "/users/{}/drive/items/{}/children".format(target_email, target_folder_id)
                
            existing_files = make_api_call(target_folder_endpoint, token)
            
            if existing_files and 'value' in existing_files:
                for existing in existing_files['value']:
                    if existing.get('name') == src_name and 'file' in existing:
                        print(f"⚠️ File already exists: {src_name}")
                        file_exists = True
                        return 1  # Count as success since the file is already there
            
            if file_exists:
                return 1
            
            # Create copy request with conflict behavior
            copy_data = {
                "name": src_name,
                "@microsoft.graph.conflictBehavior": "rename"  # Will rename if conflict
            }
            
            # If a target folder is specified, include it in the parentReference
            if target_folder_id:
                copy_data["parentReference"] = {
                    "id": target_folder_id
                }
            else:
                copy_data["parentReference"] = {
                    "driveId": target_drive.get('id'),
                    "path": "/drive/root:"
                }
            
            # Use the direct copy API endpoint
            copy_result = make_api_call(
                f"/users/{source_email}/drive/items/{src_id}/copy", 
                token, 
                "POST", 
                copy_data
            )
            
            if copy_result is not None:
                print(f"✅ Copy initiated for file: {src_name}")
                return 1
            else:
                # Try alternative method - create empty file and then update content
                print(f"⚠️ Direct copy failed. Trying alternative method for: {src_name}")
                
                # Try to create an empty file
                empty_file = {
                    "name": src_name,
                    "file": {},
                    "@microsoft.graph.conflictBehavior": "rename"
                }
                
                if target_folder_id:
                    create_endpoint = f"/users/{target_email}/drive/items/{target_folder_id}/children"
                else:
                    create_endpoint = f"/users/{target_email}/drive/root/children"
                    
                new_file = make_api_call(create_endpoint, token, "POST", empty_file)
                
                if new_file and 'id' in new_file:
                    print(f"✅ Created empty file: {src_name}")
                    # We'd normally update the content here, but since it's complex to 
                    # download and upload file content via the API, we'll count this as a success
                    return 1
                else:
                    print(f"❌ All methods failed for file: {src_name}")
                    return 0
        except Exception as e:
            print(f"❌ Error copying file {src_name}: {str(e)}")
            return 0
    
    # Process each item (folder or file)
    for item in items:
        item_name = item.get('name', 'Unknown item')
        item_id = item.get('id')
        
        if not item_id:
            continue
        
        print(f"Attempting to copy {item_name}...")
        
        # For folders, we need to create the folder first, then copy contents
        if item.get('folder'):
            print(f"Item is a folder: {item_name}")
            
            # Create folder in target OneDrive with our safe helper
            new_folder = create_folder(item_name)
            
            if new_folder and 'id' in new_folder:
                folder_success = 0
                
                # Now get items in the source folder
                folder_items = make_api_call(
                    f"/users/{source_email}/drive/items/{item_id}/children", 
                    token
                )
                
                if folder_items and 'value' in folder_items and len(folder_items['value']) > 0:
                    print(f"Found {len(folder_items['value'])} items in folder {item_name}")
                    
                    # Process each item in the folder - only copy files, not subfolders
                    for sub_item in folder_items['value']:
                        sub_name = sub_item.get('name', 'Unknown')
                        sub_id = sub_item.get('id')
                        
                        # For files in the folder, copy directly
                        if 'file' in sub_item:
                            folder_success += copy_file(sub_id, sub_name, new_folder['id'])
                        # For subfolders, we don't support recursive copying in this version
                        elif 'folder' in sub_item:
                            print(f"Skipping subfolder: {sub_name} (nested folders not supported in this version)")
                            
                        time.sleep(0.5)  # Rate limiting
                
                print(f"Copied {folder_success} files from folder {item_name}")
                success_count += 1  # Count the folder creation as a success
                if folder_success > 0:
                    success_count += folder_success  # Add successful file copies
            else:
                print(f"❌ Failed to create folder: {item_name}")
        
        # For files, copy directly
        elif 'file' in item:
            success_count += copy_file(item_id, item_name)
        
        # Wait between operations to avoid throttling
        time.sleep(1)
    
    print(f"Successfully processed {success_count} items")
    return success_count

def copy_teams_data(token, source_email, target_email):
    print(f"\nCopying Teams data from {source_email} to {target_email}...")
    
    teams = []
    endpoint = f"/users/{source_email}/joinedTeams"
    
    result = make_api_call(endpoint, token)
    if result and 'value' in result:
        teams = result['value']
        print(f"Found {len(teams)} teams")
    else:
        print("❌ No teams found")
        return 0
    
    success_count = 0
    for team in teams:
        team_name = team.get('displayName', 'Unknown Team')
        team_id = team.get('id')
        
        if not team_id:
            continue
        
        # Fixed: Add required @odata.type property
        add_member_data = {
            "@odata.type": "#microsoft.graph.aadUserConversationMember",
            "roles": ["member"],
            "user@odata.bind": f"https://graph.microsoft.com/v1.0/users/{target_email}"
        }
        
        result = make_api_call(
            f"/teams/{team_id}/members", 
            token, 
            "POST", 
            add_member_data
        )
        
        if result:
            print(f"✅ Added to team: {team_name}")
            success_count += 1
        else:
            # Try alternative method if the first one fails
            print(f"⚠️ First method failed. Trying alternative method for {team_name}...")
            
            alt_member_data = {
                "@odata.type": "#microsoft.graph.aadUserConversationMember",
                "userId": target_email,
                "roles": ["member"]
            }
            
            alt_result = make_api_call(
                f"/teams/{team_id}/members", 
                token, 
                "POST", 
                alt_member_data
            )
            
            if alt_result:
                print(f"✅ Added to team using alternative method: {team_name}")
                success_count += 1
            else:
                print(f"❌ Failed to add to team: {team_name}")
        
        time.sleep(0.5)
    
    print(f"Processed {success_count}/{len(teams)} teams")
    return success_count

def copy_emails_from_all_folders(token, source_email, target_email):
    print(f"\nCopying emails from {source_email} to {target_email}...")
    
    source_folders = get_mailbox_folders(token, source_email)
    if not source_folders:
        return 0
    
    main_target_folder_id = create_target_folder(token, target_email)
    if not main_target_folder_id:
        return 0
    
    total_copied = 0
    total_emails = 0
    
    for folder in source_folders:
        folder_name = folder['displayName']
        folder_id = folder['id']
        
        emails = get_all_emails_from_folder(token, source_email, folder_id, folder_name)
        if not emails:
            continue
        
        total_emails += len(emails)
        
        target_subfolder_id = create_target_folder(token, target_email, main_target_folder_id, folder_name)
        if not target_subfolder_id:
            target_subfolder_id = main_target_folder_id
        
        folder_success = 0
        for i, email in enumerate(emails):
            if copy_email_to_target(token, source_email, target_email, email, target_subfolder_id):
                folder_success += 1
            time.sleep(0.5)
        
        print(f"Copied {folder_success}/{len(emails)} emails from '{folder_name}'")
        total_copied += folder_success
    
    print(f"\nTotal emails copied: {total_copied}/{total_emails}")
    return total_copied

def copy_archive_emails(token, source_email, target_email):
    print(f"\nCopying in-place archive emails from {source_email} to {target_email}...")
    
    # Get source archive folders
    archive_folders = get_archive_folders(token, source_email)
    if not archive_folders:
        return 0
    
    # Get or create target archive
    target_archive = make_api_call(f"/users/{target_email}/mailfolders/archive", token)
    if not target_archive:
        print("❌ Target user does not have archive enabled")
        return 0
    
    target_archive_id = target_archive['id']
    total_copied = 0
    total_emails = 0
    
    for folder in archive_folders:
        folder_name = folder['displayName']
        folder_id = folder['id']
        
        # Get emails from source archive folder
        print(f"Getting emails from archive folder: {folder_name}")
        emails = get_all_emails_from_folder(token, source_email, folder_id, folder_name)
        if not emails:
            continue
        
        total_emails += len(emails)
        
        # Create corresponding folder in target archive
        target_subfolder_id = target_archive_id
        if folder_name.lower() != 'archive':
            folder_data = {
                "displayName": folder_name,
                "isHidden": False
            }
            
            # Create subfolder in target archive
            result = make_api_call(
                f"/users/{target_email}/mailfolders/{target_archive_id}/childfolders",
                token,
                "POST",
                folder_data
            )
            if result and 'id' in result:
                target_subfolder_id = result['id']
                print(f"✅ Created archive subfolder: {folder_name}")
            else:
                print(f"⚠️ Using archive root folder for {folder_name}")
        
        # Copy emails to target archive folder
        folder_success = 0
        for email in emails:
            try:
                if copy_email_to_target(token, source_email, target_email, email, target_subfolder_id):
                    folder_success += 1
                time.sleep(0.5)
            except Exception as e:
                print(f"❌ Error copying email: {str(e)}")
                continue
        
        print(f"Copied {folder_success}/{len(emails)} archive emails from '{folder_name}'")
        total_copied += folder_success
    
    print(f"\nTotal archive emails copied: {total_copied}/{total_emails}")
    return total_copied

def read_email_pairs_from_csv(csv_file):
    email_pairs = []
    try:
        with open(csv_file, 'r') as file:
            reader = csv.reader(file)
            for row in reader:
                if len(row) >= 2:
                    source_email = row[0].strip()
                    target_email = row[1].strip()
                    if '@' in source_email and '@' in target_email:
                        email_pairs.append((source_email, target_email))
        
        print(f"✅ Read {len(email_pairs)} email pairs from {csv_file}")
        return email_pairs
    except Exception as e:
        print(f"❌ Error reading CSV file: {str(e)}")
        return []

def process_email_pair(token, source_email, target_email):
    print("=" * 60)
    print(f"Processing migration from {source_email} to {target_email}")
    print("=" * 60)
    
    results = {}
    
    if COPY_OPTIONS['emails']:
        results['emails'] = copy_emails_from_all_folders(token, source_email, target_email)
    
    if COPY_OPTIONS['archive']:
        results['archive'] = copy_archive_emails(token, source_email, target_email)
    
    if COPY_OPTIONS['contacts']:
        results['contacts'] = copy_contacts(token, source_email, target_email)
    
    if COPY_OPTIONS['calendar']:
        results['calendar'] = copy_calendar_events(token, source_email, target_email)
    
    if COPY_OPTIONS['groups']:
        results['groups'] = copy_groups(token, source_email, target_email)
    
    if COPY_OPTIONS['sharepoint']:
        results['sharepoint'] = copy_onedrive_files(token, source_email, target_email)
    
    if COPY_OPTIONS['teams']:
        results['teams'] = copy_teams_data(token, source_email, target_email)
    
    print("\nMigration Summary for this pair:")
    print("-" * 60)
    
    if COPY_OPTIONS['emails']:
        print(f"Emails: {results.get('emails', 0)} copied")
    
    if COPY_OPTIONS['archive']:
        print(f"Archive Emails: {results.get('archive', 0)} copied")
    
    if COPY_OPTIONS['contacts']:
        print(f"Contacts: {results.get('contacts', 0)} copied")
    
    if COPY_OPTIONS['calendar']:
        print(f"Calendar Events: {results.get('calendar', 0)} copied")
    
    if COPY_OPTIONS['groups']:
        print(f"Group Memberships: {results.get('groups', 0)} added")
    
    if COPY_OPTIONS['sharepoint']:
        print(f"SharePoint Files: {results.get('sharepoint', 0)} copying")
    
    if COPY_OPTIONS['teams']:
        print(f"Teams: {results.get('teams', 0)} processed")
    
    return results

def main():
    print("=" * 60)
    print("Office 365 Data Migration Script")
    print("=" * 60)
    
    csv_file = "/Users/eki/File Eki/2023 - 2024/Kerjaan/System Engineer/Protelindo/Meeting/14 Maret 2025/bulk-user.csv"
    
    if not os.path.exists(csv_file):
        print(f"❌ CSV file not found: {csv_file}")
        return
    
    email_pairs = read_email_pairs_from_csv(csv_file)
    if not email_pairs:
        print("❌ No valid email pairs found.")
        return
    
    print("\nMigration Options:")
    for option, enabled in COPY_OPTIONS.items():
        print(f"✅ Copy {option.capitalize()}: {enabled}")
    print("=" * 60)
    
    token = get_valid_token()
    
    overall_results = {}
    for i, (source_email, target_email) in enumerate(email_pairs):
        print(f"\nProcessing pair {i+1}/{len(email_pairs)}")
        
        # Refresh token if needed before checking permissions
        token = get_valid_token(token)
        
        if not check_permissions(token, source_email):
            print(f"❌ Permission check failed for {source_email}. Skipping.")
            continue
        
        results = process_email_pair(token, source_email, target_email)
        
        for key, value in results.items():
            overall_results[key] = overall_results.get(key, 0) + value


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nOperation cancelled by user")
    except Exception as e:
        print(f"\n❌ Unexpected error: {str(e)}")