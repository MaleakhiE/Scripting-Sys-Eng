import requests
import json
import csv
import msal

# Azure AD authentication parameters
TENANT_ID = '6b937f07-afd5-45f0-bc7b-37b9575d6e86'
CLIENT_ID = 'fffdd242-53f0-4345-8a1b-0d6b8466ce4e'
CLIENT_SECRET = 'rTB8Q~-kHc43LMgapa-w5JPi8hNELhkfhnvhcbXQ'
SCOPE = ['https://graph.microsoft.com/.default']

def get_access_token():
    """Get an access token using MSAL"""
    authority = f"https://login.microsoftonline.com/{TENANT_ID}"
    app = msal.ConfidentialClientApplication(
        CLIENT_ID,
        authority=authority,
        client_credential=CLIENT_SECRET
    )
    result = app.acquire_token_for_client(scopes=SCOPE)
    if 'access_token' in result:
        print("Access token acquired successfully")
        return result['access_token']
    else:
        print("Failed to acquire token:", result.get("error_description"))
        return None

def get_all_users(token):
    """Fetch all users in the organization"""
    url = "https://graph.microsoft.com/v1.0/users"
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    all_users = []
    
    while url:
        response = requests.get(url, headers=headers)
        if response.status_code != 200:
            print(f"Error {response.status_code}: {response.text}")
            return []
        
        data = response.json()
        all_users.extend(data.get('value', []))
        url = data.get('@odata.nextLink', None)  # Handle pagination if necessary

    return all_users

def get_user_sponsors(token, user_id):
    """Fetch sponsors for a specific user"""
    url = f"https://graph.microsoft.com/v1.0/users/{user_id}/sponsors"
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    response = requests.get(url, headers=headers)
    
    if response.status_code != 200:
        print(f"Error fetching sponsors for user {user_id}: {response.status_code}")
        return []
    
    sponsors = response.json().get('value', [])
    return [sponsor.get('displayName') for sponsor in sponsors]

def get_users_with_sponsors(token):
    """Fetch users and their sponsors"""
    users = get_all_users(token)
    filtered_users = []

    for user in users:
        user_id = user.get('id')
        sponsors = get_user_sponsors(token, user_id)

        # Add user to list if sponsors are found
        if sponsors:
            filtered_users.append({
                'ID': user.get('id', ''),
                'DisplayName': user.get('displayName', ''),
                'Email': user.get('mail', ''),
                'UserPrincipalName': user.get('userPrincipalName', ''),
                'UserType': user.get('userType', ''),
                'Sponsors': ', '.join(sponsors)
            })

    return filtered_users

def save_to_csv(users):
    """Save the filtered users to a CSV file"""
    with open('filtered_users.csv', mode='w', newline='') as file:
        writer = csv.DictWriter(file, fieldnames=['ID', 'DisplayName', 'Email', 'UserPrincipalName', 'UserType', 'Sponsors'])
        writer.writeheader()
        writer.writerows(users)
    print("Saved filtered users to filtered_users.csv")

if __name__ == "__main__":
    token = get_access_token()
    if token:
        users_with_sponsors = get_users_with_sponsors(token)
        if users_with_sponsors:
            print(f"Found {len(users_with_sponsors)} users with Sponsors.")
            save_to_csv(users_with_sponsors)
        else:
            print("No users found with Sponsors.")
    else:
        print("Could not authenticate and retrieve users.")
