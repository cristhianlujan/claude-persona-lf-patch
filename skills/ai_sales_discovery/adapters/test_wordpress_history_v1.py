import unittest
from datetime import datetime, timezone
from unittest.mock import Mock

from .wordpress_history_v1 import iter_wordpress_pages


class WordPressHistory(unittest.TestCase):
    start = datetime(2026, 9, 22, 5, tzinfo=timezone.utc)
    end = datetime(2026, 11, 23, 5, tzinfo=timezone.utc)

    @staticmethod
    def row(identifier, date='2026-10-01T12:00:00'):
        return {'id': identifier, 'date_gmt': date, 'status': 'publish',
                'type': 'post',
                'link': f'https://www.example.edu.pe/post-{identifier}/'}

    def pages(self, responses, *, budget=3, page=1):
        transport = Mock(side_effect=responses)
        iterator = iter_wordpress_pages(
            transport, 'www.example.edu.pe', self.start, self.end,
            per_page=5, page_budget=budget, page_number=page)
        return transport, iterator

    def test_consecutive_pages_and_source_end(self):
        headers = {'X-WP-TotalPages': '2'}
        transport, pages = self.pages([
            {'status': 200, 'headers': headers,
             'body': [self.row(2), self.row(1, '2024-01-01T00:00:00')]},
            {'status': 200, 'headers': headers,
             'body': [self.row(3, '2023-01-01T00:00:00')]},
        ])
        first, last = pages
        self.assertEqual((first.page_number, first.in_window, first.outside_window),
                         (1, 1, 1))
        self.assertEqual((last.page_number, last.total_pages, last.source_end),
                         (2, 2, True))
        self.assertEqual(transport.call_args.args[0], 2)
        self.assertEqual(transport.call_args.args[1]['page'], 2)

    def test_resume_and_budget_preserves_next_page(self):
        response = {'status': 200, 'headers': {'x-wp-totalpages': '3'}, 'body': []}
        _, pages = self.pages([response], budget=1, page=2)
        self.assertEqual(next(pages).page_number, 2)
        with self.assertRaisesRegex(RuntimeError, 'PAGE_BUDGET_EXHAUSTED'):
            next(pages)

    def test_archive_mutation_and_wrong_host_are_blocked(self):
        _, pages = self.pages([
            {'status': 200, 'headers': {'X-WP-TotalPages': '2'}, 'body': []},
            {'status': 200, 'headers': {'X-WP-TotalPages': '3'}, 'body': []},
        ])
        with self.assertRaisesRegex(ValueError, 'ARCHIVE_CHANGED_DURING_RUN'):
            list(pages)
        bad = self.row(1)
        bad['link'] = 'https://example.org/post-1/'
        _, pages = self.pages([
            {'status': 200, 'headers': {'X-WP-TotalPages': '1'}, 'body': [bad]}
        ])
        with self.assertRaisesRegex(ValueError, 'CANONICAL_URL_INVALID'):
            list(pages)

    def test_missing_total_pages_and_http_error_are_not_source_end(self):
        for response, error in [
            ({'status': 200, 'headers': {}, 'body': []}, 'TOTAL_PAGES_REQUIRED'),
            ({'status': 400, 'headers': {}, 'body': {}}, 'PAGE_INVALID'),
        ]:
            with self.subTest(error=error):
                _, pages = self.pages([response])
                with self.assertRaisesRegex(ValueError, error):
                    list(pages)

    def test_cross_page_duplicate_and_broken_chronology_are_blocked(self):
        headers = {'X-WP-TotalPages': '2'}
        cases = [
            ([self.row(1, '2024-01-01T00:00:00')],
             [self.row(1, '2023-01-01T00:00:00')],
             'DUPLICATE_ID_ACROSS_PAGES'),
            ([self.row(1, '2024-01-01T00:00:00')],
             [self.row(2, '2025-01-01T00:00:00')],
             'CHRONOLOGY_BROKEN'),
        ]
        for first, second, error in cases:
            with self.subTest(error=error):
                _, pages = self.pages([
                    {'status': 200, 'headers': headers, 'body': first},
                    {'status': 200, 'headers': headers, 'body': second},
                ])
                with self.assertRaisesRegex(ValueError, error):
                    list(pages)
