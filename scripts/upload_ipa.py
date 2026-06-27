#!/usr/bin/env python3
"""Upload an IPA to App Store Connect for TestFlight processing."""
import os, sys, zipfile, plistlib, time
import requests

# Re-use auth from asc_api
sys.path.insert(0, os.path.dirname(__file__))
from asc_api import api_headers

BASE = "https://api.appstoreconnect.apple.com"


def extract_ipa_info(ipa_path):
    with zipfile.ZipFile(ipa_path, 'r') as z:
        for name in z.namelist():
            if name.endswith('.app/Info.plist') and name.count('/') == 2:
                with z.open(name) as f:
                    plist = plistlib.load(f)
                    return {
                        'version': plist.get('CFBundleShortVersionString', '0.1.0'),
                        'build_number': plist.get('CFBundleVersion', '1'),
                        'bundle_id': plist.get('CFBundleIdentifier', ''),
                        'name': plist.get('CFBundleName', ''),
                    }
    return None


def upload_ipa(app_id, ipa_path):
    ipa_size = os.path.getsize(ipa_path)
    info = extract_ipa_info(ipa_path)
    if not info:
        print("ERROR: Could not extract Info.plist from IPA")
        return False

    print(f"IPA: {info['name']} v{info['version']} build {info['build_number']} ({ipa_size} bytes)")

    with open(ipa_path, 'rb') as f:
        ipa_bytes = f.read()

    # 1. Create build upload
    print("1. Creating build upload...")
    resp = requests.post(f"{BASE}/v1/buildUploads", headers=api_headers(), json={
        "data": {
            "type": "buildUploads",
            "attributes": {
                "cfBundleShortVersionString": info['version'],
                "cfBundleVersion": info['build_number'],
                "platform": "IOS",
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}}
            }
        }
    })
    if resp.status_code >= 400:
        print(f"ERROR ({resp.status_code}): {resp.text}")
        return False
    upload_data = resp.json()
    if 'errors' in upload_data:
        for e in upload_data['errors']:
            print(f"ERROR: {e.get('detail', e)}")
        return False
    upload_id = upload_data['data']['id']
    print(f"   Upload ID: {upload_id}")

    # 2. Create upload file entry
    print("2. Creating upload file entry...")
    resp = requests.post(f"{BASE}/v1/buildUploadFiles", headers=api_headers(), json={
        "data": {
            "type": "buildUploadFiles",
            "attributes": {
                "fileName": os.path.basename(ipa_path),
                "fileSize": ipa_size,
                "assetType": "ASSET",
                "uti": "com.apple.ipa",
            },
            "relationships": {
                "buildUpload": {"data": {"type": "buildUploads", "id": upload_id}}
            }
        }
    })
    if resp.status_code >= 400:
        print(f"ERROR ({resp.status_code}): {resp.text}")
        return False
    file_data = resp.json()
    if 'errors' in file_data:
        for e in file_data['errors']:
            print(f"ERROR: {e.get('detail', e)}")
        return False
    file_id = file_data['data']['id']
    upload_ops = file_data['data']['attributes'].get('uploadOperations', [])

    # 3. Upload chunks to presigned URLs
    print(f"3. Uploading ({len(upload_ops)} parts)...")
    for i, op in enumerate(upload_ops):
        chunk = ipa_bytes[op.get('offset', 0):op.get('offset', 0) + op.get('length', ipa_size)]
        req_headers = {h['name']: h['value'] for h in op.get('requestHeaders', [])}
        resp = requests.request(op.get('method', 'PUT'), op['url'], headers=req_headers, data=chunk)
        if resp.status_code >= 400:
            print(f"   Part {i+1} FAILED ({resp.status_code})")
            return False
        print(f"   Part {i+1} OK")

    # 4. Confirm upload
    print("4. Confirming upload...")
    resp = requests.patch(f"{BASE}/v1/buildUploadFiles/{file_id}", headers=api_headers(), json={
        "data": {"type": "buildUploadFiles", "id": file_id, "attributes": {"uploaded": True}}
    })
    if resp.status_code >= 400:
        print(f"ERROR ({resp.status_code}): {resp.text}")
        return False

    # 5. Poll processing state
    print("5. Polling processing state...")
    for _ in range(60):
        time.sleep(10)
        resp = requests.get(f"{BASE}/v1/buildUploads/{upload_id}", headers=api_headers())
        state = resp.json()['data']['attributes'].get('processingState', 'unknown')
        print(f"   State: {state}")
        if state in ('VALID', 'FAILED', 'INVALID'):
            if state == 'VALID':
                print(f"\nBuild uploaded successfully! Check TestFlight for app {app_id}")
                return True
            else:
                errors = resp.json()['data']['attributes'].get('processingErrors', [])
                for e in errors:
                    print(f"   Error: {e}")
                return False
    print("Timed out waiting for processing")
    return False


if __name__ == '__main__':
    app_id = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("COG_ASC_APP_ID", "")
    if not app_id:
        print("ERROR: pass app_id as the first argument or set COG_ASC_APP_ID")
        sys.exit(2)

    ipa_path = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.asc/Cog_final.ipa")
    sys.exit(0 if upload_ipa(app_id, ipa_path) else 1)
