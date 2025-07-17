#!/usr/bin/env python3
import msal
import json

CLIENT_ID = '14dfa8f3-e0e9-420c-889a-f7c3d369f604'
CLIENT_SECRET = 'bZF8Q~0~OP9UDByaJ1JP3ElR6rAv~3ENew.u4cg1'
TENANT_ID = '39c345ae-bf0d-40bf-aba9-081979356879'
AUTHORITY = f"https://login.microsoftonline.com/{TENANT_ID}"
SCOPE = ["https://graph.microsoft.com/.default"]

app = msal.ConfidentialClientApplication(
    CLIENT_ID,
    authority=AUTHORITY,
    client_credential=CLIENT_SECRET
)

result = app.acquire_token_for_client(scopes=SCOPE)

if "access_token" in result:
    print("✅ Access token acquired, MFA does not apply to client credentials.")
    print("Access Token:", result['access_token'])
else:
    print("❌ Failed to acquire token:")
    print(json.dumps(result, indent=2))