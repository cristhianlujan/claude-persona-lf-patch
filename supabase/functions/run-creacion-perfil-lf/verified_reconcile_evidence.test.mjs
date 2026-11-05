import test from 'node:test';
import assert from 'node:assert/strict';
import {verifyPostMergeReconcile} from './verified_reconcile_evidence.ts';

const R = 'cristhianlujan/claude-persona-lf-patch';
const ROOT = 'profiles/demo_profile';
const MERGE = 'a'.repeat(40);
const ENTRY = 'b'.repeat(40);
const MAN = 'c'.repeat(40);
const manifestB64 = (pack = 'PACK_1') => Buffer.from(JSON.stringify({profile_pack_id: pack})).toString('base64');

function reader(over = {}) {
  const s = {
    pr: {merged: true, base: {ref: 'main', repo: {full_name: R}}, merge_commit_sha: MERGE},
    compare: {status: 'ahead'}, entry: {sha: ENTRY},
    manifest: {sha: MAN, encoding: 'base64', content: manifestB64()}, listing: [{name: 'SKILL.md'}, {name: 'manifest.json'}], ...over,
  };
  return async (path) => {
    const pick = (v) => { if (v === null) throw new Error('GITHUB_404'); return v; };
    if (path.startsWith('/pulls/')) return pick(s.pr);
    if (path.startsWith('/compare/')) return pick(s.compare);
    if (path.includes('/SKILL.md?ref=')) return pick(s.entry);
    if (/^\/contents\/[^?]*\?ref=/.test(path) && !path.includes('.')) return pick(s.listing);
    if (path.includes('/manifest.json?ref=')) return pick(s.manifest);
    throw new Error('UNEXPECTED_' + path);
  };
}
const run = (gh, evidence = {merge_sha: MERGE, pr_number: 7}, targetRootPath = ROOT) =>
  verifyPostMergeReconcile({repository: R, targetRootPath, evidence, gh});

test('derives entrypoint, manifest and pack from the merge commit', async () => {
  const r = await run(reader());
  assert.deepEqual(r, {ok: true, args: {merge_sha: MERGE, entrypoint_sha: ENTRY, manifest_sha: MAN, profile_pack_id: 'PACK_1', pr_number: 7}});
});

test('caller-asserted entrypoint/manifest/pack are ignored', async () => {
  const r = await run(reader(), {merge_sha: MERGE, pr_number: 7, entrypoint_sha: 'f'.repeat(40), manifest_sha: 'e'.repeat(40), profile_pack_id: 'FAKE'});
  assert.equal(r.ok, true);
  assert.equal(r.args.entrypoint_sha, ENTRY);
  assert.equal(r.args.profile_pack_id, 'PACK_1');
});

const cases = [
  ['bad merge sha', {merge_sha: 'xyz', pr_number: 7}, {}, 'RECONCILE_MERGE_SHA_INVALID'],
  ['bad pr number', {merge_sha: MERGE, pr_number: 0}, {}, 'RECONCILE_PR_NUMBER_INVALID'],
  ['pr missing', undefined, {pr: null}, 'RECONCILE_PR_NOT_FOUND'],
  ['pr not merged', undefined, {pr: {merged: false, base: {ref: 'main', repo: {full_name: R}}, merge_commit_sha: MERGE}}, 'RECONCILE_PR_NOT_MERGED_INTO_MAIN'],
  ['pr into other branch', undefined, {pr: {merged: true, base: {ref: 'dev', repo: {full_name: R}}, merge_commit_sha: MERGE}}, 'RECONCILE_PR_NOT_MERGED_INTO_MAIN'],
  ['pr other repo', undefined, {pr: {merged: true, base: {ref: 'main', repo: {full_name: 'x/y'}}, merge_commit_sha: MERGE}}, 'RECONCILE_PR_NOT_MERGED_INTO_MAIN'],
  ['merge sha mismatch', undefined, {pr: {merged: true, base: {ref: 'main', repo: {full_name: R}}, merge_commit_sha: 'd'.repeat(40)}}, 'RECONCILE_MERGE_SHA_MISMATCH'],
  ['merge not on main', undefined, {compare: {status: 'diverged'}}, 'RECONCILE_MERGE_NOT_ON_MAIN'],
  ['compare fails', undefined, {compare: null}, 'RECONCILE_MERGE_NOT_ON_MAIN'],
  ['entry missing', undefined, {entry: null}, 'RECONCILE_PROFILE_BLOBS_MISSING'],
  ['manifest missing but listed', undefined, {manifest: null}, 'RECONCILE_PROFILE_BLOBS_MISSING'],
  ['manifest not json', undefined, {manifest: {sha: MAN, encoding: 'base64', content: Buffer.from('nope').toString('base64')}}, 'RECONCILE_MANIFEST_UNPARSEABLE'],
  ['manifest no pack', undefined, {manifest: {sha: MAN, encoding: 'base64', content: Buffer.from('{}').toString('base64')}}, 'RECONCILE_PROFILE_PACK_ID_MISSING'],
];
for (const [name, evidence, over, code] of cases) {
  test(`blocks: ${name}`, async () => {
    const r = await run(reader(over), evidence);
    assert.deepEqual(r, {ok: false, code});
  });
}

const skillB64 = (pack) => Buffer.from(`# X\n\nStatus: CANDIDATE\nProfile Pack ID: ${pack}\n\nMore\n`).toString('base64');
const noManifest = (over = {}) => reader({manifest: null, listing: [{name: 'SKILL.md'}, {name: 'contracts'}], entry: {sha: ENTRY, encoding: 'base64', content: skillB64('PACK_NM')}, ...over});

test('pack without manifest.json: manifest_sha null and pack id from the entrypoint', async () => {
  const r = await run(noManifest());
  assert.deepEqual(r, {ok: true, args: {merge_sha: MERGE, entrypoint_sha: ENTRY, manifest_sha: null, profile_pack_id: 'PACK_NM', pr_number: 7}});
});
test('manifest read failing while the listing still shows manifest.json is blocked (never treated as absent)', async () => {
  const r = await run(noManifest({listing: [{name: 'SKILL.md'}, {name: 'manifest.json'}]}));
  assert.deepEqual(r, {ok: false, code: 'RECONCILE_PROFILE_BLOBS_MISSING'});
});
test('manifest missing and listing unreadable is blocked', async () => {
  assert.deepEqual(await run(noManifest({listing: null})), {ok: false, code: 'RECONCILE_PROFILE_BLOBS_MISSING'});
});
test('no manifest and no Profile Pack ID line in the entrypoint is blocked', async () => {
  const r = await run(noManifest({entry: {sha: ENTRY, encoding: 'base64', content: Buffer.from('# X\nno pack here\n').toString('base64')}}));
  assert.deepEqual(r, {ok: false, code: 'RECONCILE_PROFILE_PACK_ID_MISSING'});
});

test('blocks: invalid target root', async () => {
  assert.deepEqual(await run(reader(), undefined, '../etc'), {ok: false, code: 'RECONCILE_TARGET_ROOT_INVALID'});
});
