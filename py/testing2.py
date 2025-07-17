import smtplib
from email.mime.text import MIMEText
from getpass import getpass
import base64

# Office 365 SMTP server details
smtp_server = 'outlook.office.com'
smtp_port = 443

# Sender and recipient email addresses
sender_email = 'maleakhi@dikstrasolusi.com'
recipient_email = 'ekiputra234@gmail.com'

# OAuth 2.0 access token
access_token = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6IlhSdmtvOFA3QTNVYVdTblU3Yk05blQwTWpoQSIsImtpZCI6IlhSdmtvOFA3QTNVYVdTblU3Yk05blQwTWpoQSJ9.eyJhdWQiOiIwMDAwMDAwMi0wMDAwLTAwMDAtYzAwMC0wMDAwMDAwMDAwMDAiLCJpc3MiOiJodHRwczovL3N0cy53aW5kb3dzLm5ldC8zOWMzNDVhZS1iZjBkLTQwYmYtYWJhOS0wODE5NzkzNTY4NzkvIiwiaWF0IjoxNzEwNzM5MjY0LCJuYmYiOjE3MTA3MzkyNjQsImV4cCI6MTcxMDc0MzE2NCwiYWlvIjoiRTJOZ1lCRHJESC90blRubnhzMm5rVWZtUEg4ZERRQT0iLCJhcHBpZCI6IjE0ZGZhOGYzLWUwZTktNDIwYy04ODlhLWY3YzNkMzY5ZjYwNCIsImFwcGlkYWNyIjoiMSIsImlkcCI6Imh0dHBzOi8vc3RzLndpbmRvd3MubmV0LzM5YzM0NWFlLWJmMGQtNDBiZi1hYmE5LTA4MTk3OTM1Njg3OS8iLCJvaWQiOiI0MTMxOGQ5ZS1mNmZhLTQzMGEtOWQzMC0xNDQ0ZDFmYzJmNzMiLCJyaCI6IjAuQVZNQXJrWERPUTJfdjBDcnFRZ1plVFZvZVFJQUFBQUFBQUFBd0FBQUFBQUFBQURGQUFBLiIsInN1YiI6IjQxMzE4ZDllLWY2ZmEtNDMwYS05ZDMwLTE0NDRkMWZjMmY3MyIsInRlbmFudF9yZWdpb25fc2NvcGUiOiJBUyIsInRpZCI6IjM5YzM0NWFlLWJmMGQtNDBiZi1hYmE5LTA4MTk3OTM1Njg3OSIsInV0aSI6Ikt1LWZkazlkRGtpR3RMQ2g0eUVWQUEiLCJ2ZXIiOiIxLjAifQ.DGmH0YYAYnrTVWWLS58v6bdBT4TUjXRX-cSObmrzKvMDOJ9sxZYaRPWziFbts2IbtHOYlyHxbTW2mDCK96tN7zCBOnUk_h7TD5_6OLFpEW2BRIHqknTslGqCSHVaowFCidpgvzUvChkV7NfH0XLQl4DA0O3am9hxpVHbxzUjr3jm6xhdkRdwcQ1jX5iHor-XMhNqxGn4RJHt-lwNvh7hnsBEctwuHo_VvoZuplGOsYlBuVXpKxDsXyiE1g7tUoP34kqEr3Ayx5ydTqNyTk4TsMsAfOccvXJ-r7axhT-c9yDUadbjRAYbmtf-gvht8PScAx2CPhs5djsk0NadsWiA5g'

# Create a message
message = MIMEText('This is a test email.')
message['Subject'] = 'Test Email'
message['From'] = sender_email
message['To'] = recipient_email

# Connect to the SMTP server and send the email
try:
    smtp = smtplib.SMTP(smtp_server, smtp_port)
    smtp.starttls()
    
    # Prepare the OAuth 2.0 token for authentication
    auth_str = '\x00' + sender_email + '\x00' + access_token
    auth_bytes = auth_str.encode('ascii')
    auth_b64 = base64.b64encode(auth_bytes)
    
    # Send AUTH command with XOAUTH2 mechanism
    smtp.docmd('AUTH', 'XOAUTH2 ' + auth_b64.decode('ascii'))
    
    # Send the email
    smtp.sendmail(sender_email, recipient_email, message.as_string())
    print('Email sent successfully!')
except Exception as e:
    print('Failed to send email:', e)
finally:
    smtp.quit()
