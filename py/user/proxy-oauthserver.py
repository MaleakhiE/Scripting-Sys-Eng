from flask import Flask, request, jsonify
import requests
import base64
import xml.etree.ElementTree as ET

app = Flask(__name__)

# Microsoft Graph API endpoints
GRAPH_API_SEND_MAIL_URL = "https://graph.microsoft.com/v1.0/me/sendMail"
GRAPH_API_READ_MAIL_URL = "https://graph.microsoft.com/v1.0/me/messages"

@app.route('/send_email', methods=['POST'])
def send_email():
    # Extract Azure AD credentials and XML payload from JSON body
    data = request.get_json()
    if not data:
        return jsonify({"error": "Invalid JSON payload"}), 400

    client_id = data.get("client_id")
    client_secret = data.get("client_secret")
    tenant_id = data.get("tenant_id")
    xml_payload = data.get("xml_payload")

    # Validate Azure AD credentials
    if not client_id or not client_secret or not tenant_id:
        return jsonify({"error": "Missing Azure AD credentials in JSON payload"}), 400

    # Extract Basic Auth credentials from the request header
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Basic "):
        return jsonify({"error": "Invalid Authorization header"}), 400

    encoded_creds = auth_header.split(" ")[1]
    decoded_creds = base64.b64decode(encoded_creds).decode("utf-8")
    username, password = decoded_creds.split(":")

    # Parse the XML payload to extract email details
    try:
        root = ET.fromstring(xml_payload)
        subject = root.find(".//t:Subject", namespaces={"t": "http://schemas.microsoft.com/exchange/services/2006/types"}).text
        body = root.find(".//t:Body", namespaces={"t": "http://schemas.microsoft.com/exchange/services/2006/types"}).text
        to_email = root.find(".//t:EmailAddress", namespaces={"t": "http://schemas.microsoft.com/exchange/services/2006/types"}).text
    except Exception as e:
        print(f"Failed to parse XML: {e}")
        return jsonify({"error": "Failed to parse XML payload"}), 400

    # Get OAuth token
    access_token = get_oauth_token(username, password, client_id, client_secret, tenant_id)
    if not access_token:
        return jsonify({"error": "Failed to retrieve token"}), 500

    # Send email via Microsoft Graph API
    email_sent = send_email_via_graph_api(access_token, username, to_email, subject, body)
    if email_sent:
        return jsonify({"message": "Email sent successfully via Microsoft Graph API!"}), 200
    else:
        return jsonify({"error": "Failed to send email via Microsoft Graph API"}), 500

def get_oauth_token(username, password, client_id, client_secret, tenant_id):
    """Retrieve OAuth token using username, password, and Azure AD credentials."""
    payload = {
        'client_id': client_id,
        'client_secret': client_secret,
        'scope': 'https://graph.microsoft.com/.default',
        'grant_type': 'password',
        'username': username,
        'password': password
    }

    token_url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
    try:
        response = requests.post(token_url, data=payload)
        response.raise_for_status()  # Raise an exception for HTTP errors
        return response.json().get("access_token")
    except requests.exceptions.RequestException as e:
        print(f"Failed to retrieve token: {e}")
        return None

def send_email_via_graph_api(access_token, from_email, to_email, subject, body):
    """Send email using Microsoft Graph API."""
    email_data = {
        "message": {
            "subject": subject,
            "body": {
                "contentType": "Text",
                "content": body
            },
            "toRecipients": [
                {
                    "emailAddress": {
                        "address": to_email
                    }
                }
            ]
        },
        "saveToSentItems": "true"
    }

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }

    try:
        response = requests.post(GRAPH_API_SEND_MAIL_URL, json=email_data, headers=headers)
        return response.status_code == 202
    except requests.exceptions.RequestException as e:
        print(f"Failed to send email: {e}")
        return False

@app.route('/read_emails', methods=['POST'])
def read_emails():
    # Extract Azure AD credentials from JSON body
    data = request.get_json()
    if not data:
        return jsonify({"error": "Invalid JSON payload"}), 400

    client_id = data.get("client_id")
    client_secret = data.get("client_secret")
    tenant_id = data.get("tenant_id")

    # Validate Azure AD credentials
    if not client_id or not client_secret or not tenant_id:
        return jsonify({"error": "Missing Azure AD credentials in JSON payload"}), 400

    # Extract Basic Auth credentials from request header
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Basic "):
        return jsonify({"error": "Invalid Authorization header"}), 400

    encoded_creds = auth_header.split(" ")[1]
    decoded_creds = base64.b64decode(encoded_creds).decode("utf-8")
    username, password = decoded_creds.split(":")

    # Get OAuth token
    access_token = get_oauth_token(username, password, client_id, client_secret, tenant_id)
    if not access_token:
        return jsonify({"error": "Failed to retrieve token"}), 500

    # Retrieve emails via Microsoft Graph API
    emails = get_emails_via_graph_api(access_token)
    if emails:
        return jsonify({"emails": emails}), 200
    else:
        return jsonify({"error": "Failed to retrieve emails"}), 500

def get_emails_via_graph_api(access_token):
    """Retrieve recent emails from Microsoft Graph API."""
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }

    try:
        response = requests.get(GRAPH_API_READ_MAIL_URL, headers=headers, params={"$top": 5})
        response.raise_for_status()  # Raise an exception for HTTP errors
        messages = response.json().get("value", [])
        emails = [
            {
                "subject": message.get("subject"),
                "sender": message.get("from", {}).get("emailAddress", {}).get("address"),
                "received_date": message.get("receivedDateTime"),
                "body_preview": message.get("bodyPreview")
            }
            for message in messages
        ]
        return emails
    except requests.exceptions.RequestException as e:
        print(f"Failed to retrieve emails: {e}")
        return None


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
