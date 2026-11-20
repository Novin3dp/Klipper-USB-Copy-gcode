#!/usr/bin/env python3
"""Offline-friendly Moonraker HTTP client for Novin3dp USB G-code Copy.

Uses only Python's standard library. Uploads are streamed in chunks, so large
G-code files do not need to be loaded into RAM.
"""
import http.client
import json
import os
import secrets
import sys
from urllib.parse import quote, urlencode, urlsplit


CHUNK_SIZE = 1024 * 1024
DEFAULT_URL = "http://127.0.0.1:7125"


def connection_for(base_url, timeout):
    parsed = urlsplit(base_url)
    if parsed.scheme != "http" or not parsed.hostname:
        raise ValueError("Only a local http:// Moonraker URL is supported")
    if parsed.path not in ("", "/"):
        raise ValueError("Moonraker base URL must not contain a path")
    return http.client.HTTPConnection(parsed.hostname, parsed.port or 80, timeout=timeout)


def request_state(base_url):
    conn = connection_for(base_url, 8)
    try:
        conn.request("GET", "/printer/objects/query?print_stats")
        response = conn.getresponse()
        payload = response.read()
        if response.status != 200:
            return "unknown"
        data = json.loads(payload.decode("utf-8", "replace"))
        state = data.get("result", {}).get("status", {}).get("print_stats", {}).get("state")
        return state if isinstance(state, str) else "unknown"
    finally:
        conn.close()


def send_gcode(base_url, script):
    conn = connection_for(base_url, 10)
    try:
        target = "/printer/gcode/script?" + urlencode({"script": script})
        conn.request("POST", target, body=b"", headers={"Content-Length": "0"})
        response = conn.getresponse()
        body = response.read()
        print(response.status)
        if response.status != 200 and body:
            print(body.decode("utf-8", "replace"), file=sys.stderr)
        return 0 if response.status == 200 else 1
    finally:
        conn.close()


def write_response(path, body):
    if path:
        try:
            with open(path, "wb") as output:
                output.write(body)
        except OSError:
            pass


def upload_file(base_url, moonraker_path, filename, response_path):
    conn = None
    try:
        if not os.path.isfile(filename):
            raise FileNotFoundError(filename)

        boundary = "----Novin3dpUSB" + secrets.token_hex(16)
        basename = os.path.basename(filename)
        safe_ascii = basename.encode("ascii", "ignore").decode("ascii")
        safe_ascii = safe_ascii.replace('"', "_").replace("\\", "_").replace("\r", "_").replace("\n", "_")
        if not safe_ascii:
            safe_ascii = "upload.gcode"
        encoded_name = quote(basename, safe="")
        fields = (("root", "gcodes"), ("path", moonraker_path))

        prefix = bytearray()
        for field_name, value in fields:
            prefix.extend(("--" + boundary + "\r\n").encode("ascii"))
            prefix.extend(('Content-Disposition: form-data; name="' + field_name + '"\r\n\r\n').encode("ascii"))
            prefix.extend(value.encode("utf-8"))
            prefix.extend(b"\r\n")

        prefix.extend(("--" + boundary + "\r\n").encode("ascii"))
        disposition = (
            'Content-Disposition: form-data; name="file"; filename="' + safe_ascii +
            '"; filename*=UTF-8\'\'' + encoded_name + "\r\n"
        )
        prefix.extend(disposition.encode("ascii"))
        prefix.extend(b"Content-Type: application/octet-stream\r\n\r\n")
        suffix = ("\r\n--" + boundary + "--\r\n").encode("ascii")

        file_size = os.path.getsize(filename)
        content_length = len(prefix) + file_size + len(suffix)
        conn = connection_for(base_url, 900)
        conn.putrequest("POST", "/server/files/upload")
        conn.putheader("Content-Type", "multipart/form-data; boundary=" + boundary)
        conn.putheader("Content-Length", str(content_length))
        conn.putheader("Connection", "close")
        conn.endheaders()
        conn.send(prefix)

        with open(filename, "rb") as source:
            while True:
                chunk = source.read(CHUNK_SIZE)
                if not chunk:
                    break
                conn.send(chunk)

        conn.send(suffix)
        response = conn.getresponse()
        body = response.read()
        write_response(response_path, body)
        print(response.status)
        return 0 if response.status in (200, 201) else 1

    except Exception as exc:
        write_response(response_path, str(exc).encode("utf-8", "replace"))
        print("000")
        return 1
    finally:
        if conn is not None:
            conn.close()


def main(argv):
    if len(argv) < 3:
        print("Usage: usb-gcode-copy-http.py state|gcode|upload MOONRAKER_URL ...", file=sys.stderr)
        return 2

    command, base_url = argv[1], argv[2]
    try:
        if command == "state":
            print(request_state(base_url))
            return 0
        if command == "gcode" and len(argv) == 4:
            return send_gcode(base_url, argv[3])
        if command == "upload" and len(argv) == 6:
            return upload_file(base_url, argv[3], argv[4], argv[5])
        print("Invalid command arguments", file=sys.stderr)
        return 2
    except Exception as exc:
        if command == "state":
            print("unknown")
            return 0
        print("000")
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
