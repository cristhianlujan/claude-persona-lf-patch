// Offline design guard. It does not authenticate an ACT-0001 handoff or authorize a RUN.
const isObj = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const names = v => Array.isArray(v) && v.length > 0 && v.every(x => typeof x === 'string' && x.trim().length > 0);
const block = code => Object.freeze({status:'BLOCKED', code, runtime_authorized:false});

export function planBusinessAdapterBinding({routerBusiness, businessCatalog, businessPolicy, sourceAdapter, specialistRole}) {
  if (!isObj(routerBusiness) || routerBusiness.source !== 'ACT-0001_EXTERNAL_TRUSTED_HANDOFF' ||
      !/^[A-Z][A-Z0-9_-]*$/.test(routerBusiness.business_code || ''))
    return block('MISSING_TRUSTED_ROUTER_BUSINESS');
  // The caller, not this pure function, must authenticate the Router handoff and catalog readback.
  if (!Array.isArray(businessCatalog) || businessCatalog.filter(x => isObj(x) &&
      x.business_code === routerBusiness.business_code && x.status === 'ENABLED').length !== 1)
    return block('BUSINESS_NOT_ENABLED_OR_AMBIGUOUS');
  if (!isObj(businessPolicy) || businessPolicy.business_code !== routerBusiness.business_code ||
      typeof businessPolicy.policy_ref !== 'string' || !businessPolicy.policy_ref.trim() ||
      typeof businessPolicy.version !== 'string' || !businessPolicy.version.trim() ||
      businessPolicy.effect !== 'READ_ONLY' || !names(businessPolicy.sources))
    return block('BUSINESS_POLICY_NOT_BOUND');
  if (!isObj(sourceAdapter) || typeof sourceAdapter.adapter_id !== 'string' ||
      !sourceAdapter.adapter_id.trim() || typeof sourceAdapter.source_id !== 'string' ||
      !sourceAdapter.source_id.trim() || sourceAdapter.effect !== 'READ_ONLY' ||
      sourceAdapter.business_specific === true || !businessPolicy.sources.includes(sourceAdapter.source_id))
    return block('SOURCE_ADAPTER_NOT_ALLOWED_BY_BUSINESS');
  // A functional role is not a new profile, a profile code, or native selection evidence.
  if (!isObj(specialistRole) || specialistRole.role !== 'DISCOVERY' ||
      specialistRole.business_code !== null || specialistRole.runtime_selected === true)
    return block('ROLE_MUST_REMAIN_SHARED_CANDIDATE');
  return Object.freeze({
    status:'CANDIDATE_BINDING_ONLY',
    role:'DISCOVERY',
    business_code:routerBusiness.business_code,
    source_id:sourceAdapter.source_id,
    adapter_id:sourceAdapter.adapter_id,
    business_policy_ref:businessPolicy.policy_ref,
    business_policy_version:businessPolicy.version,
    effect:'READ_ONLY',
    runtime_authorized:false,
    native_profile_selected:false,
    next_gate:'AUTHENTICATED_ROUTER_BINDING_AND_NATIVE_PROFILE_SELECTION'
  });
}
