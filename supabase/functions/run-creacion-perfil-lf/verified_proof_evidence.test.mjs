import test from 'node:test';
import assert from 'node:assert/strict';
import {verifyEvolutionProofRun, PROOF_WORKFLOW_PATH, PROOF_RESOLVER} from './verified_proof_evidence.ts';

const R = 'cristhianlujan/claude-persona-lf-patch';
const SLUG = 'demo_profile';
const BASE = 'a'.repeat(40), CAND = 'b'.repeat(40), ZERO = '0'.repeat(40);
const H = 'c'.repeat(64);

function setup(over = {}) {
  const s = {
    mode: 'compare', cand: CAND,
    run: {}, jobs: [{id: 77, name: 'proof', conclusion: 'success'}], ann: null, env: {}, proof: {}, ...over,
  };
  const mode = s.mode;
  const title = `profile-evolution-proof ${mode} ${SLUG} ${BASE} ${mode === 'compare' ? s.cand : ZERO}`;
  const run = {path: PROOF_WORKFLOW_PATH, event: 'workflow_dispatch', head_branch: 'main', status: 'completed', conclusion: 'success',
    repository: {full_name: R}, head_repository: {full_name: R}, display_title: title, created_at: '2026-10-28T20:00:00Z', ...s.run};
  const proof = mode === 'compare'
    ? {schema: 'S26_PROFILE_EVOLUTION_PROOF_V1', profile_slug: SLUG, verdict: 'EVOLUTION_DEMONSTRATED', improved_dimensions: ['B02'], regressed_dimensions: [], blocking_codes: [], proof_sha256: H, ...s.proof}
    : {schema: 'S26_PROFILE_MEASUREMENT_V1', profile_slug: SLUG, decision: 'UPDATE_REQUIRED', score: 2, required: 13, blocking_codes: [], proof_sha256: H, ...s.proof};
  const envelope = {schema: 'LF_PROFILE_EVOLUTION_PROOF_ANNOTATION_V1', mode, profile_slug: SLUG, base_sha: BASE, candidate_sha: mode === 'compare' ? s.cand : ZERO, proof, ...s.env};
  const ann = s.ann ?? [{title: 'LF_PROFILE_EVOLUTION_PROOF', message: JSON.stringify(envelope)}];
  const gh = async (p) => {
    if (/^\/actions\/runs\/\d+$/.test(p)) return run;
    if (p.endsWith('/jobs')) return {jobs: s.jobs};
    if (p.startsWith('/check-runs/')) return ann;
    throw new Error('UNEXPECTED_' + p);
  };
  return {mode, gh};
}
const call = (st, over = {}) => verifyEvolutionProofRun({repository: R, mode: st.mode, profileSlug: SLUG, baseSha: BASE, candidateSha: CAND, runId: 123, notBefore: '2026-10-28T19:00:00Z', gh: st.gh, now: () => 'T', ...over});

test('compare: accepted and trust context derived', async () => {
  const r = await call(setup());
  assert.equal(r.ok, true);
  assert.equal(r.evidence.server_trust_context.resolver, PROOF_RESOLVER);
  assert.equal(r.evidence.server_trust_context.candidate_sha, CAND);
  assert.equal(r.evidence.proof.verdict, 'EVOLUTION_DEMONSTRATED');
});

test('measure: accepted with zero candidate', async () => {
  const r = await call(setup({mode: 'measure'}), {mode: 'measure', candidateSha: undefined});
  assert.equal(r.ok, true);
  assert.equal(r.evidence.proof.score, 2);
  assert.equal(r.evidence.server_trust_context.candidate_sha, ZERO);
});

test('invalid run id and expectations', async () => {
  for (const runId of ['abc', '', '12;3', null, undefined, '1'.repeat(16)]) assert.deepEqual(await call(setup(), {runId}), {ok: false, code: 'PROOF_RUN_ID_INVALID'});
  assert.deepEqual(await call(setup(), {candidateSha: ZERO}), {ok: false, code: 'PROOF_EXPECTATION_INVALID'});
  assert.deepEqual(await call(setup(), {profileSlug: '../x'}), {ok: false, code: 'PROOF_EXPECTATION_INVALID'});
});

test('run must be the proof workflow, dispatched, from trusted main of this repository', async () => {
  for (const run of [{path: '.github/workflows/other.yml'}, {event: 'push'}]) assert.equal((await call(setup({run}))).code, 'PROOF_RUN_NOT_PROOF_WORKFLOW');
  for (const run of [{head_branch: 'lf/x'}, {repository: {full_name: 'evil/fork'}}, {head_repository: {full_name: 'evil/fork'}}]) assert.equal((await call(setup({run}))).code, 'PROOF_RUN_NOT_TRUSTED_SOURCE');
});

test('run must be completed and successful', async () => {
  for (const run of [{status: 'in_progress'}, {conclusion: 'failure'}, {conclusion: null}]) assert.equal((await call(setup({run}))).code, 'PROOF_RUN_NOT_SUCCESSFUL');
});

test('run title binds mode, slug, base and candidate', async () => {
  assert.equal((await call(setup(), {baseSha: 'd'.repeat(40)})).code, 'PROOF_RUN_INPUTS_MISMATCH');
  assert.equal((await call(setup(), {candidateSha: 'e'.repeat(40)})).code, 'PROOF_RUN_INPUTS_MISMATCH');
  assert.equal((await call(setup(), {profileSlug: 'other_profile'})).code, 'PROOF_RUN_INPUTS_MISMATCH');
  assert.equal((await call(setup({mode: 'measure'}), {mode: 'compare', candidateSha: CAND})).code, 'PROOF_RUN_INPUTS_MISMATCH');
});

test('stale run is rejected', async () => {
  assert.equal((await call(setup(), {notBefore: '2026-10-28T21:00:00Z'})).code, 'PROOF_RUN_STALE');
  assert.equal((await call(setup({run: {created_at: 'garbage'}}))).code, 'PROOF_RUN_STALE');
});

test('job shape must be a single successful proof job', async () => {
  for (const jobs of [[], [{id: 1, name: 'proof', conclusion: 'success'}, {id: 2, name: 'x', conclusion: 'success'}], [{id: 1, name: 'proof', conclusion: 'failure'}], [{id: 1, name: 'other', conclusion: 'success'}]]) {
    assert.equal((await call(setup({jobs}))).code, 'PROOF_JOB_NOT_SUCCESSFUL');
  }
});

test('annotation must exist once, parse and agree with the run', async () => {
  assert.equal((await call(setup({ann: []}))).code, 'PROOF_ANNOTATION_MISSING_OR_AMBIGUOUS');
  const one = {title: 'LF_PROFILE_EVOLUTION_PROOF', message: '{}'};
  assert.equal((await call(setup({ann: [one, one]}))).code, 'PROOF_ANNOTATION_MISSING_OR_AMBIGUOUS');
  assert.equal((await call(setup({ann: [{...one, message: 'not json'}]}))).code, 'PROOF_ANNOTATION_UNPARSEABLE');
  assert.equal((await call(setup({env: {base_sha: 'f'.repeat(40)}}))).code, 'PROOF_ANNOTATION_MISMATCH');
  assert.equal((await call(setup({env: {profile_slug: 'other'}}))).code, 'PROOF_ANNOTATION_MISMATCH');
  assert.equal((await call(setup({proof: {proof_sha256: 'short'}}))).code, 'PROOF_ANNOTATION_MISMATCH');
  assert.equal((await call(setup({proof: {blocking_codes: ['X']}}))).code, 'PROOF_ANNOTATION_MISMATCH');
});

test('compare must demonstrate improvement without regressions', async () => {
  for (const proof of [{verdict: 'NO_DEMONSTRATED_IMPROVEMENT'}, {improved_dimensions: []}, {regressed_dimensions: ['B07']}, {schema: 'OTHER'}]) {
    assert.equal((await call(setup({proof}))).code, 'PROOF_COMPARISON_NOT_DEMONSTRATED');
  }
});

test('measure rejects blocked or malformed measurements', async () => {
  const st = (proof) => setup({mode: 'measure', proof});
  for (const proof of [{decision: 'BLOCKED'}, {score: 'x'}, {schema: 'OTHER'}]) {
    assert.equal((await call(st(proof), {mode: 'measure', candidateSha: undefined})).code, 'PROOF_MEASUREMENT_INVALID');
  }
});

test('reader errors propagate (fail closed)', async () => {
  await assert.rejects(call({mode: 'compare', gh: async () => { throw new Error('GITHUB_RUN_500'); }}), /GITHUB_RUN_500/);
});
