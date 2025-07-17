#!/usr/bin/env python3
import msal
import json

CLIENT_ID = '14dfa8f3-e0e9-420c-889a-f7c3d369f604'
CLIENT_SECRET = 'bZF8Q~0~OP9UDByaJ1JP3ElR6rAv~3ENew.u4cg1'
TENANT_ID = '39c345ae-bf0d-40bf-aba9-081979356879'
AUTHORITY = f"https://login.microsoftonline.com/{TENANT_ID}"
SCOPE = ["https://graph.microsoft.com/.default"]

# USERNAME = input("Service account UPN: ")
# PASSWORD = input("Service account password: ")

USERNAME = 'maleakhi@dikstrasolusi.com'
PASSWORD = 'Sayangmamih1.'


app = msal.PublicClientApplication(CLIENT_ID, authority=AUTHORITY)

result = app.acquire_token_by_username_password(
    username=USERNAME,
    password=PASSWORD,
    scopes=SCOPE
)

if "access_token" in result:
    print("✅ Token acquired using ROPC (username/password).")
else:
    print("❌ Failed to acquire token:")
    print(json.dumps(result, indent=2))