#!/usr/bin/env python3
"""App Store Connect API helper. Uses env vars for auth."""
import jwt, time, json, requests, base64, sys, os

ASC_DIR = os.path.expanduser("~/.asc")

def _get_config():
    key_id = os.environ.get("ASC_KEY_ID", "")
    issuer_id = os.environ.get("ASC_ISSUER_ID", "")
    key_path = os.path.join(ASC_DIR, f"AuthKey_{key_id}.p8")
    if not key_id or not issuer_id:
        raise RuntimeError("ASC_KEY_ID and ASC_ISSUER_ID env vars required")
    # Try key file first, fall back to ASC_PRIVATE_KEY env var
    if os.path.exists(key_path):
        with open(key_path, 'r') as f:
            private_key = f.read()
    else:
        private_key = os.environ.get("ASC_PRIVATE_KEY", "")
        if not private_key:
            raise RuntimeError(f"No key at {key_path} and ASC_PRIVATE_KEY env var not set")
    return key_id, issuer_id, private_key

def get_token():
    key_id, issuer_id, private_key = _get_config()
    now = int(time.time())
    payload = {'iss': issuer_id, 'iat': now, 'exp': now + 1200, 'aud': 'appstoreconnect-v1'}
    headers = {'kid': key_id, 'typ': 'JWT'}
    return jwt.encode(payload, private_key, algorithm='ES256', headers=headers)

def api_headers():
    return {
        'Authorization': f'Bearer {get_token()}',
        'Content-Type': 'application/json'
    }

def api(method, endpoint, data=None):
    url = f'https://api.appstoreconnect.apple.com{endpoint}'
    resp = requests.request(method, url, headers=api_headers(), json=data)
    return resp.json() if resp.content else {}

def create_profile(name, bundle_id_resource_id, cert_id, profile_type='IOS_APP_STORE'):
    result = api('POST', '/v1/profiles', {
        'data': {
            'type': 'profiles',
            'attributes': {'name': name, 'profileType': profile_type},
            'relationships': {
                'bundleId': {'data': {'type': 'bundleIds', 'id': bundle_id_resource_id}},
                'certificates': {'data': [{'type': 'certificates', 'id': cert_id}]}
            }
        }
    })
    if 'errors' in result:
        for e in result['errors']:
            print(f"ERROR: {e.get('detail', e)}")
        return None
    profile = result['data']
    attrs = profile['attributes']
    content = attrs.get('profileContent', '')
    if content:
        os.makedirs(ASC_DIR, exist_ok=True)
        path = os.path.join(ASC_DIR, f'{name}.mobileprovision')
        with open(path, 'wb') as f:
            f.write(base64.b64decode(content))
        print(f"Profile saved: {path}")
    return profile

if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'help'
    if cmd == 'get-jwt':
        print(get_token())
    elif cmd == 'list-certs':
        for c in api('GET', '/v1/certificates').get('data', []):
            a = c['attributes']
            print(f"{c['id']}: {a['certificateType']} - {a['displayName']} (expires: {a['expirationDate']})")
    elif cmd == 'list-profiles':
        for p in api('GET', '/v1/profiles').get('data', []):
            a = p['attributes']
            print(f"{p['id']}: {a['name']} ({a['profileType']}) - {a['profileState']} (expires: {a['expirationDate']})")
    elif cmd == 'list-apps':
        for a in api('GET', '/v1/apps').get('data', []):
            print(f"{a['id']}: {a['attributes']['name']} ({a['attributes']['bundleId']})")
    elif cmd == 'create-profile':
        create_profile(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] if len(sys.argv) > 5 else 'IOS_APP_STORE')
    else:
        print("Commands: get-jwt, list-certs, list-profiles, list-apps, create-profile <name> <bid_id> <cert_id> [type]")
