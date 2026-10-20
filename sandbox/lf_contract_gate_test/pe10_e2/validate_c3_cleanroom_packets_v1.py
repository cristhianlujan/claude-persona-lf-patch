import hashlib,json,sys
from pathlib import Path

def csha(obj):
    return hashlib.sha256(json.dumps(obj,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()

def load(p): return json.loads(Path(p).read_text(encoding='utf-8'))

def validate(common,b18,b29):
    assert common['schema']=='PE10_E2_C3_CLEANROOM_COMMON_ENVELOPE_V1'
    assert common['case_ref']=='PE10-IG-M107-M109-P0'
    common_sha=csha(common)
    assert common_sha=='93d4f5cba4564ddb0cc46f731375d5d83d81b724e195dfc213b2d98fc9ebc090'
    assert common['source_event']['id']==20161
    assert common['source_cutoff_utc']=='2026-10-15T00:00:00Z'
    assert common['environment_gate']['prior_pe10_results_visible_before_source_access']=='MUST_BE_FALSE'
    assert common['environment_gate']['memory_or_prior_context_inheritance']=='MUST_BE_DISABLED_OR_ABSENT'
    assert 'docs/profile_updater/experiments/pe10_e2/evaluator_only/**' in common['producer_denylist']
    for o,arm,variant,orig,algs,expected in [
        (b18,'B18','PE10_M18_E2','PE10_M18',['D'],'c450070e7f332a74e5c91115f87df7ad722aa06c81a41b550ba54cf68794bd9b'),
        (b29,'B29','PE10_M29_E2','PE10_M29',['C','E'],'a39ac7843d5a869de7ae8b6488b13f93082febd02375dd31aa3ea170372d6de5')]:
        assert o['schema']=='PE10_E2_C3_PRODUCER_OVERLAY_V1'
        assert o['case_ref']==common['case_ref']
        assert o['common_envelope_sha256']==common_sha
        assert o['producer_arm']==arm and o['evolved_variant']==variant and o['original_method']==orig
        assert o['base']=='B' and o['algorithms']==algs
        raw=dict(o); digest=raw.pop('overlay_sha256')
        assert digest==expected==csha(raw)
        assert o['output_state_before_external_grading']=='RAW_FROZEN_UNGRADED'
    assert b18['common_envelope_sha256']==b29['common_envelope_sha256']
    assert b18['overlay_sha256']!=b29['overlay_sha256']
    return {'status':'PASS','same_common_p0':True,'common_envelope_sha256':common_sha,'b18_overlay_sha256':b18['overlay_sha256'],'b29_overlay_sha256':b29['overlay_sha256']}

if __name__=='__main__':
    root=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parents[3]/'docs/profile_updater/experiments/pe10_e2/c3_cleanroom'
    print(json.dumps(validate(load(root/'COMMON_P0_INPUT_ENVELOPE_V1.json'),load(root/'B18_PRODUCER_OVERLAY_V1.json'),load(root/'B29_PRODUCER_OVERLAY_V1.json')),sort_keys=True))
