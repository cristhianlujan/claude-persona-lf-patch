import unittest
from datetime import datetime, timezone
from .social_convergence_v1 import CandidateEngine


class RepeatedConfirmation(unittest.TestCase):
    def test_confirming_channel_omits_second_copy(self):
        engine = CandidateEngine(datetime(2026, 1, 1, tzinfo=timezone.utc),
                                 datetime(2027, 1, 1, tzinfo=timezone.utc))
        row = dict(business_key='pilot', event_key='event', claim_key='claim',
                   summary_non_personal='Institutional event', claim_state='REALIZADO',
                   published_at='2026-10-01T12:00:00Z', matching_reviewed=True,
                   company_identity_verified=True)
        def submit(source, host, ref):
            return engine.add(dict(row, source=source, external_ref=ref,
                                   url=f'https://{host}/{ref}'))
        self.assertEqual(submit('YOUTUBE', 'www.youtube.com', 'one'), 'ADMITTED_CANDIDATE')
        self.assertEqual(submit('TIKTOK', 'www.tiktok.com', 'two'), 'CROSS_CHANNEL_DUPLICATE')
        self.assertEqual(submit('TIKTOK', 'www.tiktok.com', 'three'), 'DUPLICATE_WITHIN_CHANNEL')
        self.assertEqual(submit('TIKTOK', 'www.tiktok.com', 'three'), 'SAME_SOURCE_REPLAY')
        self.assertEqual(engine.logs[-2]['original_source_ref'], 'two')
        self.assertEqual(len(engine.concurrency), 1)
        with self.assertRaisesRegex(ValueError, 'SOURCE_HOST_MISMATCH'):
            submit('YOUTUBE', 'example.org', 'four')
