import requests
import json
import msal

# Define Azure AD authentication parameters
CLIENT_ID = '14dfa8f3-e0e9-420c-889a-f7c3d369f604'
CLIENT_SECRET = 'bZF8Q~0~OP9UDByaJ1JP3ElR6rAv~3ENew.u4cg1'
TENANT_ID = '39c345ae-bf0d-40bf-aba9-081979356879'
SCOPE = ['https://graph.microsoft.com/.default']

# Define email properties
sender_email = str(input("Enter sender email address: "))
recipient_email = str(input("Enter receiver email address: "))
subject = 'Test MSGraph'
content = str(input("Enter email content: "))
body = {'contentType': 'Text', 'content': content}

# Authenticate using MSAL
authority = f"https://login.microsoftonline.com/{TENANT_ID}"
app = msal.ConfidentialClientApplication(CLIENT_ID, authority=authority, client_credential=CLIENT_SECRET)

result = app.acquire_token_for_client(scopes=SCOPE)

if 'access_token' in result:
    headers = {'Authorization': 'Bearer ' + result['access_token'], 'Content-Type': 'application/json'}

    # Send mail
    mail_url = "https://graph.microsoft.com/v1.0/users/" + sender_email + "/sendMail"
    mail_body = {
        "message": {
            "subject": subject,
            "body": body,
            "toRecipients": [{"emailAddress": {"address": recipient_email}}]
        },
        "saveToSentItems": "true"
    }
    
    response = requests.post(mail_url, headers=headers, data=json.dumps(mail_body))
    
    if response.status_code == 202:
        print("Email sent successfully, from:", sender_email, "to:", recipient_email)
    else:
        print("Failed to send email:", response.text)
else:
    print("Failed to acquire token.")
