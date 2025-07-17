import requests
import json

# URL provided by Power Automate (replace with your actual URL)
power_automate_url = "https://prod-53.southeastasia.logic.azure.com:443/workflows/374051bf829e4d89a0f508de7967944b/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=sywdCsOtR3cvMI8FTuVelElb2ZB5-pgUu5Un5PAuQOQ"

# Collecting input from the user
email = input("Input Email to send: ").strip()
subject = input("Input Subject: ").strip()
body = input("Input Body: ").strip()

# JSON payload to be sent in the request
payload = {
    "email": email,
    "subject": subject,
    "body": body
}

# Headers for the request
headers = {
    'Content-Type': 'application/json'
}

try:
    # Send the HTTP POST request
    response = requests.post(power_automate_url, headers=headers, data=json.dumps(payload))

    # Check the response
    if response.status_code in [200, 202]:
        print("Email sent successfully via Power Automate!")
    else:
        print(f"Failed to send email. Status code: {response.status_code}")
        print(f"Response: {response.text}")

except requests.exceptions.RequestException as e:
    print(f"An error occurred: {e}")
