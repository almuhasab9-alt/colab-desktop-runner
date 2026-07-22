#!/usr/bin/env python3
"""
Release pipeline for Colab Desktop Runner secure updates.

Generates:
- bsdiff delta patches from previous release APKs to the new APK
- latest.json signed manifest (Ed25519)
- latest.json.sig (hex-encoded raw 64-byte signature)

SECURITY:
- The Ed25519 PRIVATE key is NEVER stored in the repository.
  It is read from the environment variable UPDATE_SIGNING_KEY_HEX
  (64 hex chars = 32 raw bytes) or from a local file path given in
  UPDATE_SIGNING_KEY_FILE. In GitHub Actions use a repository Secret.
- Every generated patch is verified by applying it (bspatch) and
  comparing the rebuilt APK byte-for-byte (SHA-256) before publishing.

Usage:
  python3 tools/release_pipeline.py \
    --new-apk build/app/outputs/flutter-apk/app-release.apk \
    --version-name 1.1.0 --version-code 2 --serial 2 \
    --repo almuhasab9-alt/colab-desktop-runner --tag v1.1.0 \
    --old-apk 1:path/to/v1.0.0.apk [--old-apk CODE:PATH ...] \
    --out dist/
"""
import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timedelta, timezone

try:
    import bsdiff4
except ImportError:
    print("ERROR: pip install bsdiff4", file=sys.stderr)
    sys.exit(1)

try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
except ImportError:
    print("ERROR: pip install cryptography", file=sys.stderr)
    sys.exit(1)

PACKAGE_NAME = "com.colabdesktoprunner.runner"
# APK signing certificate SHA-256 (public fingerprint, safe to embed)
SIGNING_CERT_SHA256 = "4582a8a121e45c76c590596a2479d8510157734e8c64617ac54b3e9de3a8551a"
MANIFEST_VALID_DAYS = 90


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_private_key() -> Ed25519PrivateKey:
    key_hex = os.environ.get("UPDATE_SIGNING_KEY_HEX", "").strip()
    key_file = os.environ.get("UPDATE_SIGNING_KEY_FILE", "").strip()
    if key_hex:
        raw = bytes.fromhex(key_hex)
    elif key_file and os.path.exists(key_file):
        raw = open(key_file, "rb").read()
    else:
        print("ERROR: set UPDATE_SIGNING_KEY_HEX or UPDATE_SIGNING_KEY_FILE "
              "(never commit the private key)", file=sys.stderr)
        sys.exit(2)
    if len(raw) != 32:
        print("ERROR: private key must be 32 raw bytes", file=sys.stderr)
        sys.exit(2)
    return Ed25519PrivateKey.from_private_bytes(raw)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--new-apk", required=True)
    ap.add_argument("--version-name", required=True)
    ap.add_argument("--version-code", type=int, required=True)
    ap.add_argument("--serial", type=int, required=True,
                    help="monotonically increasing anti-replay serial")
    ap.add_argument("--repo", required=True, help="owner/repo")
    ap.add_argument("--tag", required=True, help="release tag, e.g. v1.1.0")
    ap.add_argument("--channel", default="stable")
    ap.add_argument("--min-supported", type=int, default=1)
    ap.add_argument("--notes-ar", default="")
    ap.add_argument("--old-apk", action="append", default=[],
                    metavar="VERSIONCODE:PATH",
                    help="previous release APK (repeatable, last 3-5 releases)")
    ap.add_argument("--out", default="dist")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    new_bytes = open(args.new_apk, "rb").read()
    new_sha = hashlib.sha256(new_bytes).hexdigest()
    base_url = f"https://github.com/{args.repo}/releases/download/{args.tag}"

    patches = []
    for spec in args.old_apk:
        code_s, path = spec.split(":", 1)
        from_code = int(code_s)
        old_bytes = open(path, "rb").read()
        old_sha = hashlib.sha256(old_bytes).hexdigest()

        print(f"[patch] v{from_code} -> v{args.version_code} ...")
        patch = bsdiff4.diff(old_bytes, new_bytes)

        # MANDATORY verification: apply patch, must reproduce byte-for-byte
        rebuilt = bsdiff4.patch(old_bytes, patch)
        rebuilt_sha = hashlib.sha256(rebuilt).hexdigest()
        if rebuilt != new_bytes or rebuilt_sha != new_sha:
            print(f"FATAL: patch verification FAILED for v{from_code} "
                  f"(rebuilt sha {rebuilt_sha} != {new_sha})", file=sys.stderr)
            return 3
        print(f"  verified byte-for-byte OK "
              f"({len(patch)} bytes = {len(patch)*100//len(new_bytes)}% of full)")

        patch_name = f"patch-v{from_code}-to-v{args.version_code}.bsdiff"
        patch_path = os.path.join(args.out, patch_name)
        open(patch_path, "wb").write(patch)
        patches.append({
            "fromVersionCode": from_code,
            "fromApkSha256": old_sha,
            "toApkSha256": new_sha,
            "url": f"{base_url}/{patch_name}",
            "size": len(patch),
            "patchSha256": hashlib.sha256(patch).hexdigest(),
            "algorithm": "bsdiff40",
        })

    manifest = {
        "packageName": PACKAGE_NAME,
        "serial": args.serial,
        "channel": args.channel,
        "expiresAt": (datetime.now(timezone.utc)
                      + timedelta(days=MANIFEST_VALID_DAYS)
                      ).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "signingCertSha256": SIGNING_CERT_SHA256,
        "latest": {
            "versionName": args.version_name,
            "versionCode": args.version_code,
            "minimumSupportedVersionCode": args.min_supported,
            "notesAr": args.notes_ar,
            "apk": {
                "url": f"{base_url}/app-release.apk",
                "size": len(new_bytes),
                "sha256": new_sha,
            },
        },
        "patches": patches,
    }

    manifest_bytes = json.dumps(
        manifest, ensure_ascii=False, indent=2).encode("utf-8")
    manifest_path = os.path.join(args.out, "latest.json")
    open(manifest_path, "wb").write(manifest_bytes)

    priv = load_private_key()
    sig = priv.sign(manifest_bytes)
    open(os.path.join(args.out, "latest.json.sig"), "w").write(sig.hex())

    # checksums file for the release
    with open(os.path.join(args.out, "SHA256SUMS.txt"), "w") as f:
        f.write(f"{new_sha}  app-release.apk\n")
        for p in patches:
            f.write(f"{p['patchSha256']}  {os.path.basename(p['url'])}\n")
        f.write(f"{hashlib.sha256(manifest_bytes).hexdigest()}  latest.json\n")

    print(f"\nOK: manifest + {len(patches)} verified patch(es) in {args.out}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
