from flask import Flask, request, jsonify, abort
import requests
import base64
import xml.etree.ElementTree as ET
import logging
from werkzeug.middleware.proxy_fix import ProxyFix
from werkzeug.exceptions import HTTPException
from requests.auth import HTTPBasicAuth
from os import getenv

# Configure the environment
ENV = getenv("FLASK_ENV", "production")

app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app)

# Security settings
app.config.update({
    'SESSION_COOKIE_SECURE': ENV == "production",
    'SESSION_COOKIE_HTTPONLY': True,
    'SESSION_COOKIE_SAMESITE': 'Strict',
})

# Set up logging for production
if ENV == "production":
    logging.basicConfig(level=logging.WARNING)
else:
    logging.basicConfig(level=logging.DEBUG)

# Default Azure AD credentials for fallback
DEFAULT_CLIENT_ID = "14dfa8f3-e0e9-420c-889a-f7c3d369f604"
DEFAULT_CLIENT_SECRET = "KtX8Q~tIi8NEGujS2sUBi3jgt~nGgZ8mEpSwMbJk"
DEFAULT_TENANT_ID = "39c345ae-bf0d-40bf-aba9-081979356879"

# Microsoft Graph API endpoints
GRAPH_API_SEND_MAIL_URL = "https://graph.microsoft.com/v1.0/me/sendMail"
GRAPH_API_READ_MAIL_URL = "https://graph.microsoft.com/v1.0/me/messages"
EWS_URL = "https://outlook.office365.com/EWS/Exchange.asmx"  # Update this endpoint for EWS

@app.errorhandler(HTTPException)
def handle_exception(e):
    response = e.get_response()
    response.data = jsonify({"error": "An error occurred. Please try again later."}).get_data()
    response.content_type = "application/json"
    logging.error(f"HTTP error: {e.description}")
    return response

def validate_input(data, required_fields):
    missing_fields = [field for field in required_fields if field not in data]
    if missing_fields:
        logging.warning(f"Missing fields in payload: {missing_fields}")
        abort(400, description="Invalid input data")

def get_credentials(data):
    """Check if credentials are provided; otherwise, use defaults."""
    client_id = data.get("client_id", DEFAULT_CLIENT_ID)
    client_secret = data.get("client_secret", DEFAULT_CLIENT_SECRET)
    tenant_id = data.get("tenant_id", DEFAULT_TENANT_ID)
    return client_id, client_secret, tenant_id

def get_oauth_token(username, password, client_id, client_secret, tenant_id):
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
        response = requests.post(token_url, data=payload, timeout=5)
        response.raise_for_status()
        return response.json().get("access_token")
    except requests.exceptions.RequestException as e:
        logging.error(f"Failed to retrieve token: {e}")
        return None

def send_email_via_graph_api(access_token, from_email, to_email, subject, body):
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
        response = requests.post(GRAPH_API_SEND_MAIL_URL, json=email_data, headers=headers, timeout=5)
        return response.status_code == 202
    except requests.exceptions.RequestException as e:
        logging.error(f"Failed to send email: {e}")
        return False

@app.route('/send_email', methods=['POST'])
def send_email():
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Basic "):
        logging.warning("Invalid or missing Authorization header")
        return jsonify({"error": "Invalid Authorization header"}), 400

    # Decode Basic Auth credentials
    try:
        encoded_creds = auth_header.split(" ")[1]
        decoded_creds = base64.b64decode(encoded_creds).decode("utf-8")
        username, password = decoded_creds.split(":")
    except Exception as e:
        logging.error(f"Error decoding credentials: {e}")
        return jsonify({"error": "Invalid Authorization credentials"}), 400

    # Check if JSON payload is sent or XML directly
    if request.is_json:
        data = request.get_json()
        if not data:
            logging.warning("Invalid JSON payload")
            return jsonify({"error": "Invalid JSON payload"}), 400
        
        client_id, client_secret, tenant_id = get_credentials(data)
        required_fields = ["xml_payload"]
        validate_input(data, required_fields)
        xml_payload = data["xml_payload"]
    else:
        xml_payload = request.data.decode("utf-8")
        client_id, client_secret, tenant_id = DEFAULT_CLIENT_ID, DEFAULT_CLIENT_SECRET, DEFAULT_TENANT_ID

    try:
        root = ET.fromstring(xml_payload)
        subject = root.find(".//t:Subject", namespaces={"t": "http://schemas.microsoft.com/exchange/services/2006/types"}).text
        body = root.find(".//t:Body", namespaces={"t": "http://schemas.microsoft.com/exchange/services/2006/types"}).text
        to_email = root.find(".//t:EmailAddress", namespaces={"t": "http://schemas.microsoft.com/exchange/services/2006/types"}).text
    except Exception as e:
        logging.error(f"Failed to parse XML: {e}")
        return jsonify({"error": "Failed to parse XML payload"}), 400

    access_token = get_oauth_token(username, password, client_id, client_secret, tenant_id)
    if not access_token:
        logging.error("Failed to retrieve token")
        return jsonify({"error": "Failed to retrieve token"}), 500

    email_sent = send_email_via_graph_api(access_token, username, to_email, subject, body)
    if email_sent:
        return jsonify({"message": "Email sent successfully via Microsoft Graph API!"}), 200
    else:
        logging.error("Failed to send email")
        return jsonify({"error": "Failed to send email via Microsoft Graph API"}), 500

def get_emails_via_graph_api(access_token):
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }

    try:
        response = requests.get(GRAPH_API_READ_MAIL_URL, headers=headers, params={"$top": 5}, timeout=5)
        response.raise_for_status()
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
        logging.error(f"Failed to retrieve emails: {e}")
        return None

def read_emails_via_ews(username, password):
    xml_payload = """<?xml version="1.0" encoding="utf-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                   xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"
                   xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages">
        <soap:Header>
            <t:RequestServerVersion Version="Exchange2010" />
        </soap:Header>
        <soap:Body>
            <m:FindItem Traversal="Shallow">
                <m:ItemShape>
                    <t:BaseShape>IdOnly</t:BaseShape>
                    <t:AdditionalProperties>
                        <t:FieldURI FieldURI="item:Subject"/>
                        <t:FieldURI FieldURI="item:DateTimeReceived"/>
                        <t:FieldURI FieldURI="message:Sender"/>
                    </t:AdditionalProperties>
                </m:ItemShape>
                <m:ParentFolderIds>
                    <t:DistinguishedFolderId Id="inbox" />
                </m:ParentFolderIds>
            </m:FindItem>
        </soap:Body>
    </soap:Envelope>"""

    try:
        response = requests.post(
            EWS_URL,
            data=xml_payload,
            headers={
                "Content-Type": "text/xml; charset=utf-8",
                "SOAPAction": "http://schemas.microsoft.com/exchange/services/2006/messages/FindItem"
            },
            auth=HTTPBasicAuth(username, password),
            verify=False
        )

        if response.status_code == 200:
            emails = []
            root = ET.fromstring(response.content)
            namespace = {"t": "http://schemas.microsoft.com/exchange/services/2006/types"}
            for item in root.findall(".//t:Message", namespace):
                subject = item.find("t:Subject", namespace).text or "No Subject"
                sender = item.find("t:Sender/t:Mailbox/t:EmailAddress", namespace).text or "Unknown Sender"
                received_date = item.find("t:DateTimeReceived", namespace).text or "Unknown Date"
                emails.append({"subject": subject, "sender": sender, "received_date": received_date})
            return emails
        else:
            logging.error(f"EWS email read failed. Status Code: {response.status_code}, Response: {response.content.decode()}")
            return None
    except Exception as e:
        logging.error(f"Exception while reading emails via EWS: {e}")
        return None

@app.route('/read_emails', methods=['POST'])
def read_emails():
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Basic "):
        logging.warning("Invalid Authorization header")
        return jsonify({"error": "Invalid Authorization header"}), 400

    # Decode Basic Auth credentials
    try:
        encoded_creds = auth_header.split(" ")[1]
        decoded_creds = base64.b64decode(encoded_creds).decode("utf-8")
        username, password = decoded_creds.split(":")
    except Exception as e:
        logging.error(f"Error decoding credentials: {e}")
        return jsonify({"error": "Invalid Authorization credentials"}), 400

    # Attempt to read emails via EWS (Basic Authentication)
    ews_emails = read_emails_via_ews(username, password)
    if ews_emails:
        return jsonify({"emails": ews_emails}), 200

    # If EWS fails, switch to OAuth for Microsoft Graph API
    client_id, client_secret, tenant_id = DEFAULT_CLIENT_ID, DEFAULT_CLIENT_SECRET, DEFAULT_TENANT_ID
    access_token = get_oauth_token(username, password, client_id, client_secret, tenant_id)
    if not access_token:
        logging.error("Failed to retrieve OAuth token")
        return jsonify({"error": "Failed to retrieve token"}), 500

    # Get emails via Microsoft Graph API
    graph_emails = get_emails_via_graph_api(access_token)
    if graph_emails:
        return jsonify({"emails": graph_emails}), 200
    else:
        logging.error("Failed to retrieve emails via Microsoft Graph API")
        return jsonify({"error": "Failed to retrieve emails via Microsoft Graph API"}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
    
