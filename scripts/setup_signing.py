#!/usr/bin/env python3
"""Set up Apple code signing from org secrets. Regenerates cert + profiles if needed.

Requires env vars: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY, APPLE_TEAM_ID
Creates all files in ~/.asc/ needed for the TestFlight build pipeline.
"""
import base64, json, os, subprocess, sys, tempfile

sys.path.insert(0, os.path.dirname(__file__))
from asc_api import api, get_token, ASC_DIR

TEAM_ID = os.environ.get("APPLE_TEAM_ID", "Y9ZLF8R6XZ")
MAIN_BUNDLE_ID_RESOURCE = "73WHP4Q899"     # com.cogfordevin.ios
WIDGET_BUNDLE_ID_RESOURCE = "5QPDTYJW94"   # com.cogfordevin.ios.sessions-widget
WWDR_URL = "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer"
RCODESIGN_VERSION = "0.29.0"
RCODESIGN_URL = f"https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F{RCODESIGN_VERSION}/apple-codesign-{RCODESIGN_VERSION}-x86_64-unknown-linux-musl.tar.gz"

WIDGET_ENTITLEMENTS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>beta-reports-active</key>
\t<true/>
\t<key>application-identifier</key>
\t<string>{team_id}.com.cogfordevin.ios.sessions-widget</string>
\t<key>keychain-access-groups</key>
\t<array>
\t\t<string>{team_id}.*</string>
\t\t<string>com.apple.token</string>
\t</array>
\t<key>get-task-allow</key>
\t<false/>
\t<key>com.apple.developer.team-identifier</key>
\t<string>{team_id}</string>
</dict>
</plist>"""


def run(cmd, check=True, **kwargs):
    print(f"  $ {cmd}")
    return subprocess.run(cmd, shell=True, check=check, capture_output=True, text=True, **kwargs)


def setup_asc_dir():
    os.makedirs(ASC_DIR, exist_ok=True)
    # Write API key .p8 from env var
    key_id = os.environ.get("ASC_KEY_ID", "")
    key_path = os.path.join(ASC_DIR, f"AuthKey_{key_id}.p8")
    if not os.path.exists(key_path):
        pk = os.environ.get("ASC_PRIVATE_KEY", "")
        if pk:
            with open(key_path, 'w') as f:
                f.write(pk)
            os.chmod(key_path, 0o600)
            print(f"Wrote API key to {key_path}")


def download_wwdr():
    pem_path = os.path.join(ASC_DIR, "AppleWWDRCAG3.pem")
    if os.path.exists(pem_path):
        print(f"WWDR cert exists: {pem_path}")
        return pem_path
    cer_path = os.path.join(ASC_DIR, "AppleWWDRCAG3.cer")
    run(f"curl -sL '{WWDR_URL}' -o '{cer_path}'")
    run(f"openssl x509 -inform DER -in '{cer_path}' -out '{pem_path}'")
    print(f"Downloaded WWDR cert: {pem_path}")
    return pem_path


def find_or_create_cert():
    """Find existing DISTRIBUTION cert or create a new one."""
    cert_pem_path = os.path.join(ASC_DIR, "apple_dist_cert.pem")
    key_pem_path = os.path.join(ASC_DIR, "dist_key.pem")

    # Check for existing valid cert
    data = api('GET', '/v1/certificates?filter[certificateType]=DISTRIBUTION')
    certs = data.get('data', [])
    valid_certs = [c for c in certs if c['attributes']['certificateType'] == 'DISTRIBUTION']

    if valid_certs and os.path.exists(key_pem_path):
        # We have a cert and key already — download the cert content
        cert = valid_certs[0]
        cert_content = cert['attributes'].get('certificateContent', '')
        if cert_content:
            cert_der = base64.b64decode(cert_content)
            der_path = os.path.join(ASC_DIR, "dist_cert.der")
            with open(der_path, 'wb') as f:
                f.write(cert_der)
            run(f"openssl x509 -inform DER -in '{der_path}' -out '{cert_pem_path}'")
        print(f"Reusing existing cert {cert['id']} with local key")
        return cert['id'], cert_pem_path, key_pem_path, False

    # Need to create a new cert (and key)
    print("Creating new distribution certificate...")

    # Revoke any existing DISTRIBUTION certs (limit of ~3)
    for cert in valid_certs:
        print(f"  Revoking old cert {cert['id']}...")
        api('DELETE', f"/v1/certificates/{cert['id']}")

    # Generate key + CSR
    run(f"openssl genrsa -out '{key_pem_path}' 2048")
    os.chmod(key_pem_path, 0o600)

    csr_path = os.path.join(ASC_DIR, "dist.csr")
    run(f"openssl req -new -key '{key_pem_path}' -out '{csr_path}' -subj '/CN=Cog Distribution/O={TEAM_ID}'")

    with open(csr_path, 'r') as f:
        csr_content = f.read()

    result = api('POST', '/v1/certificates', {
        'data': {
            'type': 'certificates',
            'attributes': {
                'certificateType': 'DISTRIBUTION',
                'csrContent': csr_content
            }
        }
    })
    if 'errors' in result:
        for e in result['errors']:
            print(f"ERROR creating cert: {e.get('detail', e)}")
        sys.exit(1)

    cert = result['data']
    cert_content = cert['attributes']['certificateContent']
    cert_der = base64.b64decode(cert_content)
    der_path = os.path.join(ASC_DIR, "dist_cert.der")
    with open(der_path, 'wb') as f:
        f.write(cert_der)
    run(f"openssl x509 -inform DER -in '{der_path}' -out '{cert_pem_path}'")
    print(f"Created cert {cert['id']}")

    return cert['id'], cert_pem_path, key_pem_path, True


def create_p12(cert_pem, key_pem, wwdr_pem):
    """Create P12 keystore with full chain."""
    p12_path = os.path.join(ASC_DIR, "apple_dist_chain.p12")
    run(
        f"openssl pkcs12 -export "
        f"-inkey '{key_pem}' "
        f"-in '{cert_pem}' "
        f"-certfile '{wwdr_pem}' "
        f"-out '{p12_path}' "
        f"-passout pass:devin"
    )
    print(f"Created P12: {p12_path}")
    return p12_path


def setup_profiles(cert_id, cert_is_new=False):
    """Download existing profiles or create new ones. Recreates if cert changed."""
    data = api('GET', '/v1/profiles?filter[profileType]=IOS_APP_STORE')
    profiles = {p['attributes']['name']: p for p in data.get('data', [])}

    # If cert was recreated, delete old profiles so they get recreated with new cert
    if cert_is_new:
        for name in ['Cog Distribution', 'Cog_Widget_Distribution']:
            if name in profiles:
                print(f"  Deleting old profile {profiles[name]['id']} (cert changed)...")
                api('DELETE', f"/v1/profiles/{profiles[name]['id']}")
        profiles = {}

    # Main app profile
    main_profile_path = os.path.join(ASC_DIR, "Cog Distribution.mobileprovision")
    if 'Cog Distribution' in profiles:
        p = profiles['Cog Distribution']
        content = p['attributes'].get('profileContent', '')
        if content:
            with open(main_profile_path, 'wb') as f:
                f.write(base64.b64decode(content))
            print(f"Downloaded main profile: {p['id']}")
        else:
            # Need to re-fetch with content
            detail = api('GET', f"/v1/profiles/{p['id']}")
            content = detail['data']['attributes'].get('profileContent', '')
            if content:
                with open(main_profile_path, 'wb') as f:
                    f.write(base64.b64decode(content))
                print(f"Downloaded main profile: {p['id']}")
    else:
        print("Creating main app profile...")
        from asc_api import create_profile
        create_profile("Cog Distribution", MAIN_BUNDLE_ID_RESOURCE, cert_id, "IOS_APP_STORE")

    # Widget profile
    widget_profile_path = os.path.join(ASC_DIR, "Cog_Widget_Distribution.mobileprovision")
    if 'Cog_Widget_Distribution' in profiles:
        p = profiles['Cog_Widget_Distribution']
        content = p['attributes'].get('profileContent', '')
        if content:
            with open(widget_profile_path, 'wb') as f:
                f.write(base64.b64decode(content))
            print(f"Downloaded widget profile: {p['id']}")
        else:
            detail = api('GET', f"/v1/profiles/{p['id']}")
            content = detail['data']['attributes'].get('profileContent', '')
            if content:
                with open(widget_profile_path, 'wb') as f:
                    f.write(base64.b64decode(content))
                print(f"Downloaded widget profile: {p['id']}")
    else:
        print("Creating widget profile...")
        from asc_api import create_profile
        create_profile("Cog_Widget_Distribution", WIDGET_BUNDLE_ID_RESOURCE, cert_id, "IOS_APP_STORE")


def install_rcodesign():
    rcodesign_dir = f"/tmp/apple-codesign-{RCODESIGN_VERSION}-x86_64-unknown-linux-musl"
    rcodesign_bin = os.path.join(rcodesign_dir, "rcodesign")
    if os.path.exists(rcodesign_bin):
        print(f"rcodesign already installed: {rcodesign_bin}")
        return rcodesign_bin
    print("Installing rcodesign...")
    run(f"curl -sL '{RCODESIGN_URL}' -o /tmp/rcodesign.tar.gz")
    run(f"tar xzf /tmp/rcodesign.tar.gz -C /tmp/")
    run(f"chmod +x '{rcodesign_bin}'")
    print(f"Installed rcodesign: {rcodesign_bin}")
    return rcodesign_bin


def write_widget_entitlements():
    path = os.path.join(ASC_DIR, "widget_entitlements.plist")
    with open(path, 'w') as f:
        f.write(WIDGET_ENTITLEMENTS.format(team_id=TEAM_ID))
    print(f"Wrote widget entitlements: {path}")
    return path


def main():
    print("=== Cog iOS Signing Setup ===\n")

    print("[1/6] Setting up ASC directory...")
    setup_asc_dir()

    print("\n[2/6] Downloading WWDR intermediate cert...")
    wwdr_pem = download_wwdr()

    print("\n[3/6] Finding or creating distribution certificate...")
    cert_id, cert_pem, key_pem, cert_is_new = find_or_create_cert()

    print("\n[4/6] Creating P12 keystore...")
    create_p12(cert_pem, key_pem, wwdr_pem)

    print("\n[5/6] Setting up provisioning profiles...")
    setup_profiles(cert_id, cert_is_new)

    print("\n[6/6] Installing rcodesign + writing entitlements...")
    install_rcodesign()
    write_widget_entitlements()

    print("\n=== Setup complete! ===")
    print(f"Signing files in: {ASC_DIR}")
    for f in sorted(os.listdir(ASC_DIR)):
        print(f"  {f}")


if __name__ == '__main__':
    main()
