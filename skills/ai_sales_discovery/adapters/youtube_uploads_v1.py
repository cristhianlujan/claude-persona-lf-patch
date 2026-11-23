"""Candidate reader for an authority-bound uploads playlist. No DB writes.

The caller binds the authenticated YouTube service, playlist and window from
the approved source. Each yielded page must be consumed and checkpointed
atomically by the governed runner before advancing.
"""
from dataclasses import dataclass
from datetime import datetime
import re

from .social_convergence_v1 import parse_dt


@dataclass(frozen=True)
class UploadPage:
    videos: tuple
    next_token: str | None
    undated: int


def iter_upload_pages(service, playlist_id, start, end_exclusive, *, page_budget,
                      retries, page_token=None):
    """Yield API pages. Quota exhaustion, invalid metadata or loops interrupt coverage."""
    if not isinstance(playlist_id, str) or not re.fullmatch(r'UU[\w-]{22}', playlist_id, re.ASCII):
        raise ValueError('UPLOADS_PLAYLIST_REQUIRED')
    if not all(isinstance(v, datetime) and v.utcoffset() is not None for v in (start, end_exclusive)) or start >= end_exclusive:
        raise ValueError('WINDOW_INVALID')
    if type(page_budget) is not int or page_budget < 1 or type(retries) is not int or not 0 <= retries <= 3:
        raise ValueError('LIMITS_INVALID')
    seen = set()
    for _ in range(page_budget):
        if page_token is not None and (not isinstance(page_token, str) or not page_token.strip() or page_token in seen):
            raise ValueError('CURSOR_INVALID')
        seen.add(page_token)
        request = service.playlistItems().list(
            part='contentDetails', playlistId=playlist_id, pageToken=page_token,
            maxResults=50, fields='nextPageToken,items(contentDetails(videoId,videoPublishedAt))')
        page = request.execute(num_retries=retries)
        if not isinstance(page, dict) or not isinstance(page.get('items'), list):
            raise ValueError('PAGE_INVALID')
        token = page.get('nextPageToken')
        if 'nextPageToken' in page and (not isinstance(token, str) or not token.strip() or token in seen):
            raise ValueError('CURSOR_INVALID')
        videos = []
        undated = 0
        for item in page['items']:
            details = item.get('contentDetails') if isinstance(item, dict) else None
            if not isinstance(details, dict):
                raise ValueError('ITEM_INVALID')
            published = parse_dt(details.get('videoPublishedAt'))
            if published is None:
                undated += 1
                continue
            video_id = details.get('videoId')
            if not isinstance(video_id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{11}', video_id):
                raise ValueError('VIDEO_ID_INVALID')
            if start <= published < end_exclusive:
                videos.append((video_id, published.isoformat()))
        yield UploadPage(tuple(videos), token, undated)
        if token is None:
            return
        page_token = token
    raise RuntimeError('PAGE_BUDGET_EXHAUSTED')
