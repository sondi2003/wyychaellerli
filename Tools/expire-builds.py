#!/usr/bin/env python3
"""Macht ältere TestFlight-Builds in App Store Connect ungültig („expired“).

Aufruf (Trockenlauf, ändert nichts):
    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/.appstoreconnect/AuthKey_….p8 \
        python3 Tools/expire-builds.py

Wirklich ausführen:  … python3 Tools/expire-builds.py --apply
Die letzten N Builds behalten (Standard 1):  --keep 2

Der Schlüssel wird einmalig in App Store Connect angelegt (Benutzer und Zugriff →
Integrationen → App Store Connect API → Schlüssel, Rolle „App-Manager“). Die .p8-Datei bleibt
auf diesem Mac, nichts davon gehört ins Repo. Das Skript braucht nur Python 3 und `openssl`
(beides ist auf dem Mac da) und fasst ausschliesslich Builds dieser App an.
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "ch.sondinetwork.wyychaellerli"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """ECDSA-Signatur von DER (openssl) in die 64 Byte r||s, die JWT für ES256 verlangt."""
    assert der[0] == 0x30
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    parts = []
    for _ in range(2):
        assert der[i] == 0x02
        length = der[i + 1]
        value = der[i + 2:i + 2 + length].lstrip(b"\x00")
        parts.append(value.rjust(32, b"\x00"))
        i += 2 + length
    return parts[0] + parts[1]


def make_token(key_id: str, issuer_id: str, key_path: str) -> str:
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "exp": int(time.time()) + 15 * 60, "aud": "appstoreconnect-v1"}
    signing_input = b64url(json.dumps(header, separators=(",", ":")).encode()) + "." + \
        b64url(json.dumps(payload, separators=(",", ":")).encode())
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", os.path.expanduser(key_path)],
        input=signing_input.encode(), capture_output=True, check=True,
    ).stdout
    return signing_input + "." + b64url(der_to_raw(der))


def call(token: str, method: str, path: str, body=None):
    request = urllib.request.Request(
        API + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            text = response.read().decode()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()[:400]
        sys.exit(f"Fehler {error.code} bei {method} {path}: {detail}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true", help="wirklich ungültig machen (sonst nur anzeigen)")
    parser.add_argument("--keep", type=int, default=1, help="so viele neueste Builds behalten (Standard 1)")
    args = parser.parse_args()

    try:
        key_id, issuer_id, key_path = (os.environ[k] for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"))
    except KeyError as missing:
        sys.exit(f"Umgebungsvariable {missing} fehlt (siehe Kopf dieser Datei).")

    token = make_token(key_id, issuer_id, key_path)
    app = call(token, "GET", "/v1/apps?" + urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID}))
    if not app.get("data"):
        sys.exit("App nicht gefunden – stimmt die Bundle-ID?")
    app_id = app["data"][0]["id"]

    query = urllib.parse.urlencode({
        "filter[app]": app_id, "sort": "-uploadedDate", "limit": 200,
        "fields[builds]": "version,uploadedDate,expired,processingState",
    })
    builds = call(token, "GET", "/v1/builds?" + query)["data"]
    valid = [b for b in builds if not b["attributes"].get("expired")]
    old = valid[args.keep:]
    print(f"{len(builds)} Builds, davon {len(valid)} gültig; behalte die neuesten {args.keep}.")
    for b in valid[:args.keep]:
        print(f"  bleibt:  {b['attributes']['version']}")
    for b in old:
        print(f"  {'läuft ab' if args.apply else 'würde ablaufen'}: {b['attributes']['version']}")
        if args.apply:
            call(token, "PATCH", f"/v1/builds/{b['id']}",
                 {"data": {"type": "builds", "id": b["id"], "attributes": {"expired": True}}})
    if old and not args.apply:
        print("Trockenlauf: nichts geändert. Mit --apply ausführen.")


if __name__ == "__main__":
    main()
