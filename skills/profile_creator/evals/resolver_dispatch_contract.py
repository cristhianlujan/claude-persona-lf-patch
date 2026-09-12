#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
contract = json.loads((ROOT / 'contracts/resolver_dispatch_contract.json').read_text(encoding='utf-8'))
resolvers = contract['resolvers']

observed_live_refs = {
    'public.lf_operation_execution',
    'public.v_lf_fuente_operativa',
    'public.v_lf_fuente_operativa.ACT-0001 + public.lf_operation_registry',
    'public.v_lf_fuente_operativa.ACT-0001 + public.lf_operation_step_contracts/CREACION_PERFIL_LF/router',
    'public.v_lf_fuente_operativa.ACT-0045',
    'v_lf_fuente_operativa + lf_activos',
    'public.v_lf_artifact_destination_registry',
    'public.v_lf_artifact_destination_registry + public.v_lf_artifact_pack_template_registry',
    'public.v_lf_artifact_pack_template_registry',
    'public.lf_operation_step_judge_bindings + public.lf_operation_judges',
    'GITHUB_API_LF_READER',
    'run-github-readback-perfil-lf',
    'run-github-write-perfil-lf',
    'GPT_RUNTIME_WITH_SUPABASE_CONTEXT',
}

checks = {
    'default_fail_closed': contract.get('default_mode') == 'BLOCK_UNMAPPED_RESOLVER',
    'all_observed_resolvers_mapped': observed_live_refs <= set(resolvers),
    'judge_not_executor_global': contract['principles'].get('judge_is_executor') is False,
    'declared_not_observed': contract['principles'].get('declared_evidence_is_observed_evidence') is False,
    'missing_evidence_fail_closed': contract['principles'].get('missing_observed_evidence_fails_closed') is True,
    'judge_ref_read_only': resolvers['public.lf_operation_step_judge_bindings + public.lf_operation_judges'].get('must_not_execute_judge_as_resolver') is True,
    'gpt_requires_observed_source': resolvers['GPT_RUNTIME_WITH_SUPABASE_CONTEXT'].get('evidence_provenance') == 'OBSERVED_SOURCE_REF_REQUIRED',
    'gpt_no_fabricated_receipt': resolvers['GPT_RUNTIME_WITH_SUPABASE_CONTEXT'].get('must_not_fabricate_receipt') is True,
    'github_write_has_prewrite': 'PRE_WRITE_EXECUTION_BINDING_GATE_CLEAN' in resolvers['run-github-write-perfil-lf'].get('requires', []),
    'github_write_has_currentness': 'CURRENT_EXECUTION_AND_STEP' in resolvers['run-github-write-perfil-lf'].get('requires', []),
    'read_modes_side_effect_free': all(not resolvers[name].get('side_effect') for name in observed_live_refs if resolvers[name]['mode'] in {'SUPABASE_READ','JUDGE_CONTRACT_READ_ONLY','GITHUB_READ','GITHUB_READBACK'}),
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit('FAIL_PROFILE_CREATOR_RESOLVER_DISPATCH:' + ','.join(failed))
print(f'PASS_PROFILE_CREATOR_RESOLVER_DISPATCH={sum(checks.values())}/{len(checks)}')
