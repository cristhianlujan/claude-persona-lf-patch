/* IG M10.7 — selective data-only reader. CANDIDATE ONLY, not deployed or wired.
 * loadTrustedSnapshot comes ONLY from a trusted backend, never from HTTP input.
 * Bind once per execution, verify once, then request only required variables.
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

const sections = Object.freeze(['rules','contracts','families','graph']);
const own = (object, key) => Object.prototype.hasOwnProperty.call(object,key);
function indexBy(records, fields, section) {
  if (!Array.isArray(records))
    throw new SnapshotInvalidError('IG_SNAPSHOT_' + section + '_INVALID');
  const index = new Map();
  for (const item of records) {
    if (!item || typeof item !== 'object' || Array.isArray(item))
      throw new SnapshotInvalidError('IG_SNAPSHOT_' + section + '_INVALID');
    const id = fields.map(key => item[key]).find(value => typeof value === 'string' || Number.isSafeInteger(value));
    if (id === undefined || index.has(String(id)))
      throw new SnapshotInvalidError('IG_SNAPSHOT_' + section + '_IDENTITY_INVALID');
    index.set(String(id),item);
  }
  return index;
}
function graphPath(graph,path) {
  if (typeof path !== 'string' || path.length > 512 || !path)
    throw new SnapshotInvalidError('IG_SNAPSHOT_GRAPH_PATH_INVALID');
  let node=graph;
  for (const key of path.split('.')) {
    if (!key || ['__proto__','prototype','constructor'].includes(key) ||
        node === null || typeof node !== 'object' || !own(node,key))
      throw new SnapshotInvalidError('IG_SNAPSHOT_GRAPH_FIELD_MISSING');
    node=node[key];
  }
  return node;
}
/** Bind once to a trusted, SHA-verified, run-pinned snapshot.
 * read(selection) returns only named rules/contracts/families/graph fields.
 * No full clone, repeated hash or database access per read.
 * Missing/unavailable provider or wrong stage => canonical path.
 * Altered V2 or missing requested source => fail closed.
 */
export async function selectSnapshotReadV1({consumer, run, loadTrustedSnapshot}) {
  if (!own(roles,consumer)) throw new SnapshotInvalidError('IG_SNAPSHOT_CONSUMER_NOT_ALLOWED');
  if (!run || !Number.isSafeInteger(run.run_id) || run.run_id<=0 ||
      !Number.isSafeInteger(run.pantalla_id) || run.pantalla_id<=0 ||
      !Number.isSafeInteger(run.version_id) || run.version_id<=0)
    throw new SnapshotInvalidError('IG_SNAPSHOT_RUN_IDENTITY_INVALID');
  const canonical = reason => Object.freeze({mode:'CANONICAL_CURRENT',reason,read:null});
  if (run.status !== roles[consumer]) return canonical('STAGE_NOT_APPLICABLE');
  if (typeof loadTrustedSnapshot !== 'function') return canonical('PROVIDER_NOT_CONNECTED');
  const packet=await loadTrustedSnapshot();
  if (packet == null) return canonical('NO_SNAPSHOT_AVAILABLE');
  if (packet.schema_version==='IG_EXECUTION_SOURCE_CONTEXT_V1' &&
      packet.reuse_scope==='RUN_PINNED_FIELDS_ONLY') return canonical('G1_REFERENCE_ONLY');
  if (packet.schema_version!=='IG_EXECUTION_SOURCE_CONTEXT_V2' ||
      packet.purpose!=='READ_ONLY_DATA_PACKET' ||
      packet.reuse_scope!=='RUN_IMMUTABLE_COMPLETE' ||
      packet.consumer_stage!==roles[consumer])
    throw new SnapshotInvalidError('IG_SNAPSHOT_CONTRACT_UNRECOGNIZED');
  for (const key of ['run_id','pantalla_id','version_id','contract_snapshot_sha256','source_snapshot_sha256'])
    if (packet[key] !== run[key])
      throw new SnapshotInvalidError('IG_SNAPSHOT_IDENTITY_MISMATCH_' + key.toUpperCase());
  if (consumer==='INPUT_VALIDATOR' && (!run.curator_identity || !run.validator_identity ||
      run.curator_identity===run.validator_identity || packet.validator_identity!==run.validator_identity))
    throw new SnapshotInvalidError('IG_SNAPSHOT_VALIDATOR_INDEPENDENCE_MISSING');
  const data=packet.data;
  if (!data || typeof data!=='object' || Array.isArray(data) ||
      !sections.some(key => own(data,key)) || !/^[0-9a-f]{64}$/.test(packet.data_sha256??''))
    throw new SnapshotInvalidError('IG_SNAPSHOT_DATA_INCOMPLETE');
  if (await sha256Hex(data)!==packet.data_sha256)
    throw new SnapshotInvalidError('IG_SNAPSHOT_DATA_TAMPERED');
  if (own(data,'graph') && (!data.graph || typeof data.graph!=='object' || Array.isArray(data.graph)))
    throw new SnapshotInvalidError('IG_SNAPSHOT_GRAPH_INVALID');
  if (Object.keys(data).some(key=>!sections.includes(key)))
    throw new SnapshotInvalidError('IG_SNAPSHOT_DATA_SECTION_UNRECOGNIZED');
  // Trusted JSON object ownership passes to this scope. Freeze only once.
  deepFreeze(data);
  const indexes=Object.create(null);
  const ids={rules:['regla_id','rule_id','id'],contracts:['contrato_codigo','code'],families:['family_code']};
  const getIndex=section=>{
    if (!own(indexes,section)) indexes[section]=indexBy(data[section],ids[section],section.toUpperCase());
    return indexes[section];
  };
  function read(selection) {
    if (!selection || typeof selection!=='object' || Array.isArray(selection) ||
        Object.keys(selection).length===0 || Object.keys(selection).some(key=>!sections.includes(key)))
      throw new SnapshotInvalidError('IG_SNAPSHOT_SELECTION_INVALID');
    const view=Object.create(null);
    for (const [section,requested] of Object.entries(selection)) {
      if (!own(data,section))
        throw new SnapshotInvalidError('IG_SNAPSHOT_' + section.toUpperCase() + '_MISSING');
      if (section==='graph') {
        if (requested===true) view.graph=data.graph;
        else if (Array.isArray(requested)) {
          const graph=Object.create(null);
          for (const path of requested) graph[path]=graphPath(data.graph,path);
          view.graph=Object.freeze(graph);
        } else throw new SnapshotInvalidError('IG_SNAPSHOT_SELECTION_INVALID');
      } else if (requested===true) {
        view[section]=data[section];
      } else if (Array.isArray(requested)) {
        const index=getIndex(section);
        view[section]=Object.freeze(requested.map(id=>{
          if (typeof id!=='string' && !Number.isSafeInteger(id))
            throw new SnapshotInvalidError('IG_SNAPSHOT_SELECTION_INVALID');
          const value=index.get(String(id));
          if (value===undefined)
            throw new SnapshotInvalidError('IG_SNAPSHOT_' + section.toUpperCase() + '_KEY_MISSING');
          return value;
        }));
      } else throw new SnapshotInvalidError('IG_SNAPSHOT_SELECTION_INVALID');
    }
    return Object.freeze(view);
  }
  return Object.freeze({mode:'SHARED_SNAPSHOT',reason:'ADMITTED_INDEXED',read});
}
