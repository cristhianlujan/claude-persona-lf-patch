import test from 'node:test';
import assert from 'node:assert/strict';
import {verifyGithubWrite, verifyGithubReadback, IDENTITY_FIELDS} from './verified_write_evidence.ts';

const R = 'cristhianlujan/claude-persona-lf-patch';
const ROOT = 'profiles/demo_profile';
const BASE = 'a'.repeat(40);
const HEAD = 'b'.repeat(40);
const BLOB = 'c'.repeat(40);
const BLOB2 = 'd'.repeat(40);
const manifest = (over = {}) => Buffer.from(JSON.stringify({
  profile_pack_id: 'P1', profile_code: 'DEMO', profile_slug: 'demo_profile', document_status: 'CANDIDATO',
  operational_status: 'READ_ONLY', runtime: 'NO_HABILITADO', automatic_impact: 'BLOQUEADO', status: 'CANDIDATE_READ_ONLY',
  runtime_enabled: false, automatic_promotion: false, production_enabled: false, validated_or_vigente: false, ...over,
})).toString('base64');
const notFound = () => { throw new Error('GITHUB_CONTENTS_404'); };

function reader(over = {}) {
  const s = {
    refSha: HEAD,
    compare: {status: 'ahead', ahead_by: 1, behind_by: 0, files: [{filename: `${ROOT}/SKILL.md`, status: 'modified', sha: BLOB}]},
    baseManifest: manifest(), headManifest: manifest(), contentSha: BLOB, ...over,
  };
  return async (path) => {
    if (path.startsWith('/git/ref/heads/')) return {object: {sha: s.refSha}};
    if (path.startsWith('/compare/')) return s.compare;
    if (path.startsWith(`/contents/${ROOT}/manifest.json`)) {
      const b = path.endsWith(`ref=${BASE}`) ? s.baseManifest : s.headManifest;
      if (b === null) return notFound();
      return {encoding: 'base64', content: b};
    }
    if (path.startsWith('/contents/')) return {sha: s.contentSha};
    throw new Error('UNEXPECTED_' + path);
  };
}
const base = (gh, evidence = {branch: 'lf/demo-1', commit_sha: HEAD}) => ({repository: R, targetRootPath: ROOT, boundRevision: BASE, evidence, gh, now: () => 'T'});

test('write: derives files, blob shas and identity from GitHub', async () => {
  const r = await verifyGithubWrite(base(reader()));
  assert.equal(r.ok, true);
  assert.deepEqual(r.evidence.written_files, [{path: `${ROOT}/SKILL.md`, blob_sha: BLOB, status: 'modified'}]);
  assert.equal(r.evidence.identity_preserved, true);
  assert.equal(r.evidence.server_trust_context.resolver, 'GITHUB_PUBLIC_API_EXACT_COMMIT_V1');
  assert.equal(r.evidence.server_trust_context_source, 'run-creacion-perfil-lf');
});

test('write: caller-asserted derived fields are overwritten, never trusted', async () => {
  const r = await verifyGithubWrite(base(reader(), {
    branch: 'lf/demo-1', commit_sha: HEAD, written_files: ['fake'], identity_preserved: false, sha_match: true,
    server_trust_context_valid: false, exact_head: 'x',
  }));
  assert.equal(r.ok, true);
  assert.equal(r.evidence.written_files.length, 1);
  assert.equal(r.evidence.identity_preserved, true);
  assert.equal('sha_match' in r.evidence, false);
  assert.equal(r.evidence.server_trust_context_valid, true);
});

test('write: blocks main, malformed branch and malformed commit', async () => {
  for (const [b, c, code] of [['main', HEAD, 'GITHUB_WRITE_BRANCH_INVALID'], ['feature/x', HEAD, 'GITHUB_WRITE_BRANCH_INVALID'], ['lf/x', 'zz', 'GITHUB_WRITE_COMMIT_SHA_INVALID']]) {
    const r = await verifyGithubWrite(base(reader(), {branch: b, commit_sha: c}));
    assert.deepEqual(r, {ok: false, code});
  }
});

test('write: branch head must equal the declared commit', async () => {
  const r = await verifyGithubWrite(base(reader({refSha: 'e'.repeat(40)})));
  assert.deepEqual(r, {ok: false, code: 'GITHUB_WRITE_BRANCH_HEAD_MISMATCH'});
});

test('write: must descend from the bound revision (stale base blocked)', async () => {
  for (const compare of [{status: 'diverged', ahead_by: 1, behind_by: 2, files: []}, {status: 'ahead', ahead_by: 1, behind_by: 1, files: []}, {status: 'identical', ahead_by: 0, behind_by: 0, files: []}]) {
    const r = await verifyGithubWrite(base(reader({compare})));
    assert.deepEqual(r, {ok: false, code: 'GITHUB_WRITE_NOT_DESCENDANT_OF_BOUND_REVISION'});
  }
});

test('write: any file outside the profile root blocks', async () => {
  for (const filename of ['profiles/other/SKILL.md', '.github/workflows/x.yml', `${ROOT}/../other/a.md`, 'profiles/demo_profile2/a.md']) {
    const compare = {status: 'ahead', ahead_by: 1, behind_by: 0, files: [{filename: `${ROOT}/SKILL.md`, status: 'modified', sha: BLOB}, {filename, status: 'modified', sha: BLOB}]};
    const r = await verifyGithubWrite(base(reader({compare})));
    assert.deepEqual(r, {ok: false, code: 'GITHUB_WRITE_OUT_OF_PROFILE_SCOPE'});
  }
});

test('write: deletes and renames are not allowed; empty and oversized sets are unverifiable', async () => {
  for (const status of ['removed', 'renamed']) {
    const compare = {status: 'ahead', ahead_by: 1, behind_by: 0, files: [{filename: `${ROOT}/a.md`, status, sha: BLOB}]};
    assert.deepEqual(await verifyGithubWrite(base(reader({compare}))), {ok: false, code: 'GITHUB_WRITE_CHANGE_KIND_NOT_ALLOWED'});
  }
  const empty = {status: 'ahead', ahead_by: 1, behind_by: 0, files: []};
  assert.deepEqual(await verifyGithubWrite(base(reader({compare: empty}))), {ok: false, code: 'GITHUB_WRITE_FILE_SET_UNVERIFIABLE'});
  const big = {status: 'ahead', ahead_by: 1, behind_by: 0, files: Array.from({length: 300}, (_, i) => ({filename: `${ROOT}/f${i}.md`, status: 'added', sha: BLOB}))};
  assert.deepEqual(await verifyGithubWrite(base(reader({compare: big}))), {ok: false, code: 'GITHUB_WRITE_FILE_SET_UNVERIFIABLE'});
});

test('write: identity fields changing in manifest.json blocks, each field individually', async () => {
  for (const field of IDENTITY_FIELDS) {
    const r = await verifyGithubWrite(base(reader({headManifest: manifest({[field]: 'CHANGED'})})));
    assert.deepEqual(r, {ok: false, code: 'GITHUB_WRITE_IDENTITY_NOT_PRESERVED'}, field);
  }
  assert.deepEqual(await verifyGithubWrite(base(reader({headManifest: null}))), {ok: false, code: 'GITHUB_WRITE_IDENTITY_NOT_PRESERVED'});
  assert.equal((await verifyGithubWrite(base(reader({baseManifest: null, headManifest: null})))).ok, true);
});

test('write: non-identity manifest edits are allowed', async () => {
  const r = await verifyGithubWrite(base(reader({headManifest: manifest({behavioral_proof_status: 'EXECUTED'})})));
  assert.equal(r.ok, true);
});

async function verifiedWrite(gh = reader()) {
  return (await verifyGithubWrite(base(gh))).evidence;
}

test('readback: derives exact_head, blob shas and sha_match from GitHub', async () => {
  const w = await verifiedWrite();
  const r = await verifyGithubReadback({...base(reader()), evidence: {}, recordedWrite: w});
  assert.equal(r.ok, true);
  assert.equal(r.evidence.exact_head, HEAD);
  assert.equal(r.evidence.sha_match, true);
  assert.deepEqual(r.evidence.readback_files, [{path: `${ROOT}/SKILL.md`, blob_sha: BLOB}]);
});

test('readback: caller sha_match/exact_head are ignored', async () => {
  const w = await verifiedWrite();
  const r = await verifyGithubReadback({...base(reader()), evidence: {sha_match: false, exact_head: 'x'}, recordedWrite: w});
  assert.equal(r.ok, true);
  assert.equal(r.evidence.exact_head, HEAD);
  assert.equal(r.evidence.sha_match, true);
});

test('readback: requires a server-verified write step', async () => {
  for (const recordedWrite of [null, {}, {server_trust_context_valid: true, server_trust_context: {resolver: 'OTHER'}}, {server_trust_context_valid: false}]) {
    const r = await verifyGithubReadback({...base(reader()), evidence: {}, recordedWrite});
    assert.deepEqual(r, {ok: false, code: 'GITHUB_READBACK_VERIFIED_WRITE_REQUIRED'});
  }
});

test('readback: head drift and blob mismatch block', async () => {
  const w = await verifiedWrite();
  assert.deepEqual(await verifyGithubReadback({...base(reader({refSha: 'e'.repeat(40)})), evidence: {}, recordedWrite: w}), {ok: false, code: 'GITHUB_READBACK_HEAD_DRIFT'});
  assert.deepEqual(await verifyGithubReadback({...base(reader({contentSha: BLOB2})), evidence: {}, recordedWrite: w}), {ok: false, code: 'GITHUB_READBACK_SHA_MISMATCH'});
});

test('readback: tampered recorded write outside scope blocks', async () => {
  const w = await verifiedWrite();
  w.written_files = [{path: 'profiles/other/SKILL.md', blob_sha: BLOB, status: 'modified'}];
  assert.deepEqual(await verifyGithubReadback({...base(reader()), evidence: {}, recordedWrite: w}), {ok: false, code: 'GITHUB_READBACK_OUT_OF_PROFILE_SCOPE'});
});

test('reader errors propagate (fail closed, no silent pass)', async () => {
  const gh = async () => { throw new Error('GITHUB_REF_500'); };
  await assert.rejects(verifyGithubWrite(base(gh)), /GITHUB_REF_500/);
});
