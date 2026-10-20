"""Exercise proposed workflow Bash with real Git, offline ledger and fake gh."""
from __future__ import annotations
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lf_migration_reconcile_lane as lane

ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path(os.environ.get('LF_RECONCILE_WORKFLOW_SOURCE', ROOT / '.github/workflows/lf-migration-reconcile-lane.yml'))
STEPS = yaml.safe_load(SOURCE.read_text())['jobs']['reconcile-source-only']['steps']


def step(name):
    return next(s for s in STEPS if s.get('name') == name)


class ReconcileWorkflowSync(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.remote = self.root / 'remote.git'
        self.repo = self.root / 'reconcile-head'
        subprocess.run(['git', 'init', '--bare', '-q', str(self.remote)], check=True)
        subprocess.run(['git', 'init', '-q', str(self.repo)], check=True)
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('remote', 'add', 'origin', str(self.remote))
        self.old = 'supabase/migrations/20261014105900_legacy_filename.sql'
        self.new = 'supabase/migrations/20261014110000_ig_m8_2_per_family_resolver_hook_v1.sql'
        self.sql = 'select 1;\n'
        path = self.repo / self.old
        path.parent.mkdir(parents=True)
        path.write_text(self.sql)
        (self.repo / 'shared.txt').write_text('base\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'base')
        self.base = self.git('rev-parse', 'HEAD')
        self.git('branch', '-M', 'main')
        self.git('push', '-q', 'origin', 'main')
        self.git('checkout', '-qb', 'lf/test')
        self.git('mv', self.old, self.new)
        self.git('commit', '-qm', 'one exact rename')
        self.head = self.git('rev-parse', 'HEAD')
        self.git('push', '-q', 'origin', 'lf/test')
        self.output = self.root / 'outputs'
        self.calls = self.root / 'gh-calls'
        binpath = self.root / 'bin'
        binpath.mkdir()
        gh = binpath / 'gh'
        gh.write_text('''#!/usr/bin/env python3
import json, os, subprocess, sys
with open(os.environ['GH_CALLS'], 'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
if '--method' in sys.argv:
    print('{}')
else:
    print(subprocess.check_output(['git','--git-dir',os.environ['TEST_REMOTE'],'rev-parse','refs/heads/lf/test'],text=True).strip())
''')
        gh.chmod(0o755)
        self.env = dict(os.environ, PATH=str(binpath)+os.pathsep+os.environ['PATH'],
                        GH_TOKEN='offline-test-only', REPO='test/repo', PR='1',
                        HEAD_REF='lf/test', EXPECTED_HEAD=self.head,
                        GITHUB_OUTPUT=str(self.output), RUNNER_TEMP=str(self.root),
                        GITHUB_RUN_ID='offline', GH_CALLS=str(self.calls),
                        TEST_REMOTE=str(self.remote))

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args],
                                       text=True, stderr=subprocess.DEVNULL).strip()

    def advance_main(self, conflict=False):
        if conflict:
            (self.repo / 'shared.txt').write_text('PR\n')
            self.git('add', '.')
            self.git('commit', '-qm', 'PR shared change')
            self.head = self.git('rev-parse', 'HEAD')
            self.git('push', '-q', 'origin', 'lf/test')
            self.env['EXPECTED_HEAD'] = self.head
        self.git('checkout', '-q', 'main')
        (self.repo / 'shared.txt').write_text('main\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'advance main')
        main = self.git('rev-parse', 'HEAD')
        self.git('push', '-q', 'origin', 'main')
        self.git('checkout', '-q', '--detach', self.head)
        return main

    def run_sync(self, main):
        self.env['CURRENT_MAIN'] = main
        return subprocess.run(['bash', '-c', step('Sync exact PR head with current main')['run']],
                              cwd=self.root, env=self.env, text=True, capture_output=True)

    def test_behind_branch_sync_checkout_and_verify_exact_rename(self):
        main = self.advance_main()
        fixture = self.root / 'ledger.json'
        fixture.write_text(json.dumps({
            'schema_version': 'lf-migration-reconcile-ledger-snapshot/v1',
            'rows': [{'version': '20261014110000',
                      'name': 'ig_m8_2_per_family_resolver_hook_v1',
                      'statements': [self.sql]}],
        }))
        ledger = lane._load_ledger_json(fixture)
        before_rc, before_receipt = lane.verify(
            repo=self.repo, repo_label='test/repo', pr=1,
            base_sha=main, head_sha=self.head, ledger_entries=ledger)
        self.assertEqual(before_rc, lane.FAIL)
        self.assertEqual(before_receipt['reason'], 'HEAD_DOES_NOT_CONTAIN_MAIN')
        result = self.run_sync(main)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        synced = self.output.read_text().strip().split('head_sha=')[1]
        self.assertNotEqual(synced, self.head)
        self.assertEqual(self.git('show', '-s', '--format=%P', synced), f'{self.head} {main}')
        self.assertEqual(self.git('show', '-s', '--format=%s', synced),
                         'chore(reconcile): sync source-only lane with main')
        self.env['HEAD_SHA'] = synced
        checkout = subprocess.run(['bash', '-c', step('Re-fetch and checkout synced PR head')['run']],
                                  cwd=self.root, env=self.env, text=True, capture_output=True)
        self.assertEqual(checkout.returncode, 0, checkout.stdout + checkout.stderr)
        self.assertEqual(self.git('rev-parse', 'HEAD'), synced)
        changes = lane._parse_diff(self.repo, main, synced)
        self.assertEqual(changes, [lane.Change('R', self.new, self.old)])
        rc, receipt = lane.verify(
            repo=self.repo, repo_label='test/repo', pr=1,
            base_sha=main, head_sha=synced, ledger_entries=ledger)
        self.assertEqual(rc, lane.PASS, receipt)
        self.assertEqual(receipt['verdict'], 'PASS')
        self.assertEqual({row['path']: row['verdict'] for row in receipt['files']}, {
            self.old: 'PASS_PAIRED_SOURCE_NOT_LEDGER', self.new: 'PASS_LEDGER_EXACT',
        })
        self.assertEqual(self.git('show', f'{synced}:shared.txt'), 'main')
        self.assertNotIn('x-access-token', self.git('config', '--local', '--list'))

    def test_conflict_exits_two_comments_and_never_pushes_or_merges(self):
        main = self.advance_main(conflict=True)
        result = self.run_sync(main)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn('FAIL_RECONCILE_SYNC_CONFLICT', result.stdout)
        observed = subprocess.check_output(['git', '--git-dir', str(self.remote),
                                           'rev-parse', 'refs/heads/lf/test'], text=True).strip()
        self.assertEqual(observed, self.head)
        self.assertFalse(self.output.exists())
        calls = [json.loads(row) for row in self.calls.read_text().splitlines()]
        self.assertEqual(len(calls), 1)
        self.assertIn('repos/test/repo/issues/1/comments', calls[0])
        self.assertFalse(any('/merge' in arg for row in calls for arg in row))

    def test_current_branch_is_noop(self):
        result = self.run_sync(self.base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.output.read_text().strip(), f'head_sha={self.head}')
        self.assertFalse(self.calls.exists())

    def test_trusted_guard_and_head_contract(self):
        names = [s['name'] for s in STEPS]
        self.assertLess(names.index('Sync exact PR head with current main'),
                        names.index('Wait required pre-apply checks on synced head'))
        self.assertLess(names.index('Wait required pre-apply checks on synced head'),
                        names.index('Verify exact source against read-only ledger'))
        guard = step('Wait required pre-apply checks on synced head')['run']
        self.assertIn('python3 trusted/sandbox/', guard)
        self.assertIn('--checks-file trusted/sandbox/', guard)
        self.assertIn('seq 1 90', guard)
        self.assertIn('guard_args+=(--final)', guard)
        self.assertIn('sleep 5', guard)
        self.assertIn('FAIL_RECONCILE_REQUIRED_CHECK_TIMEOUT', guard)
        for name in ('Verify exact source against read-only ledger',
                     'Publish verified status and merge exact head'):
            self.assertEqual(step(name)['env']['HEAD_SHA'], '${{ steps.sync.outputs.head_sha }}')
        self.assertEqual(yaml.safe_load(SOURCE.read_text())['jobs']['reconcile-source-only']['timeout-minutes'], 40)
        sync = step('Sync exact PR head with current main')['run']
        self.assertNotIn('remote set-url', sync)
        self.assertIn('--force-with-lease="refs/heads/$HEAD_REF:$EXPECTED_HEAD"', sync)
        for name in ('Sync exact PR head with current main',
                     'Re-fetch and checkout synced PR head',
                     'Wait required pre-apply checks on synced head'):
            self.assertEqual(step(name)['if'], "steps.preflight.outputs.conflict != 'true'")
            self.assertIn('set -euo pipefail', step(name)['run'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
