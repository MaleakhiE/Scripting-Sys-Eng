from flask import Flask, request, jsonify, abort
import requests
import base64
import xml.etree.ElementTree as ET
import logging
from werkzeug.middleware.proxy_fix import ProxyFix
from werkzeug.exceptions import HTTPException
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

# Microsoft Graph API endpoints
GRAPH_API_SEND_MAIL_URL = "https://graph.microsoft.com/v1.0/me/sendMail"
GRAPH_API_READ_MAIL_URL = "https://graph.microsoft.com/v1.0/me/messages"

@app.errorhandler(HTTPException)
def handle_exception(e):
    """Handle HTTP errors securely"""
    response = e.get_response()
    response.data = jsonify({"error": "An error occurred. Please try again later."}).get_data()
    response.content_type = "application/json"
    logging.error(f"HTTP error: {e.description}")
    return response

def validate_input(data, required_fields):
    """Helper function to validate input data for required fields"""
    missing_fields = [field for field in required_fields if field not in data]
    if missing_fields:
        logging.warning(f"Missing fields in payload: {missing_fields}")
        abort(400, description="Invalid input data")

@app.route('/send_email', methods=['POST'])
def send_email():
    data = request.get_json()
    if not data:
        logging.warning("Invalid JSON payload")
        return jsonify({"error": "Invalid JSON payload"}), 400

    required_fields = ["client_id", "client_secret", "tenant_id", "xml_payload"]
    validate_input(data, required_fields)

    client_id = data["client_id"]
    client_secret = data["client_secret"]
    tenant_id = data["tenant_id"]
    xml_payload = data["xml_payload"]

    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Basic "):
        logging.warning("Invalid or missing Authorization header")
        return jsonify({"error": "Invalid Authorization header"}), 400

    try:
        encoded_creds = auth_header.split(" ")[1]
        decoded_creds = base64.b64decode(encoded_creds).decode("utf-8")
        username, password = decoded_creds.split(":")
    except Exception as e:
        logging.error(f"Error decoding credentials: {e}")
        return jsonify({"error": "Invalid Authorization credentials"}), 400

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

@app.route('/read_emails', methods=['POST'])
def read_emails():
    data = request.get_json()
    if not data:
        logging.warning("Invalid JSON payload")
        return jsonify({"error": "Invalid JSON payload"}), 400

    required_fields = ["client_id", "client_secret", "tenant_id"]
    validate_input(data, required_fields)

    client_id = data["client_id"]
    client_secret = data["client_secret"]
    tenant_id = data["tenant_id"]

    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Basic "):
        logging.warning("Invalid Authorization header")
        return jsonify({"error": "Invalid Authorization header"}), 400

    try:
        encoded_creds = auth_header.split(" ")[1]
        decoded_creds = base64.b64decode(encoded_creds).decode("utf-8")
        username, password = decoded_creds.split(":")
    except Exception as e:
        logging.error(f"Error decoding credentials: {e}")
        return jsonify({"error": "Invalid Authorization credentials"}), 400

    access_token = get_oauth_token(username, password, client_id, client_secret, tenant_id)
    if not access_token:
        logging.error("Failed to retrieve token")
        return jsonify({"error": "Failed to retrieve token"}), 500

    emails = get_emails_via_graph_api(access_token)
    if emails:
        return jsonify({"emails": emails}), 200
    else:
        logging.error("Failed to retrieve emails")
        return jsonify({"error": "Failed to retrieve emails"}), 500

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

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
