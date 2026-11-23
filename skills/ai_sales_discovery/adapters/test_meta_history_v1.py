import unittest
from datetime import datetime, timezone
from unittest.mock import Mock
from .meta_history_v1 import iter_meta_pages


class MetaHistory(unittest.TestCase):
    def run_pages(self, source, pages, budget=2):
        self.transport = Mock(side_effect=pages)
        return iter_meta_pages(self.transport, source, '123', datetime(2026,9,22,5,tzinfo=timezone.utc),
                               datetime(2026,11,23,5,tzinfo=timezone.utc), page_size=10, page_budget=budget)

    def test_edges_and_cursor(self):
        for source, edge, field in [('FACEBOOK','posts','created_time'),('INSTAGRAM','media','timestamp')]:
            with self.subTest(source=source):
                pages = self.run_pages(source, [
                    {'data':[{'id':'a',field:'2026-10-01T12:00:00Z'}],
                     'paging':{'next':'https://unused.invalid','cursors':{'after':'opaque'}}},
                    {'data':[{'id':'b'}]}])
                first, last = pages
                self.assertEqual(first.references[0][0], 'a')
                self.assertEqual(last.undated, 1)
                self.transport.assert_called_with('/123/'+edge, {'limit':10,'fields':'id,'+field,'after':'opaque'})
                self.assertIsNone(last.after)

    def test_broken_cursor_and_error_response(self):
        for page, code in [({'data':[],'paging':{'next':'x'}}, 'CURSOR_INVALID'),
                           ({'error':{},'data':[]}, 'PAGE_INVALID')]:
            with self.assertRaisesRegex(ValueError, code):
                list(self.run_pages('FACEBOOK',[page]))

    def test_budget(self):
        pages = self.run_pages('INSTAGRAM',[{'data':[],'paging':{'next':'x','cursors':{'after':'b'}}}],1)
        self.assertEqual(next(pages).after, 'b')
        with self.assertRaisesRegex(RuntimeError, 'PAGE_BUDGET_EXHAUSTED'):
            next(pages)
