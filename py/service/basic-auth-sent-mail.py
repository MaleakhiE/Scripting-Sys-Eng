import requests
from requests.auth import HTTPBasicAuth

# Email credentials and settings
email_address = "maleakhi@dikstrasolusi.com"  # Basic Auth uses email format
password = "YourPasswordHere"  # Replace with actual password
ews_url = "http://192.168.10.50:5000/send_email"  # Proxy server URL

# Create the XML payload for sending an email
email_subject = "Test Email"
email_body = "This is a test email sent via EWS using Basic Auth."
email_to = input("Set Your Recipient here: ")

xml_payload = f"""<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
               xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"
               xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages">
    <soap:Header>
        <t:RequestServerVersion Version="Exchange2010" />
    </soap:Header>
    <soap:Body>
        <m:CreateItem MessageDisposition="SendAndSaveCopy">
            <m:Items>
                <t:Message>
                    <t:ItemClass>IPM.Note</t:ItemClass>
                    <t:Subject>{email_subject}</t:Subject>
                    <t:Body BodyType="Text">{email_body}</t:Body>
                    <t:ToRecipients>
                        <t:Mailbox>
                            <t:EmailAddress>{email_to}</t:EmailAddress>
                        </t:Mailbox>
                    </t:ToRecipients>
                    <t:SavedItemFolderId>
                        <t:DistinguishedFolderId Id="sentitems" />
                    </t:SavedItemFolderId>
                </t:Message>
            </m:Items>
        </m:CreateItem>
    </soap:Body>
</soap:Envelope>"""

# Send the request using Basic Authentication
response = requests.post(
    ews_url,
    data=xml_payload,
    headers={
        "Content-Type": "text/xml; charset=utf-8",
        "SOAPAction": "http://schemas.microsoft.com/exchange/services/2006/messages/CreateItem"
    },
    auth=HTTPBasicAuth(email_address, password),  # Switch to Basic Auth
    verify=False  # Disable SSL certificate verification if necessary
)

# Check the response
if response.status_code == 200:
    print("Email sent successfully!")
else:
    print(f"Failed to send email. Status Code: {response.status_code}")
    print(f"Response Content: {response.content.decode()}")
