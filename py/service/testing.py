import requests
import os

def main():
    # Load credentials from environment variables
    client_id = '14dfa8f3-e0e9-420c-889a-f7c3d369f604'
    client_secret = 'pQv8Q~oFocVPMQpjF3LLNEA_vn53lI4a3FXdQbMp'
    tenant_id = '39c345ae-bf0d-40bf-aba9-081979356879'
    access_token_url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
    
    # Define EWS endpoint and headers
    ews_endpoint = 'https://outlook.office.com/EWS/Exchange.asmx'
    headers = {
        'Authorization': f'Bearer {get_access_token(client_id, client_secret, tenant_id)}',
        'Content-Type': 'application/json'
    }

    # Make an EWS call
    response = requests.get(ews_endpoint, headers=headers)
    
    if response.status_code == 200:
        print("Successfully connected to EWS.")
        # Send email
        send_email(headers)
    else:
        print(f"Failed to connect to EWS. Status code: {response.status_code}")

def get_access_token(client_id, client_secret, tenant_id):
    token_payload = {
        'client_id': client_id,
        'client_secret': client_secret,
        'grant_type': 'client_credentials',
        'scope': 'https://outlook.office.com/.default'
    }
    response = requests.post(f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token", data=token_payload)
    if response.status_code == 200:
        return response.json()['access_token']
    else:
        print(f"Failed to get access token. Status code: {response.status_code}")
        return None

def send_email(headers):
    email_payload = {
        "message": {
            "subject": "Test Email",
            "body": {
                "contentType": "Text",
                "content": "This is a test email."
            },
            "toRecipients": [
                {
                    "emailAddress": {
                        "address": "ekiputra234@gmail.com"
                    }
                }
            ]
        },
        "saveToSentItems": "true"
    }
    email_url = 'https://outlook.office.com/api/v2.0/me/sendmail'
    response = requests.post(email_url, headers=headers, json=email_payload)
    if response.status_code == 202:
        print("Email sent successfully.")
    else:
        print(f"Failed to send email. Status code: {response.status_code}")

if __name__ == "__main__":
    main()
