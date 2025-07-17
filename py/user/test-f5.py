import smtplib
from email.message import EmailMessage

def send_email(subject, body, to_email, user, password, f5_server_ip):
    msg = EmailMessage()
    msg.set_content(body)
    msg['Subject'] = subject
    msg['From'] = user
    msg['To'] = to_email

    try:
        # Connect to the F5 Load Balancer, which will handle the Basic Auth to OAuth transformation
        server = smtplib.SMTP(f5_server_ip, 587, timeout=10)  # Set timeout for connection attempt
        server.starttls()  # Establish a secure connection
        server.login(user, password)  # Basic Auth login (to be transformed by F5)
        server.send_message(msg)
        print("Email sent successfully!")
    except Exception as e:
        print(f"Failed to send email: {e}")
    finally:
        try:
            server.quit()
        except NameError:
            pass  # If `server` was never created due to an error, this avoids another exception

# Configuration parameters
f5_server_ip = '192.168.10.51'  # IP of the F5 Virtual Server
user = 'maleakhi@dikstrasolusi.com'  # Replace with your email address
password = '.'  # Replace with your password
to_email = 'recipient@domain.com'  # Recipient's email address for testing

# Test sending the email
send_email("Test Subject", "This is a test email body.", to_email, user, password, f5_server_ip)
