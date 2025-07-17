import requests
from requests.auth import HTTPBasicAuth
import xml.etree.ElementTree as ET

# Email credentials and settings
email_address = "eki@protelindo.loc"  # Basic Auth uses email format
password = "password.1"
ews_url = "http://192.168.124.11/EWS/Exchange.asmx"  # Correct EWS URL

# Create the XML payload for reading emails
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
                <t:BaseShape>Default</t:BaseShape>
            </m:ItemShape>
            <m:ParentFolderIds>
                <t:DistinguishedFolderId Id="inbox" />
            </m:ParentFolderIds>
        </m:FindItem>
    </soap:Body>
</soap:Envelope>"""

# Send the request to read emails using Basic Authentication
response = requests.post(
    ews_url,
    data=xml_payload,
    headers={
        "Content-Type": "text/xml; charset=utf-8",
        "SOAPAction": "http://schemas.microsoft.com/exchange/services/2006/messages/FindItem"
    },
    auth=HTTPBasicAuth(email_address, password),  # Switch to Basic Auth
    verify=False  # Disable SSL certificate verification if necessary
)

# Check the response and parse the email data
if response.status_code == 200:
    print("Emails retrieved successfully!")

    # Parse the XML response
    root = ET.fromstring(response.content)

    # Namespaces
    namespaces = {
        's': "http://schemas.xmlsoap.org/soap/envelope/",
        'm': "http://schemas.microsoft.com/exchange/services/2006/messages",
        't': "http://schemas.microsoft.com/exchange/services/2006/types"
    }

    # Find all message elements
    messages = root.findall(".//t:Message", namespaces)

    # Extract and print details for each message
    for message in messages:
        subject = message.find("t:Subject", namespaces).text
        datetime_sent = message.find("t:DateTimeSent", namespaces).text
        from_name = message.find("t:From/t:Mailbox/t:Name", namespaces).text
        from_email = message.find("t:From/t:Mailbox/t:EmailAddress", namespaces).text
        is_read = message.find("t:IsRead", namespaces).text

        # Display each email's details
        print("Subject:", subject)
        print("Sent On:", datetime_sent)
        print("From:", f"{from_name} <{from_email}>")
        print("Is Read:", is_read)
        print("-" * 40)
else:
    print(f"Failed to retrieve emails. Status Code: {response.status_code}")
    print(f"Response Content: {response.content.decode()}")
