import requests
from msal import ConfidentialClientApplication

# === Auth Config ===
CLIENT_ID = "6dec904c-284c-4b73-91da-bc4b9206b58e"
CLIENT_SECRET = "egY8Q~6ZlTGjqkURTfWJY2IYTPk1iRHwJIom-aqH"
TENANT_ID = "c412f886-ab3a-4600-91a2-b67fa3aa95ed"
USER_TO_ASSIGN = "m365.admin@ProtelindoGroup.onmicrosoft.com"

authority = f"https://login.microsoftonline.com/{TENANT_ID}"
scope = ["https://graph.microsoft.com/.default"]

app = ConfidentialClientApplication(
    CLIENT_ID,
    authority=authority,
    client_credential=CLIENT_SECRET
)

token_response = app.acquire_token_for_client(scopes=scope)
if "access_token" not in token_response:
    raise Exception("Failed to get access token")

headers = {
    "Authorization": f"Bearer {token_response['access_token']}",
    "Content-Type": "application/json"
}

# Get user ID to assign
user_resp = requests.get(
    f"https://graph.microsoft.com/v1.0/users/{USER_TO_ASSIGN}",
    headers=headers
)
user_id = user_resp.json()['id']

# Get all M365 groups (Unified groups)
groups_url = "https://graph.microsoft.com/v1.0/groups?$filter=groupTypes/any(c:c eq 'Unified')"
while groups_url:
    response = requests.get(groups_url, headers=headers).json()
    groups = response.get('value', [])
    
    for group in groups:
        group_id = group["id"]
        group_name = group["displayName"]
        
        # Assign user as owner
        owner_url = f"https://graph.microsoft.com/v1.0/groups/{group_id}/owners/$ref"
        body = {
            "@odata.id": f"https://graph.microsoft.com/v1.0/directoryObjects/{user_id}"
        }

        resp = requests.post(owner_url, headers=headers, json=body)
        if resp.status_code == 204:
            print(f"✅ Added {USER_TO_ASSIGN} as owner to group: {group_name}")
        else:
            print(f"❌ Failed for {group_name}: {resp.status_code} - {resp.text}")
    
    groups_url = response.get('@odata.nextLink')
