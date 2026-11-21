// Preflight for discovered SOURCE candidates, NOT an executable connector.
// The caller must authenticate catalog evidence and business authorization.
// No fetch, credentials, side effects, profile, Router or persistence.
const object = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const filled = x => typeof x === 'string' && x.trim() !== '';
const positive = x => Number.isSafeInteger(x) && x > 0;
const fail = (code,stage) => Object.freeze({state:'BLOCKED',code,stage,
  runtime_authorized:false,contact_authorized:false,write_authorized:false,
  evidence_verified_by_runtime:false});
const candidate = (code,stage) => Object.freeze({state:'ADAPTER_DESIGN_CANDIDATE',code,stage,
  runtime_authorized:false,contact_authorized:false,write_authorized:false,
  evidence_verified_by_runtime:false});
function canonicalUrl(url) {
  try {
    const u=new URL(url);
    if(u.protocol !== 'https:' || !u.hostname || u.username || u.password ||
       u.hash || u.search || u.port || u.pathname.includes('..'))return null;
    return u.href;
  } catch { return null; }
}
export function inspectSourceCandidate(input) {
  if(!object(input) || !object(input.source) || !object(input.catalog) ||
     !object(input.business_policy) || !object(input.technical))
    return fail('SOURCE_PREFLIGHT_INPUT_INCOMPLETE','REQUEST');
  const {source:s,catalog:c,business_policy:p,technical:t}=input;
  if(!filled(s.source_id) || !filled(s.business_code) || !filled(s.resource_url) ||
     !filled(s.source_version) || !filled(s.format) ||
     !['CSV','ZIP','XLSX','HTML','API_JSON'].includes(s.format))
    return fail('SOURCE_PREFLIGHT_REQUEST_INVALID','REQUEST');
  const src=canonicalUrl(s.resource_url), cat=canonicalUrl(c.resource_url);
  if(src===null || cat===null || src!==cat ||
     s.source_id!==c.source_id || s.source_version!==c.source_version ||
     !filled(c.dataset_uri) || !filled(c.publisher) || !filled(c.readback_ref) ||
     !filled(c.checked_at) || !filled(c.format) || s.format!==c.format)
    return fail('SOURCE_CATALOG_INDEPENDENT_MATCH_MISSING','CATALOG');
  if(!object(p) || p.business_code!==s.business_code ||
     p.effect!=='READ_ONLY' || !filled(p.policy_ref) ||
     !Array.isArray(p.approved_sources) ||
     !p.approved_sources.includes(s.source_id))
    return fail('SOURCE_NOT_ALLOWED_BY_BUSINESS','POLICY');
  // A public URL alone is NOT a permission to persist or contact people.
  if(c.license_status!=='VERIFIED_REUSE_PERMITTED' ||
     !filled(c.license_evidence_ref) || !filled(c.license_code))
    return fail('SOURCE_LICENSE_OR_USAGE_UNRESOLVED','RIGHTS');
  if(c.personal_data_scope==='POSSIBLE' || c.personal_data_scope==='YES') {
    if(p.personal_data_use_approved!==true ||
       !filled(p.personal_data_decision_ref))
      return fail('SOURCE_PERSONAL_DATA_SCOPE_BLOCK','PRIVACY');
  } else if(c.personal_data_scope!=='NO') {
    return fail('SOURCE_PERSONAL_DATA_UNKNOWN','PRIVACY');
  }
  if(!positive(t.max_download_bytes) || !positive(t.max_unpacked_bytes) ||
     !filled(t.capability_ref))
    return fail('SOURCE_TECHNICAL_LIMITS_MISSING','LIMITS');
  if(!positive(c.declared_size_bytes) ||
     c.declared_size_bytes>t.max_download_bytes)
    return fail('SOURCE_SIZE_UNVERIFIED_OR_OVER_LIMIT','LIMITS');
  if(s.format==='API_JSON') {
    if(t.billing_authorized!==true || !filled(t.billing_decision_ref))
      return fail('SOURCE_API_BILLING_BLOCK','BILLING');
    if(t.terms_approved!==true || !filled(t.terms_decision_ref))
      return fail('SOURCE_API_TERMS_BLOCK','RIGHTS');
  }
  if(s.format==='ZIP') {
    if(t.zip_streaming_verified!==true || !filled(t.zip_test_ref))
      return fail('SOURCE_ZIP_STREAMING_NOT_PROVEN','ARCHIVE');
    if(t.zip_entry_safety_verified!==true ||
       !filled(t.zip_entry_safety_ref))
      return fail('SOURCE_ZIP_BOMB_PATH_TRAVERSAL_UNPROVEN','ARCHIVE');
  }
  if(t.schema_verified!==true || !filled(t.schema_ref))
    return fail('SOURCE_SCHEMA_NOT_VERIFIED','SCHEMA');
  if(t.adapter_tested!==true || !filled(t.adapter_test_ref))
    return candidate('SOURCE_NEEDS_ADAPTER_TEST','ADAPTER');
  return candidate('SOURCE_PREFLIGHT_PASS_CANDIDATE_ONLY','REVIEW');
}
