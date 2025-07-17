import requests

# Email credentials and settings (replace with actual values)
client_id = '14dfa8f3-e0e9-420c-889a-f7c3d369f604'
client_secret = 'KtX8Q~tIi8NEGujS2sUBi3jgt~nGgZ8mEpSwMbJk'
tenant_id = '39c345ae-bf0d-40bf-aba9-081979356879'
ews_url = "https://outlook.office365.com/EWS/Exchange.asmx"
email_address = "maleakhi@dikstrasolusi.com"
email_to = str(input("Enter receiver email address: "))

# OAuth 2.0 token endpoint
token_url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"

# Get an OAuth token
token_data = {
    'grant_type': 'client_credentials',
    'client_id': client_id,
    'client_secret': client_secret,
    'scope': 'https://outlook.office365.com/.default'
}

# Request the token
token_response = requests.post(token_url, data=token_data)
token = token_response.json().get('access_token')

if not token:
    print(f"Failed to obtain access token: {token_response.content.decode()}")
    exit()

# Create the XML payload for sending an email with ExchangeImpersonation
email_subject = "Test Email - Using EWS and OAuth 2.0 (Exchange Online Dikstra)"
email_body = str(input("Enter email content: "))
xml_payload = f"""<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
               xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"
               xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages">
    <soap:Header>
        <t:RequestServerVersion Version="Exchange2010" />
        <t:ExchangeImpersonation>
            <t:ConnectingSID>
                <t:PrimarySmtpAddress>{email_address}</t:PrimarySmtpAddress>
            </t:ConnectingSID>
        </t:ExchangeImpersonation>
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

# Send the request using OAuth token for authentication
response = requests.post(
    ews_url,
    data=xml_payload,
    headers={
        "Content-Type": "text/xml; charset=utf-8",
        "Authorization": f"Bearer {token}",
        "SOAPAction": "http://schemas.microsoft.com/exchange/services/2006/messages/CreateItem"
    }
)

# Check the response
if response.status_code == 200:
    print("Email sent successfully!")
else:
    print(f"Failed to send email. Status Code: {response.status_code}")
    print(f"Response Content: {response.content.decode()}")