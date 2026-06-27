#!/usr/bin/env python3
"""Set up Apple code signing from CI secrets. Regenerates cert + profiles if needed.

Requires env vars:
ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY, APPLE_TEAM_ID,
APPLE_DIST_P12_PASSWORD, COG_MAIN_BUNDLE_ID,
COG_MAIN_BUNDLE_ID_RESOURCE, COG_MAIN_PROFILE_NAME.

Creates all files in ~/.asc/ needed for the TestFlight build pipeline.
"""
import base64, os, shlex, subprocess, sys

sys.path.insert(0, os.path.dirname(__file__))
from asc_api import api, ASC_DIR


def require_env(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"{name} env var required")
    return value


TEAM_ID = require_env("APPLE_TEAM_ID")
MAIN_BUNDLE_ID = require_env("COG_MAIN_BUNDLE_ID")
MAIN_BUNDLE_ID_RESOURCE = require_env("COG_MAIN_BUNDLE_ID_RESOURCE")
MAIN_PROFILE_NAME = require_env("COG_MAIN_PROFILE_NAME")
P12_PASSWORD = require_env("APPLE_DIST_P12_PASSWORD")
BEGIN_PRIVATE_KEY = "-----BEGIN PRIVATE" " KEY-----"
END_PRIVATE_KEY = "-----END PRIVATE" " KEY-----"
WWDR_URL = "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer"


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


def _restore_key_from_secret():
    """Write dist_key.pem from APPLE_DIST_KEY_PEM org secret if not on disk.

    Handles two formats:
    - Proper PEM with newlines (from well-behaved secret stores)
    - Single-line PEM where newlines were lost (re-wraps at 64 chars)
    """
    key_pem_path = os.path.join(ASC_DIR, "dist_key.pem")
    if os.path.exists(key_pem_path):
        return True
    key_pem = os.environ.get("APPLE_DIST_KEY_PEM", "")
    if not key_pem:
        return False

    # Check if newlines were stripped (entire PEM on one or two lines)
    lines = key_pem.strip().splitlines()
    if len(lines) <= 2:
        # Newlines lost — extract base64 body and re-wrap at 64 chars
        body = key_pem.replace(BEGIN_PRIVATE_KEY, "") \
                      .replace(END_PRIVATE_KEY, "") \
                      .replace(" ", "").replace("\n", "").replace("\r", "")
        wrapped = "\n".join(body[i:i+64] for i in range(0, len(body), 64))
        key_pem = f"{BEGIN_PRIVATE_KEY}\n{wrapped}\n{END_PRIVATE_KEY}\n"

    with open(key_pem_path, 'w') as f:
        f.write(key_pem)
    os.chmod(key_pem_path, 0o600)
    print(f"Restored distribution key from APPLE_DIST_KEY_PEM secret")
    return True


def _key_matches_cert(key_pem_path, cert_pem_path):
    """Check if a private key matches a certificate by comparing public key modulus."""
    try:
        key_mod = run(f"openssl rsa -in '{key_pem_path}' -modulus -noout", check=False)
        cert_mod = run(f"openssl x509 -in '{cert_pem_path}' -modulus -noout", check=False)
        return (key_mod.returncode == 0 and cert_mod.returncode == 0
                and key_mod.stdout.strip() == cert_mod.stdout.strip())
    except Exception:
        return False


def find_or_create_cert():
    """Find existing DISTRIBUTION cert matching our key, or create one."""
    cert_pem_path = os.path.join(ASC_DIR, "apple_dist_cert.pem")
    key_pem_path = os.path.join(ASC_DIR, "dist_key.pem")

    # Restore private key from org secret if not on disk
    _restore_key_from_secret()
    has_key = os.path.exists(key_pem_path)

    # Check for existing valid certs
    data = api('GET', '/v1/certificates?filter[certificateType]=DISTRIBUTION')
    certs = data.get('data', [])
    valid_certs = [c for c in certs if c['attributes']['certificateType'] == 'DISTRIBUTION']

    # Try to find a cert that matches our key
    if valid_certs and has_key:
        der_path = os.path.join(ASC_DIR, "dist_cert.der")
        for cert in valid_certs:
            cert_content = cert['attributes'].get('certificateContent', '')
            if not cert_content:
                continue
            cert_der = base64.b64decode(cert_content)
            with open(der_path, 'wb') as f:
                f.write(cert_der)
            run(f"openssl x509 -inform DER -in '{der_path}' -out '{cert_pem_path}'")
            if _key_matches_cert(key_pem_path, cert_pem_path):
                print(f"Reusing existing cert {cert['id']} (key matches)")
                return cert['id'], cert_pem_path, key_pem_path, False
        # No matching cert — create one using our existing key (below)
        print("No existing cert matches the saved key")

    if has_key:
        # Create a new cert using the EXISTING key (from secret) — no new key needed
        print("Creating cert from existing key...")
    else:
        # No key at all — generate a new one
        print("No key available, generating new key + cert...")
        run(f"openssl genrsa -out '{key_pem_path}' 2048")
        os.chmod(key_pem_path, 0o600)

    # Only revoke if at Apple's limit (~3 active distribution certs)
    MAX_DIST_CERTS = 3
    if len(valid_certs) >= MAX_DIST_CERTS:
        oldest = sorted(valid_certs, key=lambda c: c['attributes'].get('expirationDate', ''))[0]
        print(f"  At cert limit ({MAX_DIST_CERTS}), revoking oldest cert {oldest['id']}...")
        api('DELETE', f"/v1/certificates/{oldest['id']}")

    csr_path = os.path.join(ASC_DIR, "dist.csr")
    subject = shlex.quote(f"/CN={MAIN_PROFILE_NAME}/O={TEAM_ID}")
    run(f"openssl req -new -key '{key_pem_path}' -out '{csr_path}' -subj {subject}")

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
    """Create P12 keystore with full chain.

    Uses -legacy flag on OpenSSL 3.x to produce a PKCS12 that macOS
    security-import can read (macOS doesn't support AES-256-CBC PKCS12).
    Falls back without -legacy for LibreSSL / older OpenSSL.
    """
    p12_path = os.path.join(ASC_DIR, "apple_dist_chain.p12")
    base_cmd = (
        f"openssl pkcs12 -export "
        f"-inkey '{key_pem}' "
        f"-in '{cert_pem}' "
        f"-certfile '{wwdr_pem}' "
        f"-out '{p12_path}' "
        f"-passout {shlex.quote('pass:' + P12_PASSWORD)}"
    )
    result = run(f"{base_cmd} -legacy", check=False)
    if result.returncode != 0:
        run(base_cmd)
    print(f"Created P12: {p12_path}")
    return p12_path


def setup_profiles(cert_id, cert_is_new=False):
    """Download existing profiles or create new ones. Recreates if cert changed."""
    data = api('GET', '/v1/profiles?filter[profileType]=IOS_APP_STORE')
    profiles = {p['attributes']['name']: p for p in data.get('data', [])}

    # If cert was recreated, delete old profiles so they get recreated with new cert
    if cert_is_new:
        if MAIN_PROFILE_NAME in profiles:
            print(f"  Deleting old profile {profiles[MAIN_PROFILE_NAME]['id']} (cert changed)...")
            api('DELETE', f"/v1/profiles/{profiles[MAIN_PROFILE_NAME]['id']}")
        profiles = {}

    # Main app profile
    main_profile_path = os.path.join(ASC_DIR, f"{MAIN_PROFILE_NAME}.mobileprovision")
    if MAIN_PROFILE_NAME in profiles:
        p = profiles[MAIN_PROFILE_NAME]
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
        create_profile(MAIN_PROFILE_NAME, MAIN_BUNDLE_ID_RESOURCE, cert_id, "IOS_APP_STORE")


def main():
    print("=== Cog iOS Signing Setup ===\n")

    print("[1/5] Setting up ASC directory...")
    setup_asc_dir()

    print("\n[2/5] Downloading WWDR intermediate cert...")
    wwdr_pem = download_wwdr()

    print("\n[3/5] Finding or creating distribution certificate...")
    cert_id, cert_pem, key_pem, cert_is_new = find_or_create_cert()

    print("\n[4/5] Creating P12 keystore...")
    create_p12(cert_pem, key_pem, wwdr_pem)

    print("\n[5/5] Setting up provisioning profiles...")
    setup_profiles(cert_id, cert_is_new)

    print("\n=== Setup complete! ===")
    print(f"Signing files in: {ASC_DIR}")
    for f in sorted(os.listdir(ASC_DIR)):
        print(f"  {f}")


if __name__ == '__main__':
    main()
