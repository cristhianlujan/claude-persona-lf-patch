import unittest
from datetime import datetime, timezone
from unittest.mock import MagicMock
from .youtube_uploads_v1 import iter_upload_pages


class UploadPages(unittest.TestCase):
    def pages(self, responses, budget=3):
        self.service = MagicMock()
        self.call = self.service.playlistItems.return_value.list
        self.call.return_value.execute.side_effect = responses
        return iter_upload_pages(self.service, 'UU' + 'a'*22,
                                 datetime(2026, 9, 22, 5, tzinfo=timezone.utc),
                                 datetime(2026, 11, 23, 5, tzinfo=timezone.utc),
                                 page_budget=budget, retries=1)

    def test_pages_and_original_dates(self):
        def item(date):
            return {'contentDetails': {'videoId':'12345678901','videoPublishedAt':date}}
        first, last = self.pages([{'nextPageToken':'x', 'items': [item(None), item('2026-09-22T05:00:00Z')]},
                                  {'items':[item('2026-11-23T05:00:00Z')]}])
        self.assertEqual((len(first.videos), first.undated, last.videos), (1, 1, ()))
        self.assertEqual(self.call.call_args.kwargs['pageToken'], 'x')
        self.assertIsNone(last.next_token)

    def test_limit_keeps_checkpoint(self):
        pages = self.pages([{'items': [], 'nextPageToken':'x'}], budget=1)
        self.assertEqual(next(pages).next_token, 'x')
        with self.assertRaisesRegex(RuntimeError, 'PAGE_BUDGET_EXHAUSTED'):
            next(pages)

    def test_loop_and_missing_items(self):
        with self.assertRaisesRegex(ValueError, 'CURSOR_INVALID'):
            list(self.pages([{'items':[], 'nextPageToken':'x'}]*2))
        with self.assertRaisesRegex(ValueError, 'PAGE_INVALID'):
            list(self.pages([{}]))
