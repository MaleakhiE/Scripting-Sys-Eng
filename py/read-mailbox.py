#!/usr/bin/env python3
import requests
import json
import msal

# Config
CLIENT_ID = '14dfa8f3-e0e9-420c-889a-f7c3d369f604'
CLIENT_SECRET = 'bZF8Q~0~OP9UDByaJ1JP3ElR6rAv~3ENew.u4cg1'
TENANT_ID = '39c345ae-bf0d-40bf-aba9-081979356879'
SCOPE = ['https://graph.microsoft.com/.default']

# Prompt user input
user_email = input("Enter the email address to read messages from: ").strip()

# MSAL app
authority = f"https://login.microsoftonline.com/{TENANT_ID}"
app = msal.ConfidentialClientApplication(
    CLIENT_ID,
    authority=authority,
    client_credential=CLIENT_SECRET
)

# Acquire token
result = app.acquire_token_for_client(scopes=SCOPE)

if "access_token" in result:
    access_token = result['access_token']
    headers = {
        'Authorization': f'Bearer {access_token}',
        'Content-Type': 'application/json'
    }
    # Call Graph API
    mail_url = f"https://graph.microsoft.com/v1.0/users/{user_email}/mailFolders/Inbox/messages?$top=5"
    try:
        response = requests.get(mail_url, headers=headers, timeout=10)
    except requests.RequestException as e:
        print(f"Error connecting to Microsoft Graph: {e}")
        exit(1)
        
    if response.status_code == 200:
        messages = response.json()
        print(f"\n✅ Successfully retrieved messages from: {user_email}\n")
        if 'value' in messages and messages['value']:
            for message in messages['value']:
                print(f"Subject: {message.get('subject')}")
                from_addr = message.get('from', {}).get('emailAddress', {}).get('address', 'Unknown')
                print(f"From: {from_addr}")
                print(f"Received: {message.get('receivedDateTime')}")
                print(f"Body Preview: {message.get('bodyPreview', '')[:100]}...\n")
        else:
            print("No messages found in the Inbox.")
    else:
        print(f"❌ Failed to retrieve messages ({response.status_code}):")
        try:
            print(json.dumps(response.json(), indent=2))
        except:
            print(response.text)
else:
    print(f"❌ Failed to acquire token. Details:\n{json.dumps(result, indent=2)}")
