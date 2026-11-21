"""Retry-safe acquisition of a pinned HTTPS resource into a private working directory."""
import hashlib
import http.client
import math
import os
import random
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        raise ValueError("REDIRECT_DENIED")


def acquire(url, destination, *, allowed_urls, max_bytes, attempts, socket_timeout,
            deadline_seconds, backoff_seconds, expected_sha=None, opener=None):
    parsed = urlsplit(url)
    if url not in allowed_urls or parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("SOURCE_DENIED")
    if any(type(v) is not int or v <= 0 for v in (max_bytes, attempts)):
        raise ValueError("DOWNLOAD_POLICY")
    if any(type(v) not in (int,float) or not math.isfinite(v) or v <= 0
           for v in (socket_timeout, deadline_seconds, backoff_seconds)):
        raise ValueError("DOWNLOAD_POLICY")
    path = Path(destination)
    opener = opener or urllib.request.build_opener(NoRedirect())
    request = urllib.request.Request(url, headers={"Accept-Encoding":"identity","User-Agent":"AIS30-ingest/1.0"})
    end = time.monotonic() + deadline_seconds

    def remaining():
        left = end - time.monotonic()
        if left <= 0:
            raise TimeoutError("DOWNLOAD_DEADLINE")
        return left

    for attempt in range(1, attempts+1):
        tmp = None
        try:
            with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as out:
                tmp = out.name
                with opener.open(request, timeout=min(remaining(), socket_timeout)) as response:
                    if (response.status != 200 or response.geturl() != url or
                            response.headers.get("Content-Encoding","identity").lower() != "identity"):
                        raise ValueError("HTTP_DENIED")
                    length = response.headers.get("Content-Length")
                    if length is not None and not 0 < int(length) <= max_bytes:
                        raise ValueError("DOWNLOAD_LIMIT")
                    hasher = hashlib.sha256()
                    total = 0
                    while True:
                        remaining()
                        chunk = response.read1(min(1024*1024,max_bytes-total+1))
                        if not chunk:
                            break
                        total += len(chunk)
                        if total > max_bytes:
                            raise ValueError("DOWNLOAD_LIMIT")
                        out.write(chunk)
                        hasher.update(chunk)
                    if total == 0 or (length is not None and total != int(length)):
                        raise http.client.IncompleteRead(b"")
                    digest = hasher.hexdigest()
                    if expected_sha is not None and digest != expected_sha:
                        raise ValueError("SNAPSHOT_CHANGED")
                    modified = response.headers.get("Last-Modified")
            remaining()
            os.link(tmp,path)
            return dict(bytes=total,sha256=digest,http_last_modified=modified,attempts=attempt)
        except (urllib.error.URLError, TimeoutError, ConnectionError, http.client.IncompleteRead) as exc:
            if isinstance(exc,urllib.error.HTTPError) and exc.code not in (408,429,500,502,503,504):
                raise
            if attempt == attempts:
                raise
            time.sleep(min(remaining(),random.uniform(0,backoff_seconds*2**min(attempt-1,12))))
        finally:
            if tmp is not None:
                Path(tmp).unlink(missing_ok=True)
