import { createHash } from 'node:crypto';

const HEX64 = /^[a-f0-9]{64}$/;
const PACKET_FIELDS = ['status', 'project_code', 'profile_code', 'identity_verified',
  'production_authorized', 'pack_type', 'deliverable_created', 'evidence_map',
  'blocking_codes', 'next_gate'];
const RESULT_FIELDS = ['source_id', 'scope_key', 'source_version', 'capture_sha256',
  'observed_count', 'existing_count', 'unmatched_count', 'effect'];
const ROW_FIELDS = ['fila_origen', 'nombre', 'ruc', 'ubigeo'];
const sha256 = value => createHash('sha256').update(value, 'utf8').digest('hex');
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const exactFields = (value, fields) => object(value) &&
  Object.keys(value).length === fields.length && fields.every(key => Object.hasOwn(value, key));
const boundedCount = n => Number.isSafeInteger(n) && n >= 0;

// Candidate-only semantic judge. The caller MUST resolve authority and policy from
// independent, trusted sources. A JSON assertion of authority cannot grant a role.
export function judgeDetails(packet, context) {
  const reject = code => Object.freeze({status: 'BLOCK_PIPELINE', code, judged_sha256: null});
  if (!exactFields(packet, PACKET_FIELDS)) return reject('RADAR_PACKET_SHAPE');
  if (packet.status !== 'VALID_OUTPUT' || packet.project_code !== 'SALY' ||
      packet.profile_code !== 'PERFIL-RADAR-COMERCIAL-SALY' ||
      packet.identity_verified !== false || packet.production_authorized !== false ||
      packet.pack_type !== 'profile') return reject('RADAR_PROJECT_OR_AUTHORITY');
  const d = packet.deliverable_created;
  if (!exactFields(d, RESULT_FIELDS) || d.effect !== 'READ_ONLY' ||
      typeof d.source_version !== 'string' || !d.source_version.trim() ||
      typeof d.capture_sha256 !== 'string' || !HEX64.test(d.capture_sha256) ||
      ![d.observed_count, d.existing_count, d.unmatched_count].every(boundedCount))
    return reject('RADAR_RESULT_SHAPE');
  if (!Array.isArray(packet.evidence_map) || !packet.evidence_map.length ||
      packet.evidence_map.some(item => typeof item !== 'string' || !item.trim()) ||
      !Array.isArray(packet.blocking_codes) || packet.blocking_codes.length ||
      typeof packet.next_gate !== 'string' || !packet.next_gate.trim())
    return reject('RADAR_EVIDENCE_SHAPE');
  if (!object(context) || !object(context.policy) || !object(context.authority) ||
      typeof context.capture_json !== 'string' || !context.capture_json.length)
    return reject('RADAR_MISSING_INDEPENDENT_CONTEXT');
  const policy = context.policy;
  if (!exactFields(policy, ['schema_version', 'project_code', 'profile_code',
      'source_id', 'scope_key', 'ubigeo_prefixes', 'allowed_effect']) ||
      policy.schema_version !== 'saly-radar-pte-policy/v1' ||
      policy.project_code !== packet.project_code ||
      policy.profile_code !== packet.profile_code ||
      policy.source_id !== d.source_id || policy.scope_key !== d.scope_key ||
      policy.allowed_effect !== 'READ_ONLY' ||
      !Array.isArray(policy.ubigeo_prefixes) || !policy.ubigeo_prefixes.length ||
      policy.ubigeo_prefixes.some(s => typeof s !== 'string' || !/^\d{2}$/.test(s)))
    return reject('RADAR_POLICY_DRIFT');
  const auth = context.authority;
  if (!exactFields(auth, ['source_kind', 'source_ref', 'capture_sha256',
      'stored_count', 'matching_count', 'query_ref']) ||
      auth.source_kind !== 'SUPABASE_READBACK' ||
      typeof auth.source_ref !== 'string' || !auth.source_ref.trim() ||
      typeof auth.query_ref !== 'string' || !auth.query_ref.trim() ||
      typeof auth.capture_sha256 !== 'string' || !HEX64.test(auth.capture_sha256) ||
      !boundedCount(auth.stored_count) || !boundedCount(auth.matching_count) ||
      auth.matching_count > auth.stored_count)
    return reject('RADAR_AUTHORITY_RECEIPT_SHAPE');
  let rows;
  try { rows = JSON.parse(context.capture_json); }
  catch { return reject('RADAR_CAPTURE_PARSE'); }
  if (!Array.isArray(rows) || !rows.length || rows.some(row =>
      !exactFields(row, ROW_FIELDS) || !Number.isSafeInteger(row.fila_origen) ||
      row.fila_origen <= 0 || typeof row.nombre !== 'string' || !row.nombre.trim() ||
      !(row.ruc === null || typeof row.ruc === 'string') ||
      typeof row.ubigeo !== 'string' || !/^\d{6}$/.test(row.ubigeo) ||
      !policy.ubigeo_prefixes.some(prefix => row.ubigeo.startsWith(prefix))))
    return reject('RADAR_CAPTURE_ROW_CONTRACT');
  if (new Set(rows.map(row => row.fila_origen)).size !== rows.length)
    return reject('RADAR_DUPLICATE_SOURCE_ORDINAL');
  const computed = sha256(context.capture_json);
  if (computed !== d.capture_sha256) return reject('RADAR_CAPTURE_HASH_MISMATCH');
  if (auth.capture_sha256 !== computed) return reject('RADAR_STORED_HASH_MISMATCH');
  if (rows.length !== d.observed_count || d.existing_count !== auth.stored_count ||
      d.unmatched_count !== rows.length - auth.matching_count ||
      auth.matching_count > rows.length)
    return reject('RADAR_COUNT_READBACK_MISMATCH');
  // The hash covers exactly the packet and independent evidence reviewed.
  // No caller-supplied precomputed verdict is trusted. Nothing is mutated.
  const judged_sha256 = sha256(JSON.stringify({packet, capture_sha256: computed,
    source_ref: auth.source_ref, query_ref: auth.query_ref, policy}));
  return Object.freeze({status: 'VALID_OUTPUT', code: 'RADAR_SEMANTIC_READ_ONLY_PASS',
    judged_sha256, capture_sha256: computed});
}
export function judge(packet, context) { return judgeDetails(packet, context).status; }

/* A2: revalidate the hash against CURRENT content at the point of use. */
export function verifyJudgedHash(verdict, packet, context) {
  if (!exactFields(verdict, ['status','code','judged_sha256','capture_sha256'])) return false;
  if (verdict.status !== 'VALID_OUTPUT' || verdict.code !== 'RADAR_SEMANTIC_READ_ONLY_PASS' ||
      typeof verdict.judged_sha256 !== 'string' || !HEX64.test(verdict.judged_sha256)) return false;
  const current = judgeDetails(packet, context);
  return current.status === 'VALID_OUTPUT' &&
    current.judged_sha256 === verdict.judged_sha256 &&
    current.capture_sha256 === verdict.capture_sha256;
}
