"""Candidate reader for an official WordPress corporate archive.

The caller owns the HTTP transport and must bind ``base_host`` to identity
evidence for the business.  Only post identifiers, canonical links and
original publication timestamps are returned.  Content and media are not
captured.
"""
from dataclasses import dataclass
from datetime import datetime
import re
from urllib.parse import urlsplit

from .social_convergence_v1 import parse_dt


def _parse_wordpress_gmt(value):
    if value is None:
        return None
    if not isinstance(value, str) or not re.fullmatch(
            r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}', value):
        raise ValueError('PUBLISHED_TIMESTAMP_INVALID')
    return parse_dt(value + 'Z')


@dataclass(frozen=True)
class WordPressPage:
    page_number: int
    total_pages: int
    references: tuple
    seen: int
    in_window: int
    outside_window: int
    undated: int
    source_end: bool


def iter_wordpress_pages(get_page, base_host, start, end_exclusive, *,
                         per_page, page_budget, page_number=1):
    """Yield consecutive archive pages using the authoritative total-pages header.

    ``get_page`` receives ``(page_number, params)`` and returns a mapping with
    integer ``status``, mapping ``headers`` and decoded JSON ``body``.  The
    transport must not follow redirects to another host.
    """
    if not isinstance(base_host, str) or not re.fullmatch(
            r'(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)(?:\.(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?))+',
            base_host):
        raise ValueError('HOST_BINDING_INVALID')
    if not all(isinstance(v, datetime) and v.utcoffset() is not None
               for v in (start, end_exclusive)) or start >= end_exclusive:
        raise ValueError('WINDOW_INVALID')
    if any(type(v) is not int or v < 1 for v in
           (per_page, page_budget, page_number)) or per_page > 100:
        raise ValueError('LIMITS_INVALID')

    first_page = page_number
    expected_total = None
    all_seen_ids = set()
    previous_published = None
    for offset in range(page_budget):
        current = first_page + offset
        params = {
            'page': current,
            'per_page': per_page,
            'orderby': 'date',
            'order': 'desc',
            '_fields': 'id,date_gmt,link,type,status',
        }
        response = get_page(current, params)
        if not isinstance(response, dict) or response.get('status') != 200:
            raise ValueError('PAGE_INVALID')
        headers = response.get('headers')
        rows = response.get('body')
        if not isinstance(headers, dict) or not isinstance(rows, list):
            raise ValueError('PAGE_INVALID')
        raw_total = next((v for k, v in headers.items()
                          if isinstance(k, str) and k.lower() == 'x-wp-totalpages'), None)
        try:
            total_pages = int(raw_total)
        except (TypeError, ValueError) as exc:
            raise ValueError('TOTAL_PAGES_REQUIRED') from exc
        if total_pages < 1 or current > total_pages:
            raise ValueError('TOTAL_PAGES_INVALID')
        if expected_total is None:
            expected_total = total_pages
        elif total_pages != expected_total:
            raise ValueError('ARCHIVE_CHANGED_DURING_RUN')

        refs = []
        outside = 0
        undated = 0
        for row in rows:
            if not isinstance(row, dict) or type(row.get('id')) is not int or row['id'] < 1:
                raise ValueError('ITEM_INVALID')
            if row['id'] in all_seen_ids:
                raise ValueError('DUPLICATE_ID_ACROSS_PAGES')
            all_seen_ids.add(row['id'])
            if row.get('status') != 'publish' or row.get('type') != 'post':
                raise ValueError('ITEM_NOT_PUBLIC_POST')
            link = urlsplit(row.get('link', ''))
            if link.scheme != 'https' or link.hostname != base_host or link.username or link.password:
                raise ValueError('CANONICAL_URL_INVALID')
            published = _parse_wordpress_gmt(row.get('date_gmt'))
            if published is None:
                undated += 1
            else:
                if previous_published is not None and published > previous_published:
                    raise ValueError('CHRONOLOGY_BROKEN')
                previous_published = published
                if start <= published < end_exclusive:
                    refs.append((str(row['id']), link.geturl(), published.isoformat()))
                else:
                    outside += 1

        yield WordPressPage(
            current, total_pages, tuple(refs), len(rows), len(refs), outside,
            undated, current == total_pages)
        if current == total_pages:
            return
    raise RuntimeError('PAGE_BUDGET_EXHAUSTED')
