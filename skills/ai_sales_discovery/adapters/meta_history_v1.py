"""Candidate Meta Graph page readers for an already authorized managed account.

get_json is the runner's version-pinned authenticated transport. It must bound
response size, timeout, retries and quota. Never follow or retain paging URLs:
they may contain access tokens. Facebook Reels require a separate edge.
"""
from dataclasses import dataclass
import re
from datetime import datetime

from .social_convergence_v1 import parse_dt


EDGES = {
    'FACEBOOK': ('posts', 'created_time'),
    'INSTAGRAM': ('media', 'timestamp'),
}


@dataclass(frozen=True)
class MetaPage:
    references: tuple
    after: str | None
    undated: int


def iter_meta_pages(get_json, source, account_id, start, end_exclusive, *,
                    page_size, page_budget, after=None):
    if source not in EDGES or not isinstance(account_id, str) or not re.fullmatch(r'[0-9]+', account_id):
        raise ValueError('ACCOUNT_BINDING_INVALID')
    if not all(isinstance(v, datetime) and v.utcoffset() is not None for v in (start, end_exclusive)) or start >= end_exclusive:
        raise ValueError('WINDOW_INVALID')
    if any(type(v) is not int or v < 1 for v in (page_size, page_budget)):
        raise ValueError('LIMITS_INVALID')
    edge, date_field = EDGES[source]
    seen = set()
    if after is not None and (not isinstance(after, str) or not after.strip()):
        raise ValueError('CURSOR_INVALID')
    for _ in range(page_budget):
        seen.add(after)
        params = {'limit': page_size, 'fields': 'id,' + date_field}
        if after is not None:
            params['after'] = after
        response = get_json(f'/{account_id}/{edge}', params)
        if not isinstance(response, dict) or 'error' in response or not isinstance(response.get('data'), list):
            raise ValueError('PAGE_INVALID')
        paging = response.get('paging', {})
        if not isinstance(paging, dict):
            raise ValueError('PAGING_INVALID')
        token = None
        if 'next' in paging:
            cursors = paging.get('cursors')
            token = cursors.get('after') if isinstance(cursors, dict) else None
            if not isinstance(paging['next'], str) or not paging['next'] or not isinstance(token, str) or not token.strip() or token in seen:
                raise ValueError('CURSOR_INVALID')
        refs = []
        undated = 0
        for row in response['data']:
            if not isinstance(row, dict) or not isinstance(row.get('id'), str) or not row['id'].strip():
                raise ValueError('ITEM_INVALID')
            published = parse_dt(row.get(date_field))
            if published is None:
                undated += 1
            elif start <= published < end_exclusive:
                refs.append((row['id'], published.isoformat()))
        yield MetaPage(tuple(refs), token, undated)
        if token is None:
            return
        after = token
    raise RuntimeError('PAGE_BUDGET_EXHAUSTED')
