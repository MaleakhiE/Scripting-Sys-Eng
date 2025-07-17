#!/usr/bin/env python3
import msal
import json
import requests
import hashlib
import base64
import os

# Application registration details
CLIENT_ID = '14dfa8f3-e0e9-420c-889a-f7c3d369f604'
CLIENT_SECRET = 'bZF8Q~0~OP9UDByaJ1JP3ElR6rAv~3ENew.u4cg1'
TENANT_ID = '39c345ae-bf0d-40bf-aba9-081979356879'
AUTHORITY = f"https://login.microsoftonline.com/{TENANT_ID}"

def scenario_1_app_only_auth():
    """
    Scenario 1: App authenticates with client credentials (recommended)
    This is what your ProDesk/AuthLogin should use for Microsoft Graph access
    """
    print("🏢 Scenario 1: App-Only Authentication (Client Credentials)")
    print("=" * 60)
    print("This is for: ProDesk/AuthLogin app accessing Microsoft Graph")
    print("Users login to YOUR app, but app uses its own credentials for Graph API")
    print()
    
    # App authenticates with its own credentials
    app = msal.ConfidentialClientApplication(
        CLIENT_ID,
        authority=AUTHORITY,
        client_credential=CLIENT_SECRET
    )
    
    # Get app-only token
    result = app.acquire_token_for_client(scopes=["https://graph.microsoft.com/.default"])
    
    if "access_token" in result:
        print("✅ App successfully authenticated with Microsoft Graph")
        print("   - App can now access Graph API on behalf of organization")
        print("   - Users login to YOUR app with their own auth system")
        print("   - This approach is NOT affected by the July 24, 2025 MFA requirement")
        
        # Test Graph API call
        headers = {'Authorization': f'Bearer {result["access_token"]}'}
        response = requests.get("https://graph.microsoft.com/v1.0/users", headers=headers)
        
        if response.status_code == 200:
            users = response.json().get('value', [])
            print(f"   - Successfully retrieved {len(users)} users from organization")
            print("   - Your app can read user data, send emails, etc.")
        else:
            print(f"   - Graph API test failed: {response.status_code}")
        
        return True
    else:
        print("❌ App authentication failed:")
        print(json.dumps(result, indent=2))
        return False

def scenario_2_problematic_ropc():
    """
    Scenario 2: App uses ROPC to authenticate users directly with Microsoft Graph
    This is what will be blocked after July 24, 2025
    """
    print("\n🔴 Scenario 2: Problematic ROPC Flow")
    print("=" * 60)
    print("This is the BAD approach that will be blocked after July 24, 2025")
    print("If your app does this, it needs to be changed")
    print()
    
    # Simulate what happens if app tries to authenticate users directly
    app = msal.PublicClientApplication(CLIENT_ID, authority=AUTHORITY)
    
    # This is what will fail with MFA users
    test_users = [
        "maleakhi@dikstrasolusi.com"
    ]
    
    for username in test_users:
        print(f"🔄 Testing ROPC for user: {username}")
        result = app.acquire_token_by_username_password(
            username=username,
            password="Sayangmamih1.",  # This will fail anyway
            scopes=["https://graph.microsoft.com/User.Read"]
        )
        
        if "access_token" in result:
            print(f"   ✅ ROPC succeeded for {username}")
        else:
            error_code = result.get('error', 'Unknown')
            error_desc = result.get('error_description', 'Unknown error')
            print(f"   ❌ ROPC failed for {username}: {error_code}")
            
            if 'AADSTS50126' in error_desc:
                print("       → Invalid credentials")
            elif 'AADSTS50076' in error_desc:
                print("       → MFA required (this is the July 24, 2025 issue)")
            elif 'AADSTS50053' in error_desc:
                print("       → Account locked or disabled")

def scenario_3_recommended_hybrid():
    """
    Scenario 3: Recommended hybrid approach
    """
    print("\n🟢 Scenario 3: Recommended Hybrid Approach")
    print("=" * 60)
    print("How your ProDesk/AuthLogin should work:")
    print()
    
    print("1. 🏢 App Authentication (for Microsoft Graph access):")
    print("   - Your app uses CLIENT_ID + CLIENT_SECRET")
    print("   - Gets app-only token from Microsoft Graph")
    print("   - Can access organization data, send emails, etc.")
    print()
    
    print("2. 👤 User Authentication (for your app access):")
    print("   - Users login to YOUR app with username/password")
    print("   - Your app validates credentials against YOUR database/AD")
    print("   - OR users login with SSO/SAML to your app")
    print("   - Your app determines user permissions")
    print()
    
    print("3. 🔗 Combined Flow:")
    print("   - User logs into ProDesk/AuthLogin → Your app validates")
    print("   - ProDesk/AuthLogin needs Graph data → Uses app token")
    print("   - Example: User requests report → App fetches data via Graph API")
    print()
    
    print("✅ Benefits:")
    print("   - Not affected by MFA requirements")
    print("   - More secure and manageable")
    print("   - Users don't need to know Microsoft Graph credentials")
    print("   - App controls what data each user can access")

def simulate_user_session():
    """
    Simulate how a user session would work in the recommended approach
    """
    print("\n📝 Simulated User Session in Recommended Approach:")
    print("=" * 50)
    
    # Step 1: User logs into your app
    print("1. 👤 User logs into ProDesk/AuthLogin:")
    print("   Username: maleakhi@dikstrasolusi.com")
    print("   Password: [validated by YOUR app]")
    print("   ✅ Login successful")
    print()
    
    # Step 2: App gets Graph token when needed
    print("2. 🏢 App needs Microsoft Graph data:")
    print("   - User clicks 'Get My Calendar'")
    print("   - App uses CLIENT_ID + CLIENT_SECRET to get Graph token")
    print("   - App calls Graph API to get calendar data")
    print("   - App shows calendar to user")
    print()
    
    # Step 3: Show the difference
    print("🔍 Key Difference:")
    print("   ❌ Bad: App directly authenticates user with Microsoft Graph")
    print("   ✅ Good: App authenticates with Graph, user authenticates with app")

def main():
    """
    Main function to test different authentication scenarios
    """
    print("🔐 Authentication Scenario Testing")
    print("Based on: 'Apps (ProDesk/AuthLogin) use CLIENT_ID+SECRET for Graph access'")
    print("Users login to app with username+password")
    print("=" * 70)
    
    # Test the current approach (should work)
    success = scenario_1_app_only_auth()
    
    # Show the problematic approach
    scenario_2_problematic_ropc()
    
    # Show the recommended approach
    scenario_3_recommended_hybrid()
    
    # Simulate user session
    simulate_user_session()
    
    print("\n" + "=" * 70)
    print("📋 Summary for Your ProDesk/AuthLogin Architecture:")
    print()
    if success:
        print("✅ Your current approach (CLIENT_ID + CLIENT_SECRET) is CORRECT")
        print("✅ This will continue working after July 24, 2025")
        print("✅ Users can still login to your app with username/password")
    else:
        print("❌ There might be an issue with your app registration")
    
    print("\n🚨 What to avoid:")
    print("   - Don't use ROPC to authenticate users directly with Microsoft Graph")
    print("   - Don't pass user credentials to Microsoft Graph API")
    print("\n✅ What to keep doing:")
    print("   - Use CLIENT_ID + CLIENT_SECRET for Graph API access")
    print("   - Handle user authentication in your own app")
    print("   - Use app token to access Graph API on behalf of organization")

if __name__ == "__main__":
    main()
