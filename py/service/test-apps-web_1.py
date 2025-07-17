import streamlit as st
import requests
from requests.auth import HTTPBasicAuth
import base64
from datetime import datetime, timedelta

# Set up the Streamlit page configuration
st.set_page_config(page_title="OAuth Email Proxy App", page_icon="📧")

# Set up the Streamlit page content
st.title("OAuth Email Proxy - Send & Read Email with Basic to OAuth Transformation")
st.write("Send an email or read recent emails using Basic Auth through a proxy server that converts it to OAuth.")

# Azure AD configuration inputs
st.markdown("### Azure AD Configuration")
client_id = st.text_input("Azure Client ID", value="14dfa8f3-e0e9-420c-889a-f7c3d369f604")
client_secret = st.text_input("Azure Client Secret", value="KtX8Q~tIi8NEGujS2sUBi3jgt~nGgZ8mEpSwMbJk", type="password")
tenant_id = st.text_input("Azure Tenant ID", value="39c345ae-bf0d-40bf-aba9-081979356879")
st.markdown("---")

# User inputs for email and password
ews_url_send = st.text_input("EWS URL for Sending Email (**192.168.10.50/send_email** - Proxy Server)", value="http://192.168.10.50:5000/send_email")
ews_url_read = st.text_input("EWS URL for Reading Emails (**192.168.10.50/read_emails** - Proxy Server)", value="http://192.168.10.50:5000/read_emails")
st.markdown("---")
email_address = st.text_input("Your Email Address (Basic Auth format)")
password = st.text_input("Your Password", type="password")
st.markdown("---")

# Send Email Section
st.subheader("Send Email")
recipient_email = st.text_input("Recipient Email Address")
subject = st.text_input("Email Subject", value="Test Email")
body = st.text_area("Email Body", value="This is a test email sent via EWS using Basic Auth.")

# Send email when the button is clicked
if st.button("Send Email"):
    if client_id and client_secret and tenant_id and email_address and password and recipient_email:
        with st.spinner("Sending email..."):
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

            # Display the result
            if response.status_code == 200:
                st.success("Email sent successfully!")
            else:
                st.error("Failed to send email. Please check the details or try again.")
                st.text(f"Status Code: {response.status_code}")
                st.text(f"Response Text: {response.text}")

# Divider
st.markdown("---")

# Read Email Section
st.subheader("Read Recent Emails")

# Read email when the button is clicked
if st.button("Read Emails"):
    if client_id and client_secret and tenant_id and email_address and password:
        with st.spinner("Reading emails..."):
            # Make the request to read emails
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

            # Display the result
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
                                <h4 style="color: #333;">📧 {email['subject']}</h4>
                                <p><strong>Sender:</strong> <a href="mailto:{email['sender']}" target="_blank" style="color: #1a73e8;">{email['sender']}</a></p>
                                <p><strong>Received Date:</strong> {formatted_date}</p>
                                <p><strong>Preview:</strong> {email['body_preview']}</p>
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
