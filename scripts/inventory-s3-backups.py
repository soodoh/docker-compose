#!/usr/bin/env python3
"""Inventory encrypted S3 backups without emitting credentials or bucket names."""

from datetime import datetime, timezone
import hashlib
import hmac
import json
import subprocess
import sys
from typing import Any
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

CONTAINER = "weekly-remote-backup"
MATCH_SUFFIX = ".gpg"
S3_NAMESPACE = {"s3": "http://s3.amazonaws.com/doc/2006-03-01/"}


def fail(reason: str) -> None:
    print(f"remote_backup_inventory=failed reason={reason}", file=sys.stderr)
    raise SystemExit(1)


def derive_signing_key(secret: str, date: str, region: str) -> bytes:
    date_key = hmac.new(("AWS4" + secret).encode(), date.encode(), hashlib.sha256).digest()
    region_key = hmac.new(date_key, region.encode(), hashlib.sha256).digest()
    service_key = hmac.new(region_key, b"s3", hashlib.sha256).digest()
    return hmac.new(service_key, b"aws4_request", hashlib.sha256).digest()


def container_environment() -> dict[str, str]:
    try:
        result = subprocess.run(
            ["docker", "inspect", CONTAINER],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        inspected = json.loads(result.stdout)[0]
    except (subprocess.SubprocessError, json.JSONDecodeError, IndexError, KeyError):
        fail("container_inspection_error")
    return {
        item.split("=", 1)[0]: item.split("=", 1)[1]
        for item in inspected["Config"].get("Env", [])
        if "=" in item
    }


def discover_region(bucket: str, default_region: str) -> str:
    url = "https://s3.amazonaws.com/" + urllib.parse.quote(bucket, safe="")
    try:
        with urllib.request.urlopen(urllib.request.Request(url, method="HEAD"), timeout=20) as response:
            return response.headers.get("x-amz-bucket-region") or default_region
    except urllib.error.HTTPError as error:
        return error.headers.get("x-amz-bucket-region") or default_region
    except Exception:
        fail("region_discovery_error")


def signed_get(
    bucket: str,
    region: str,
    access_key: str,
    secret_key: str,
    session_token: str,
    query_values: dict[str, str],
) -> bytes:
    host = "s3.amazonaws.com" if region == "us-east-1" else f"s3.{region}.amazonaws.com"
    canonical_uri = "/" + urllib.parse.quote(bucket, safe="")
    canonical_query = urllib.parse.urlencode(
        sorted(query_values.items()), quote_via=urllib.parse.quote
    )
    now = datetime.now(timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")
    payload_hash = hashlib.sha256(b"").hexdigest()
    headers = {
        "host": host,
        "x-amz-content-sha256": payload_hash,
        "x-amz-date": amz_date,
    }
    if session_token:
        headers["x-amz-security-token"] = session_token

    canonical_headers = "".join(f"{name}:{headers[name]}\n" for name in sorted(headers))
    signed_headers = ";".join(sorted(headers))
    canonical_request = "\n".join(
        [
            "GET",
            canonical_uri,
            canonical_query,
            canonical_headers,
            signed_headers,
            payload_hash,
        ]
    )
    scope = f"{date_stamp}/{region}/s3/aws4_request"
    string_to_sign = "\n".join(
        [
            "AWS4-HMAC-SHA256",
            amz_date,
            scope,
            hashlib.sha256(canonical_request.encode()).hexdigest(),
        ]
    )
    signature = hmac.new(
        derive_signing_key(secret_key, date_stamp, region),
        string_to_sign.encode(),
        hashlib.sha256,
    ).hexdigest()
    authorization = (
        f"AWS4-HMAC-SHA256 Credential={access_key}/{scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )
    request_headers = {name: value for name, value in headers.items() if name != "host"}
    request_headers["Authorization"] = authorization
    url = f"https://{host}{canonical_uri}?{canonical_query}"
    try:
        with urllib.request.urlopen(
            urllib.request.Request(url, headers=request_headers), timeout=60
        ) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        fail(f"s3_http_{error.code}")
    except Exception:
        fail("s3_request_error")


def object_metadata(item: ET.Element) -> dict[str, Any]:
    key = item.findtext("s3:Key", default="", namespaces=S3_NAMESPACE)
    name = key.rsplit("/", 1)[-1]
    return {
        "name": name,
        "key_sha256": hashlib.sha256(key.encode()).hexdigest(),
        "size": int(item.findtext("s3:Size", default="0", namespaces=S3_NAMESPACE)),
        "last_modified": item.findtext(
            "s3:LastModified", default="", namespaces=S3_NAMESPACE
        ),
        "etag": item.findtext("s3:ETag", default="", namespaces=S3_NAMESPACE).strip('"'),
    }


def main() -> None:
    environment = container_environment()
    for name in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_S3_BUCKET_NAME"):
        if not environment.get(name):
            fail(f"missing_{name.lower()}")

    bucket = environment["AWS_S3_BUCKET_NAME"]
    region = discover_region(
        bucket,
        environment.get("AWS_REGION")
        or environment.get("AWS_DEFAULT_REGION")
        or "us-east-1",
    )
    access_key = environment["AWS_ACCESS_KEY_ID"]
    secret_key = environment["AWS_SECRET_ACCESS_KEY"]
    session_token = environment.get("AWS_SESSION_TOKEN", "")

    current_root = ET.fromstring(
        signed_get(
            bucket,
            region,
            access_key,
            secret_key,
            session_token,
            {"list-type": "2", "max-keys": "1000"},
        )
    )
    if current_root.findtext("s3:IsTruncated", default="false", namespaces=S3_NAMESPACE) == "true":
        fail("current_listing_truncated")
    current_objects = [
        object_metadata(item)
        for item in current_root.findall("s3:Contents", S3_NAMESPACE)
        if item.findtext("s3:Key", default="", namespaces=S3_NAMESPACE).endswith(MATCH_SUFFIX)
    ]
    current_objects.sort(key=lambda item: item["last_modified"], reverse=True)

    versions_root = ET.fromstring(
        signed_get(
            bucket,
            region,
            access_key,
            secret_key,
            session_token,
            {"max-keys": "1000", "versions": ""},
        )
    )
    if versions_root.findtext("s3:IsTruncated", default="false", namespaces=S3_NAMESPACE) == "true":
        fail("version_listing_truncated")
    versions = []
    for kind in ("Version", "DeleteMarker"):
        for item in versions_root.findall(f"s3:{kind}", S3_NAMESPACE):
            key = item.findtext("s3:Key", default="", namespaces=S3_NAMESPACE)
            if not key.endswith(MATCH_SUFFIX):
                continue
            metadata = object_metadata(item)
            version_id = item.findtext("s3:VersionId", default="", namespaces=S3_NAMESPACE)
            metadata.update(
                {
                    "kind": kind,
                    "is_latest": item.findtext(
                        "s3:IsLatest", default="false", namespaces=S3_NAMESPACE
                    )
                    == "true",
                    "version_id_sha256": hashlib.sha256(version_id.encode()).hexdigest()
                    if version_id
                    else "",
                }
            )
            versions.append(metadata)
    versions.sort(key=lambda item: item["last_modified"], reverse=True)

    print(
        json.dumps(
            {
                "checked_at": datetime.now(timezone.utc).isoformat(),
                "region": region,
                "total_current_key_count": int(
                    current_root.findtext("s3:KeyCount", default="0", namespaces=S3_NAMESPACE)
                ),
                "encrypted_current_count": len(current_objects),
                "encrypted_current_objects": current_objects,
                "encrypted_version_count": len(versions),
                "encrypted_versions": versions,
            },
            separators=(",", ":"),
        )
    )


if __name__ == "__main__":
    main()
