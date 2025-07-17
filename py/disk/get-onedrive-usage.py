import csv
import requests
from msal import ConfidentialClientApplication

# === SET YOUR VALUES HERE ===
CLIENT_ID = "14dfa8f3-e0e9-420c-889a-f7c3d369f604"
CLIENT_SECRET = "p8L8Q~Cu6ekc1z6J6PPEGho2eWOPjoNQbyzRjct_"
TENANT_ID = "39c345ae-bf0d-40bf-aba9-081979356879"

# === AUTHENTICATE ===
authority = f"https://login.microsoftonline.com/{TENANT_ID}"
scope = ["https://graph.microsoft.com/.default"]

app = ConfidentialClientApplication(
    CLIENT_ID,
    authority=authority,
    client_credential=CLIENT_SECRET
)

token_response = app.acquire_token_for_client(scopes=scope)
if "access_token" not in token_response:
    raise Exception(f"Token acquisition failed: {token_response.get('error_description')}")

access_token = token_response['access_token']
headers = {
    'Authorization': f'Bearer {access_token}',
    'Content-Type': 'application/json'
}

# === GET ALL USERS ===
print("🔄 Fetching users...")
users = []
url = "https://graph.microsoft.com/v1.0/users?$select=id,displayName,userPrincipalName,mail"
while url:
    response = requests.get(url, headers=headers).json()
    users.extend(response.get('value', []))
    url = response.get('@odata.nextLink')

print(f"✅ Retrieved {len(users)} users.")

# === FETCH ONEDRIVE USAGE PER USER ===
oneDrive_data = []

for user in users:
    user_id = user["id"]
    try:
        drive_url = f"https://graph.microsoft.com/v1.0/users/{user_id}/drive"
        drive_response = requests.get(drive_url, headers=headers).json()

        quota = drive_response.get("quota")
        if quota:
            used = round(quota["used"] / (1024 ** 3), 2)
            total = round(quota["total"] / (1024 ** 3), 2)
            remaining = round((quota["total"] - quota["used"]) / (1024 ** 3), 2)

            oneDrive_data.append({
                "UserId": user_id,
                "UserPrincipalName": user["userPrincipalName"],
                "DisplayName": user["displayName"],
                "Email": user.get("mail", ""),
                "OneDrive_Used_GB": used,
                "OneDrive_Total_GB": total,
                "OneDrive_Remaining_GB": remaining,
                "Quota_State": quota.get("state", "unknown")
            })
        else:
            print(f"⚠️ No quota found for user {user['userPrincipalName']}")

    except Exception as e:
        print(f"❌ Error retrieving drive for {user['userPrincipalName']}: {e}")

# === EXPORT TO CSV ===
csv_file = "M365_OneDrive_Usage.csv"
with open(csv_file, mode='w', newline='', encoding='utf-8') as file:
    fieldnames = [
        "UserId", "UserPrincipalName", "DisplayName", "Email",
        "OneDrive_Used_GB", "OneDrive_Total_GB", "OneDrive_Remaining_GB", "Quota_State"
    ]
    writer = csv.DictWriter(file, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(oneDrive_data)

print(f"✅ Export completed. File saved as {csv_file}")
