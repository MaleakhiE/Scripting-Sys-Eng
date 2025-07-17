import streamlit as st
import requests
import base64
from requests.auth import HTTPBasicAuth  # Importing HTTPBasicAuth
from datetime import datetime, timedelta
import xml.etree.ElementTree as ET
import json

# Set up the Streamlit page configuration
st.set_page_config(page_title="OAuth Email Proxy App", page_icon="📧", layout="wide")

# Set up the Streamlit page content
st.title("OAuth Email Proxy - Send & Read Email with Basic to OAuth Transformation")
st.write("This application allows you to send and read emails using Basic Authentication, through a proxy server that converts the requests to OAuth.")

# Azure AD configuration inputs
st.markdown("### Azure AD Configuration")
client_id = st.text_input("Azure Client ID", value="14dfa8f3-e0e9-420c-889a-f7c3d369f604")
client_secret = st.text_input("Azure Client Secret", value="KtX8Q~tIi8NEGujS2sUBi3jgt~nGgZ8mEpSwMbJk", type="password")
tenant_id = st.text_input("Azure Tenant ID", value="39c345ae-bf0d-40bf-aba9-081979356879")
st.markdown("---")

# User inputs for email and password
ews_url_send = st.text_input("EWS URL for Sending Email", value="http://192.168.10.155:5000/send_email")
ews_url_read = st.text_input("EWS URL for Reading Emails", value="http://192.168.10.155:5000/read_emails")
st.markdown("---")
email_address = st.text_input("Your Email Address (Basic Auth format)")
password = st.text_input("Your Password", type="password")
st.markdown("---")

# Send Email Section
st.subheader("Send Email")
st.write("Use the options below to send emails using different authentication methods.")

# Create two columns for sending email
col1, col2 = st.columns(2)

# Column for sending email with OAuth
with col1:
    st.write("### Send Email via OAuth")
    st.write("Fill in the recipient's address, subject, and body to send an email securely using OAuth.")
    st.write("""
    In this method, the application constructs a secure XML payload for Microsoft Exchange and sends it using OAuth credentials (Client ID, Client Secret, Tenant ID).
    - **Functionality**: This method ensures that sensitive data is transmitted securely.
    - **Use Case**: Ideal for secure environments where OAuth is required.
    """)
    
    recipient_email = st.text_input("Recipient Email Address (OAuth)")
    subject = st.text_input("Email Subject (OAuth)", value="Test Email")
    body = st.text_area("Email Body (OAuth)", value="This is a test email sent via EWS using Basic Auth.")

    if st.button("Send Email via OAuth"):
        # Validate that all necessary inputs are provided
        if client_id and client_secret and tenant_id and email_address and password and recipient_email:
            with st.spinner("Sending email..."):
                # Create XML payload for the email using SOAP format
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
                                    <t:Subject>{subject}</t:Subject>
                                    <t:Body BodyType="Text">{body}</t:Body>
                                    <t:ToRecipients>
                                        <t:Mailbox>
                                            <t:EmailAddress>{recipient_email}</t:EmailAddress>
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

                # Combine XML payload and Azure credentials into a JSON payload
                payload = {
                    "client_id": client_id,
                    "client_secret": client_secret,
                    "tenant_id": tenant_id,
                    "xml_payload": xml_payload  # Adding XML as part of JSON payload
                }

                # Send the request using Basic Authentication and JSON payload
                response = requests.post(
                    ews_url_send,
                    json=payload,
                    headers={
                        "Authorization": f"Basic {base64.b64encode(f'{email_address}:{password}'.encode()).decode()}",
                        "Content-Type": "application/json",  # Use application/json for JSON payload
                    },
                    verify=False  # Disable SSL certificate verification if necessary
                )

                # Display the result of the email sending action
                if response.status_code == 200:
                    st.success("Email sent successfully!")
                else:
                    st.error("Failed to send email. Please check the details or try again.")
                    st.text(f"Status Code: {response.status_code}")
                    st.text(f"Response Text: {response.text}")

# Column for sending email directly via Basic Auth
with col2:
    st.write("### Send Email via Basic Auth")
    st.write("Use this method to send an email directly by entering the recipient's address, subject, and body.")
    st.write("""
    In this method, you can send an email immediately by providing the recipient's details, without the overhead of OAuth.
    - **Functionality**: This method sends your credentials directly for immediate action.
    - **Use Case**: Ideal for quick email sending when you are familiar with Basic Authentication.
    """)
    
    basic_auth_recipient = st.text_input("Recipient Email Address (Basic Auth)")
    basic_auth_subject = st.text_input("Email Subject (Basic Auth)", value="Test Email - SOAP")
    basic_auth_body = st.text_area("Email Body (Basic Auth)", value="This is a test email sent via EWS using Basic Auth.")

    if st.button("Send Email via Basic Auth"):
        if basic_auth_recipient and email_address and password:
            with st.spinner("Sending email via Basic Auth..."):
                # Create XML payload for the email
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
                                    <t:Subject>{basic_auth_subject}</t:Subject>
                                    <t:Body BodyType="Text">{basic_auth_body}</t:Body>
                                    <t:ToRecipients>
                                        <t:Mailbox>
                                            <t:EmailAddress>{basic_auth_recipient}</t:EmailAddress>
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

                # Send the request using Basic Authentication directly to the proxy
                response = requests.post(
                    ews_url_send,
                    data=xml_payload,
                    headers={
                        "Content-Type": "text/xml; charset=utf-8",
                        "SOAPAction": "http://schemas.microsoft.com/exchange/services/2006/messages/CreateItem"
                    },
                    auth=HTTPBasicAuth(email_address, password),  # Basic Auth
                    verify=False  # Disable SSL certificate verification if necessary
                )

                # Check the response
                if response.status_code == 200:
                    st.success("Email sent successfully via Basic Auth!")
                else:
                    st.error("Failed to send email via Basic Auth. Please check the details or try again.")
                    st.text(f"Status Code: {response.status_code}")
                    st.text(f"Response Content: {response.content.decode()}")

# Divider
st.markdown("---")

# Read Email Section
st.subheader("Read Recent Emails")
st.write("Use this section to read your recent emails using two different methods.")

# Create two columns for reading emails
col3, col4 = st.columns(2)

# Column for reading emails via OAuth
with col3:
    st.write("### Read Emails via OAuth")
    st.write("Use this method to read emails securely using OAuth.")
    st.write("""
    In this method, you will retrieve emails using OAuth credentials (Client ID, Client Secret, Tenant ID).
    - **Functionality**: This method ensures secure retrieval of email data.
    - **Use Case**: Ideal for applications that require secure authentication.
    """)
    
    if st.button("Read Emails via OAuth"):
        if client_id and client_secret and tenant_id and email_address and password:
            with st.spinner("Reading emails via OAuth..."):
                payload = {
                    "client_id": client_id,
                    "client_secret": client_secret,
                    "tenant_id": tenant_id
                }

                response = requests.post(
                    ews_url_read,
                    json=payload,  # Pass Azure AD credentials in JSON payload
                    headers={
                        "Authorization": f"Basic {base64.b64encode(f'{email_address}:{password}'.encode()).decode()}",
                        "Content-Type": "application/json"
                    },
                    verify=False  # Disable SSL certificate verification if necessary
                )

                # Display the result of the email reading action
                if response.status_code == 200:
                    emails = response.json().get("emails", [])
                    if emails:
                        for email in emails:
                            # Convert received date to GMT+7
                            received_date = datetime.fromisoformat(email['received_date'].replace("Z", "+00:00"))
                            gmt_plus_7 = received_date + timedelta(hours=7)
                            formatted_date = gmt_plus_7.strftime("%d %B %Y, %I:%M %p")

                            # Use Streamlit Markdown with HTML for a better layout
                            st.markdown(f"""
                                <div style="border: 1px solid #ddd; padding: 15px; border-radius: 8px; margin-bottom: 15px; box-shadow: 1px 1px 5px rgba(0,0,0,0.1); background-color: #f9f9f9;">
                                    <h4 style="text-align: center; color: #333;">📧 {email['subject']}</h4>
                                    <p style="text-align: center;"><strong>Sender:</strong> <a href="mailto:{email['sender']}" target="_blank" style="color: #1a73e8;">{email['sender']}</a></p>
                                    <p style="text-align: center;"><strong>Received Date:</strong> {formatted_date}</p>
                                    <p style="text-align: center;"><strong>Preview:</strong> {email['body_preview']}</p>
                                </div>
                            """, unsafe_allow_html=True)
                    else:
                        st.info("No recent emails found.")
                else:
                    st.error("Failed to read emails. Please check the details or try again.")
                    st.text(f"Status Code: {response.status_code}")
                    st.text(f"Response Text: {response.text}")
        else:
            st.warning("Please enter your email address and password to read emails.")


# Column for reading emails directly via SOAP
with col4:
    st.write("### Read Emails via SOAP")
    st.write("Use this method to read emails directly using a SOAP request.")
    st.write("""
    In this method, you will retrieve emails immediately using a direct XML SOAP request.
    - **Functionality**: This method sends the credentials directly for immediate email retrieval without additional OAuth transformation.
    - **Use Case**: Ideal for direct access to email data when using EWS and Basic Authentication is acceptable.
    """)
    
    if st.button("Read Emails via SOAP"):
        if email_address and password:
            with st.spinner("Reading emails via SOAP..."):
                # Create XML payload for reading emails
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
                                <t:BaseShape>AllProperties</t:BaseShape>
                            </m:ItemShape>
                            <m:ParentFolderIds>
                                <t:DistinguishedFolderId Id="inbox" />
                            </m:ParentFolderIds>
                        </m:FindItem>
                    </soap:Body>
                </soap:Envelope>"""

                # Send the request using Basic Authentication directly to the proxy
                response = requests.post(
                    ews_url_read,
                    data=xml_payload,
                    headers={
                        "Content-Type": "text/xml; charset=utf-8",
                        "SOAPAction": "http://schemas.microsoft.com/exchange/services/2006/messages/FindItem"
                    },
                    auth=HTTPBasicAuth(email_address, password),  # Basic Auth
                    verify=False  # Disable SSL certificate verification if necessary
                )

                # Check if the response is JSON or XML
                if response.status_code == 200:
                    content_type = response.headers.get("Content-Type", "")
                    emails = []
                    
                    # If response is JSON, handle it as JSON
                    if "application/json" in content_type:
                        try:
                            json_data = response.json()
                            emails = json_data.get("emails", [])
                            if not emails:
                                st.info("No recent emails found.")
                        except ValueError:
                            st.error("Failed to parse JSON response.")
                            st.text(response.text)

                    # Otherwise, assume the response is XML and parse accordingly
                    elif "text/xml" in content_type or "application/xml" in content_type:
                        try:
                            # Parse the XML response
                            root = ET.fromstring(response.content)
                            namespace = {"t": "http://schemas.microsoft.com/exchange/services/2006/types"}
                            for item in root.findall(".//t:Message", namespace):
                                subject = item.find("t:Subject", namespace).text or "No Subject"
                                sender = item.find("t:Sender/t:Mailbox/t:EmailAddress", namespace).text or "Unknown Sender"
                                received_date = item.find("t:DateTimeReceived", namespace).text or "Unknown Date"
                                body_preview = item.find("t:BodyPreview", namespace).text or "No preview available"

                                emails.append({
                                    "subject": subject,
                                    "sender": sender,
                                    "received_date": received_date,
                                    "body_preview": body_preview
                                })
                            if not emails:
                                st.info("No recent emails found.")
                        except ET.ParseError:
                            st.error("Failed to parse the XML response. Please check the server response.")

                    # Display parsed emails in a consistent format
                    if emails:
                        for email in emails:
                            # Convert received date to GMT+7 if available
                            try:
                                received_date = datetime.fromisoformat(email['received_date'].replace("Z", "+00:00"))
                                gmt_plus_7 = received_date + timedelta(hours=7)
                                formatted_date = gmt_plus_7.strftime("%d %B %Y, %I:%M %p")
                            except (ValueError, TypeError):
                                formatted_date = email['received_date']

                            # Display using Streamlit Markdown with HTML for consistent layout
                            st.markdown(f"""
                                <div style="border: 1px solid #ddd; padding: 15px; border-radius: 8px; margin-bottom: 15px; box-shadow: 1px 1px 5px rgba(0,0,0,0.1); background-color: #f9f9f9;">
                                    <h4 style="text-align: center; color: #333;">📧 {email['subject']}</h4>
                                    <p style="text-align: center;"><strong>Sender:</strong> <a href="mailto:{email['sender']}" target="_blank" style="color: #1a73e8;">{email['sender']}</a></p>
                                    <p style="text-align: center;"><strong>Received Date:</strong> {formatted_date}</p>
                                    <p style="text-align: center;"><strong>Preview:</strong> {email['body_preview']}</p>
                                </div>
                            """, unsafe_allow_html=True)
                    else:
                        st.info("No recent emails found.")
                else:
                    # Display error details if response is not as expected
                    st.error("Failed to read emails via SOAP. Please check the details or try again.")
                    st.text(f"Status Code: {response.status_code}")
                    st.text(f"Response Content: {response.content.decode('utf-8', errors='replace')}")

# End of the app