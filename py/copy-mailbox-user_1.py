import os
import time
import datetime
import requests
import json
import sys
from pprint import pprint
import msal  # Microsoft Authentication Library

# Configuration
SOURCE_EMAIL = "maleakhi@dikstrasolusi.com"
TARGET_EMAIL = "ekitest@dikstrasolusi.com"
TARGET_FOLDER = "Imported"  # Main folder for imported emails

# Azure AD app registration details
CLIENT_ID = "14dfa8f3-e0e9-420c-889a-f7c3d369f604"
CLIENT_SECRET = "p8L8Q~Cu6ekc1z6J6PPEGho2eWOPjoNQbyzRjct_"
TENANT_ID = "39c345ae-bf0d-40bf-aba9-081979356879"

# Authentication and API endpoints
AUTHORITY = f"https://login.microsoftonline.com/{TENANT_ID}"
SCOPES = ["https://graph.microsoft.com/.default"]
GRAPH_ENDPOINT = "https://graph.microsoft.com/v1.0"

# Migration options
COPY_OPTIONS = {
    "emails": False,           
    "contacts": True,         
    "calendar": True,         
    "groups": False,           
    "sharepoint": False,       
    "teams": False             
}

def get_access_token():
    """Get Microsoft Graph API access token"""
    app = msal.ConfidentialClientApplication(
        client_id=CLIENT_ID,
        client_credential=CLIENT_SECRET,
        authority=AUTHORITY
    )
    
    # Get token using client credentials flow
    result = app.acquire_token_for_client(scopes=SCOPES)
    
    if "access_token" in result:
        print("✅ Successfully obtained access token")
        return result["access_token"]
    else:
        print(f"❌ Error getting token: {result.get('error')}")
        print(f"Error description: {result.get('error_description')}")
        print("\nPossible solutions:")
        print("1. Verify your CLIENT_ID, CLIENT_SECRET, and TENANT_ID are correct")
        print("2. Ensure your Azure AD app has sufficient API permissions")
        exit(1)

def check_permissions(token):
    """Check if the app has required permissions"""
    print("Checking permissions...")
    
    # Try to get information about the current app
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    
    # Try to get current user to check if token works
    response = requests.get(f"{GRAPH_ENDPOINT}/me", headers=headers)
    if response.status_code == 401:
        print("❌ Token is invalid or expired")
        return False
    
    # Check if app has Mail.ReadWrite permission
    try:
        # Try to list mailboxes to check for proper permissions
        response = requests.get(f"{GRAPH_ENDPOINT}/users/{SOURCE_EMAIL}/mailFolders", headers=headers)
        if response.status_code >= 400:
            print("❌ Permission check failed. The app may not have required permissions.")
            print(f"Error: {response.status_code} - {response.text}")
            print("\nPlease ensure your Azure AD app has these API permissions:")
            print("- Mail.ReadWrite")
            print("- Mail.Send")
            print("- Mail.ReadWrite.Shared")
            print("- User.Read.All")
            print("- Contacts.ReadWrite")
            print("- Calendars.ReadWrite")
            print("- Group.ReadWrite.All")
            print("- Files.ReadWrite.All")
            print("- Team.ReadBasic.All")
            print("- ChannelMessage.Read.All")
            print("- Chat.ReadWrite")
            return False
        else:
            print("✅ App has sufficient permissions to access mailboxes")
            return True
    except Exception as e:
        print(f"❌ Error checking permissions: {str(e)}")
        return False

def make_api_call(endpoint, token, method="GET", data=None):
    """Make an API call to Microsoft Graph with better error handling"""
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
        
        if response.status_code >= 400:
            print(f"❌ API call failed: {method} {endpoint}")
            print(f"Status code: {response.status_code}")
            print(f"Error: {response.text}")
            
            if response.status_code == 403:
                print("\nAccess denied. This typically means:")
                print("1. The app doesn't have sufficient permissions")
                print("2. The app hasn't been granted admin consent")
                print("3. The app might be trying to access a feature it's not allowed to")
            return None
        
        return response.json() if response.content else None
    except Exception as e:
        print(f"❌ Error making API call: {str(e)}")
        return None

def get_mailbox_folders(token, email):
    """Get all folders in a mailbox"""
    print(f"Retrieving folders for {email}...")
    
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

def create_target_folder(token, parent_id=None, folder_name=None):
    """Create or find a folder in the target mailbox"""
    folder_name = folder_name or TARGET_FOLDER
    print(f"Creating/finding target folder '{folder_name}' in {TARGET_EMAIL}...")
    
    # Endpoint for searching folders
    endpoint = f"/users/{TARGET_EMAIL}/mailFolders"
    if parent_id:
        endpoint = f"/users/{TARGET_EMAIL}/mailFolders/{parent_id}/childFolders"
    
    # First, try to find if the folder already exists
    folders = make_api_call(endpoint, token)
    
    if folders and 'value' in folders:
        for folder in folders['value']:
            if folder['displayName'].lower() == folder_name.lower():
                print(f"✅ Found existing folder: {folder['displayName']} (ID: {folder['id']})")
                return folder['id']
    
    # If not found, try to create it
    folder_data = {
        "displayName": folder_name,
        "isHidden": False
    }
    
    # Create folder
    result = make_api_call(endpoint, token, "POST", folder_data)
    
    if result:
        print(f"✅ Created folder: {result['displayName']} (ID: {result['id']})")
        return result['id']
    else:
        print(f"❌ Failed to create folder '{folder_name}'")
        
        # If creation failed and this is the main target folder, try to use Inbox
        if folder_name == TARGET_FOLDER and not parent_id:
            print("Will try to use the Inbox folder instead.")
            inbox = make_api_call(f"/users/{TARGET_EMAIL}/mailFolders/inbox", token)
            if inbox and 'id' in inbox:
                print(f"Using Inbox folder (ID: {inbox['id']})")
                return inbox['id']
    
        print("❌ Could not find or create the folder.")
        return None

def get_all_emails_from_folder(token, email, folder_id, folder_name, page_size=50):
    """Get all emails from a specific folder"""
    print(f"Retrieving emails from '{folder_name}' folder...")
    
    endpoint = f"/users/{email}/mailFolders/{folder_id}/messages?$top={page_size}"
    emails = []
    page = 1
    
    while endpoint:
        print(f"Fetching page {page}...")
        result = make_api_call(endpoint, token)
        if not result:
            print(f"❌ Failed to retrieve emails from '{folder_name}'. Stopping.")
            break
            
        batch = result.get('value', [])
        emails.extend(batch)
        print(f"Retrieved {len(batch)} emails on this page, {len(emails)} total from '{folder_name}'")
        
        # Check if there are more pages
        if '@odata.nextLink' in result:
            endpoint = result['@odata.nextLink'].replace(GRAPH_ENDPOINT, '')
            page += 1
        else:
            endpoint = None
    
    print(f"Total emails retrieved from '{folder_name}': {len(emails)}")
    return emails

def copy_email_to_target(token, email, target_folder_id):
    """Copy a single email from source to target mailbox"""
    try:
        email_id = email['id']
        subject = email.get('subject', '(No Subject)')
        
        # Get the full email content
        full_email = make_api_call(f"/users/{SOURCE_EMAIL}/messages/{email_id}", token)
        
        if not full_email:
            print(f"❌ Failed to get full email content for: {subject}")
            return False
        
        # Prepare the email for copying
        new_email = {
            "subject": full_email.get('subject', '(No Subject)'),
            "body": full_email.get('body', {"contentType": "text", "content": ""}),
            "toRecipients": [{"emailAddress": {"address": TARGET_EMAIL}}],  # Only send to TARGET_EMAIL
            "importance": full_email.get('importance', 'normal'),
            # Add additional properties like receivedDateTime if needed
            "receivedDateTime": full_email.get('receivedDateTime')
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
            f"/users/{TARGET_EMAIL}/mailFolders/{target_folder_id}/messages", 
            token, 
            "POST", 
            new_email
        )
        
        if result:
            print(f"✅ Successfully copied: {subject}")
            return True
        else:
            print(f"❌ Failed to copy: {subject}")
            return False
    except Exception as e:
        print(f"❌ Error copying email: {str(e)}")
        return False

def copy_contacts(token):
    """Copy contacts from source to target account"""
    print("\nCopying contacts...")
    
    # Get contacts from source account
    contacts = []
    endpoint = f"/users/{SOURCE_EMAIL}/contacts"
    
    result = make_api_call(endpoint, token)
    if result and 'value' in result:
        contacts = result['value']
        print(f"Found {len(contacts)} contacts to copy")
    else:
        print("❌ Failed to retrieve contacts or no contacts found")
        return 0
    
    # Copy each contact to target account
    success_count = 0
    for contact in contacts:
        contact_name = contact.get('displayName', 'Unknown Contact')
        print(f"Copying contact: {contact_name}")
        
        # Create simplified contact object
        new_contact = {
            "givenName": contact.get('givenName', ''),
            "surname": contact.get('surname', ''),
            "displayName": contact.get('displayName', ''),
            "emailAddresses": contact.get('emailAddresses', []),
            "mobilePhone": contact.get('mobilePhone', ''),
            "businessPhones": contact.get('businessPhones', []),
            "personalNotes": contact.get('personalNotes', '')
        }
        
        # Create contact in target account
        result = make_api_call(f"/users/{TARGET_EMAIL}/contacts", token, "POST", new_contact)
        
        if result:
            print(f"✅ Successfully copied contact: {contact_name}")
            success_count += 1
        else:
            print(f"❌ Failed to copy contact: {contact_name}")
        
        time.sleep(0.5)  # Add delay to avoid throttling
    
    print(f"Copied {success_count}/{len(contacts)} contacts")
    return success_count

def copy_calendar_events(token):
    """Copy calendar events from source to target account"""
    print("\nCopying calendar events...")
    
    # Get events from source calendar
    events = []
    # Start date: events from the past year
    start_date = (datetime.datetime.now() - datetime.timedelta(days=365)).isoformat()
    endpoint = f"/users/{SOURCE_EMAIL}/calendar/events?startDateTime={start_date}"
    
    result = make_api_call(endpoint, token)
    if result and 'value' in result:
        events = result['value']
        print(f"Found {len(events)} calendar events to copy")
    else:
        print("❌ Failed to retrieve calendar events or no events found")
        return 0
    
    # Copy each event to target account
    success_count = 0
    for event in events:
        event_subject = event.get('subject', 'Untitled Event')
        print(f"Copying event: {event_subject}")
        
        # Create simplified event object with only the target email as attendee
        new_event = {
            "subject": event.get('subject', 'Untitled Event'),
            "body": event.get('body', {"contentType": "text", "content": ""}),
            "start": event.get('start', {"dateTime": "2023-01-01T00:00:00", "timeZone": "UTC"}),
            "end": event.get('end', {"dateTime": "2023-01-01T01:00:00", "timeZone": "UTC"}),
            "location": event.get('location', {"displayName": ""}),
            # Only include the target email as attendee regardless of original attendees
            "attendees": [
                {
                    "emailAddress": {
                        "address": TARGET_EMAIL,
                        "name": TARGET_EMAIL.split('@')[0]
                    },
                    "type": "required"
                }
            ]
        }
        
        # Create event in target calendar
        result = make_api_call(f"/users/{TARGET_EMAIL}/calendar/events", token, "POST", new_event)
        
        if result:
            print(f"✅ Successfully copied event: {event_subject}")
            success_count += 1
        else:
            print(f"❌ Failed to copy event: {event_subject}")
        
        time.sleep(0.5)  # Add delay to avoid throttling
    
    print(f"Copied {success_count}/{len(events)} calendar events")
    return success_count

def copy_groups(token):
    """Copy group memberships from source to target user"""
    print("\nCopying group memberships...")
    
    # Get groups the source user is a member of
    groups = []
    endpoint = f"/users/{SOURCE_EMAIL}/memberOf"
    
    result = make_api_call(endpoint, token)
    if result and 'value' in result:
        groups = [g for g in result['value'] if g.get('@odata.type') == '#microsoft.graph.group']
        print(f"Found {len(groups)} groups to copy")
    else:
        print("❌ Failed to retrieve groups or no groups found")
        return 0
    
    # Add target user to each group
    success_count = 0
    for group in groups:
        group_name = group.get('displayName', 'Unknown Group')
        group_id = group.get('id')
        
        if not group_id:
            print(f"❌ Missing ID for group: {group_name}")
            continue
            
        print(f"Adding {TARGET_EMAIL} to group: {group_name}")
        
        # Add member to group
        add_member_data = {
            "@odata.id": f"{GRAPH_ENDPOINT}/users/{TARGET_EMAIL}"
        }
        
        result = make_api_call(
            f"/groups/{group_id}/members/$ref", 
            token, 
            "POST", 
            add_member_data
        )
        
        if result is not None:  # Success returns empty response
            print(f"✅ Successfully added to group: {group_name}")
            success_count += 1
        else:
            print(f"❌ Failed to add to group: {group_name}")
        
        time.sleep(0.5)  # Add delay to avoid throttling
    
    print(f"Added to {success_count}/{len(groups)} groups")
    return success_count

def copy_onedrive_files(token):
    """Copy OneDrive/SharePoint files from source to target user"""
    print("\nCopying OneDrive files...")
    
    # Get source user's drive
    source_drive = make_api_call(f"/users/{SOURCE_EMAIL}/drive", token)
    target_drive = make_api_call(f"/users/{TARGET_EMAIL}/drive", token)
    
    if not source_drive or not target_drive:
        print("❌ Failed to access OneDrive for one or both users")
        return 0
        
    print(f"Source drive: {source_drive.get('name')} (ID: {source_drive.get('id')})")
    print(f"Target drive: {target_drive.get('name')} (ID: {target_drive.get('id')})")
    
    # Get root items from source drive
    items = []
    result = make_api_call(f"/users/{SOURCE_EMAIL}/drive/root/children", token)
    
    if result and 'value' in result:
        items = result['value']
        print(f"Found {len(items)} files/folders to copy")
    else:
        print("❌ Failed to retrieve OneDrive items or no items found")
        return 0
    
    # Copy top-level items (simplified approach)
    success_count = 0
    for item in items:
        item_name = item.get('name', 'Unknown item')
        item_id = item.get('id')
        
        if not item_id:
            print(f"❌ Missing ID for item: {item_name}")
            continue
            
        print(f"Copying item: {item_name}")
        
        # Create copy request
        copy_data = {
            "parentReference": {
                "driveId": target_drive.get('id'),
                "path": "/drive/root:"
            },
            "name": item_name
        }
        
        # Initiate copy operation
        result = make_api_call(
            f"/users/{SOURCE_EMAIL}/drive/items/{item_id}/copy", 
            token, 
            "POST", 
            copy_data
        )
        
        if result is not None:
            print(f"✅ Copy initiated for: {item_name}")
            success_count += 1
        else:
            print(f"❌ Failed to copy: {item_name}")
        
        time.sleep(1)  # Add longer delay for file operations
    
    print(f"Initiated copy for {success_count}/{len(items)} items")
    print("Note: Large files may take time to complete copying in the background")
    return success_count

def copy_teams_data(token):
    """Copy Teams chats and channel messages"""
    print("\nCopying Teams data...")
    
    # This is a simplified implementation that demonstrates the concept
    # A full implementation would require more complex handling
    
    # Get teams the source user is a member of
    teams = []
    endpoint = f"/users/{SOURCE_EMAIL}/joinedTeams"
    
    result = make_api_call(endpoint, token)
    if result and 'value' in result:
        teams = result['value']
        print(f"Found {len(teams)} teams to process")
    else:
        print("❌ Failed to retrieve teams or no teams found")
        return 0
    
    # For each team, get channels and messages
    success_count = 0
    for team in teams:
        team_name = team.get('displayName', 'Unknown Team')
        team_id = team.get('id')
        
        if not team_id:
            print(f"❌ Missing ID for team: {team_name}")
            continue
            
        print(f"Processing team: {team_name}")
        
        # Add target user to the team if not already a member
        add_member_data = {
            "@odata.id": f"{GRAPH_ENDPOINT}/users/{TARGET_EMAIL}"
        }
        
        result = make_api_call(
            f"/teams/{team_id}/members", 
            token, 
            "POST", 
            add_member_data
        )
        
        if result:
            print(f"✅ Added {TARGET_EMAIL} to team: {team_name}")
            success_count += 1
        else:
            print(f"❌ Failed to add to team or already a member: {team_name}")
        
        time.sleep(0.5)  # Add delay to avoid throttling
    
    print(f"Processed {success_count}/{len(teams)} teams")
    print("Note: Teams data migration is complex and this is a simplified implementation")
    return success_count

def copy_emails_from_all_folders(token):
    """Copy emails from all folders in source mailbox to corresponding folders in target"""
    print("\nCopying emails from all folders...")
    
    # Get all folders from source mailbox
    source_folders = get_mailbox_folders(token, SOURCE_EMAIL)
    if not source_folders:
        print("❌ No folders found in source mailbox")
        return 0
    
    # Create main import folder in target
    main_target_folder_id = create_target_folder(token)
    if not main_target_folder_id:
        print("❌ Failed to create main target folder")
        return 0
    
    total_copied = 0
    total_emails = 0
    
    # Process each folder
    for folder in source_folders:
        folder_name = folder['displayName']
        folder_id = folder['id']
        
        print(f"\nProcessing folder: {folder_name}")
        
        # Get emails from this folder
        emails = get_all_emails_from_folder(token, SOURCE_EMAIL, folder_id, folder_name)
        if not emails:
            print(f"No emails found in folder '{folder_name}'. Skipping.")
            continue
        
        total_emails += len(emails)
        
        # Create corresponding subfolder in target
        target_subfolder_id = create_target_folder(token, main_target_folder_id, folder_name)
        if not target_subfolder_id:
            print(f"❌ Failed to create target folder for '{folder_name}'. Using main folder.")
            target_subfolder_id = main_target_folder_id
        
        # Copy emails to target subfolder
        folder_success = 0
        for i, email in enumerate(emails):
            print(f"Copying email {i+1}/{len(emails)} from '{folder_name}': {email.get('subject', '(No Subject)')}")
            if copy_email_to_target(token, email, target_subfolder_id):
                folder_success += 1
            time.sleep(0.5)  # Add delay to avoid throttling
        
        print(f"Copied {folder_success}/{len(emails)} emails from folder '{folder_name}'")
        total_copied += folder_success
    
    print(f"\nTotal emails copied: {total_copied}/{total_emails} from all folders")
    return total_copied

def main():
    print("=" * 60)
    print("Office 365 Data Migration Script")
    print("=" * 60)
    print(f"Source: {SOURCE_EMAIL}")
    print(f"Target: {TARGET_EMAIL}")
    print("\nMigration Options:")
    print(f"✅ Copy Emails (All folders): {COPY_OPTIONS['emails']}")
    print(f"✅ Copy Contacts: {COPY_OPTIONS['contacts']}")
    print(f"✅ Copy Calendar Events: {COPY_OPTIONS['calendar']}")
    print(f"✅ Copy Groups (Memberships): {COPY_OPTIONS['groups']}")
    print(f"✅ Copy SharePoint Files (OneDrive): {COPY_OPTIONS['sharepoint']}")
    print(f"✅ Copy Teams Data (Chats & Channels): {COPY_OPTIONS['teams']}")
    print("=" * 60)
    
    # Get access token
    print("\nStep 1: Authentication")
    token = get_access_token()
    
    # Check permissions
    print("\nStep 2: Permission Check")
    if not check_permissions(token):
        print("❌ Permission check failed. Please fix the permissions and try again.")
        sys.exit(1)
    
    # Show available folders
    print("\nStep 3: Mailbox Exploration")
    print("Source mailbox folders:")
    get_mailbox_folders(token, SOURCE_EMAIL)
    
    print("\nTarget mailbox folders:")
    get_mailbox_folders(token, TARGET_EMAIL)
    
    # Copy data based on migration options
    results = {}
    
    # Copy emails from all folders
    if COPY_OPTIONS['emails']:
        results['emails'] = copy_emails_from_all_folders(token)
    
    # Copy contacts
    if COPY_OPTIONS['contacts']:
        results['contacts'] = copy_contacts(token)
    
    # Copy calendar events
    if COPY_OPTIONS['calendar']:
        results['calendar'] = copy_calendar_events(token)
    
    # Copy group memberships
    if COPY_OPTIONS['groups']:
        results['groups'] = copy_groups(token)
    
    # Copy OneDrive files
    if COPY_OPTIONS['sharepoint']:
        results['sharepoint'] = copy_onedrive_files(token)
    
    # Copy Teams data
    if COPY_OPTIONS['teams']:
        results['teams'] = copy_teams_data(token)
    
    # Print final summary
    print("\nMigration Summary:")
    print("=" * 60)
    
    if COPY_OPTIONS['emails']:
        print(f"Emails: {results.get('emails', 0)} copied")
    
    if COPY_OPTIONS['contacts']:
        print(f"Contacts: {results.get('contacts', 0)} copied")
    
    if COPY_OPTIONS['calendar']:
        print(f"Calendar Events: {results.get('calendar', 0)} copied")
    
    if COPY_OPTIONS['groups']:
        print(f"Group Memberships: {results.get('groups', 0)} added")
    
    if COPY_OPTIONS['sharepoint']:
        print(f"SharePoint/OneDrive Files: {results.get('sharepoint', 0)} copy operations initiated")
    
    if COPY_OPTIONS['teams']:
        print(f"Teams: {results.get('teams', 0)} teams processed")
    
    print("\nMigration completed. Some operations may continue in the background.")
    print("Check the target account to verify all data has been transferred successfully.")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nOperation cancelled by user")
    except Exception as e:
        print(f"\n❌ Unexpected error: {str(e)}")