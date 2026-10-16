/* IG M10.7 — data-only snapshot reader, candidate; not deployed or wired.
 * loadTrustedSnapshot must be implemented only by a trusted internal provider,
 * never from an HTTP request body or caller-provided data.
 */
export class SnapshotInvalidError extends Error {
  constructor(code) { super(code); this.name = 'SnapshotInvalidError'; this.code = code; }
}
const roles = Object.freeze({INPUT_CURATOR:'CURATING', INPUT_VALIDATOR:'VALIDATING'});
export function canonicalJSON(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(',')}]`;
  const keys = Object.keys(value).sort();
  return `{${keys.map(k=>`${JSON.stringify(k)}:${canonicalJSON(value[k])}`).join(',')}}`;
}
export async function sha256Hex(value) {
  const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(canonicalJSON(value)));
  return Array.from(new Uint8Array(hash), x=>x.toString(16).padStart(2,'0')).join('');
}
function deepFreeze(v) {
  if (v && typeof v === 'object' && !Object.isFrozen(v)) {
    for (const child of Object.values(v)) deepFreeze(child);
    Object.freeze(v);
  }
  return v;
}
/**
 * Bind a snapshot only for the exact consumer and lifecycle stage.
 * Inapplicable/missing/metadata-only V1 => existing canonical path.
 * An invalid or cross-run full V2 => FAIL_CLOSED, never silent fallback.
 */
export async function selectSnapshotReadV1({ consumer, run, loadTrustedSnapshot }) {
  if (!(consumer in roles)) throw new SnapshotInvalidError('IG_SNAPSHOT_CONSUMER_NOT_ALLOWED');
  if (!run || !Number.isSafeInteger(run.run_id) || run.run_id <= 0 ||
      !Number.isSafeInteger(run.pantalla_id) || run.pantalla_id <= 0 ||
      !Number.isSafeInteger(run.version_id) || run.version_id <= 0) {
    throw new SnapshotInvalidError('IG_SNAPSHOT_RUN_IDENTITY_INVALID');
  }
  if (run.status !== roles[consumer]) {
    return { mode:'CANONICAL_CURRENT', reason:'STAGE_NOT_APPLICABLE', data:null };
  }
  if (typeof loadTrustedSnapshot !== 'function') {
    return { mode:'CANONICAL_CURRENT', reason:'PROVIDER_NOT_CONNECTED', data:null };
  }
  const packet = await loadTrustedSnapshot();
  if (packet == null) {
    return { mode:'CANONICAL_CURRENT', reason:'NO_SNAPSHOT_AVAILABLE', data:null };
  }
  // G1 currently provides references only. Never treat them as complete inputs.
  if (packet.schema_version === 'IG_EXECUTION_SOURCE_CONTEXT_V1' &&
      packet.reuse_scope === 'RUN_PINNED_FIELDS_ONLY') {
    return { mode:'CANONICAL_CURRENT', reason:'G1_REFERENCE_ONLY', data:null };
  }
  if (packet.schema_version !== 'IG_EXECUTION_SOURCE_CONTEXT_V2' ||
      packet.purpose !== 'READ_ONLY_DATA_PACKET' ||
      packet.reuse_scope !== 'RUN_IMMUTABLE_COMPLETE' ||
      packet.consumer_stage !== roles[consumer]) {
    throw new SnapshotInvalidError('IG_SNAPSHOT_CONTRACT_UNRECOGNIZED');
  }
  for (const k of ['run_id','pantalla_id','version_id','contract_snapshot_sha256','source_snapshot_sha256']) {
    if (packet[k] !== run[k]) throw new SnapshotInvalidError(`IG_SNAPSHOT_IDENTITY_MISMATCH_${k.toUpperCase()}`);
  }
  if (consumer==='INPUT_VALIDATOR' && (!run.curator_identity || !run.validator_identity ||
      run.curator_identity === run.validator_identity ||
      packet.validator_identity !== run.validator_identity)) {
    throw new SnapshotInvalidError('IG_SNAPSHOT_VALIDATOR_INDEPENDENCE_MISSING');
  }
  const data = packet.data;
  if (!data || typeof data !== 'object' || Array.isArray(data) ||
      !Array.isArray(data.rules) || !Array.isArray(data.contracts) ||
      !Array.isArray(data.families) || data.graph == null ||
      typeof data.graph !== 'object' ||
      !/^[0-9a-f]{64}$/.test(packet.data_sha256 ?? '')) {
    throw new SnapshotInvalidError('IG_SNAPSHOT_DATA_INCOMPLETE');
  }
  if (await sha256Hex(data) !== packet.data_sha256) {
    throw new SnapshotInvalidError('IG_SNAPSHOT_DATA_TAMPERED');
  }
  return {mode:'SHARED_SNAPSHOT', reason:'ADMITTED_COMPLETE', data:deepFreeze(structuredClone(data))};
}
