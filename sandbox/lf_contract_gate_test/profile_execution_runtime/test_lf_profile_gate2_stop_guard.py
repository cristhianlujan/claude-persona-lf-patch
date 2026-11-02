import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import sys

M = Path(__file__).with_name('lf_profile_gate2_stop_guard.py')
# The hook imports the shared evaluator by sibling module name.
sys.path.insert(0, str(M.parent))
spec = importlib.util.spec_from_file_location('lf_guard', M)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
G = 'GATE2_DERIVED_PENDING_GOVERNED_ADMISSION HANDOFF_CONTEXT_TO_SELECTED_PROFILE'


def event(final, **extras):
    return {'hook_event_name': 'Stop', 'last_assistant_message': final, **extras}


class Gate2StopGuard(unittest.TestCase):
    def with_transcript(self, prompt, tool_text, final):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        p = Path(d.name) / 'session.jsonl'
        results = tool_text if isinstance(tool_text, list) else [tool_text]
        messages = [{'type': 'user', 'message': {'content': prompt}}]
        for result in results:
            messages += [
                {'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'name': 'mcp'}]}},
                {'type': 'user', 'message': {'content': [{'type': 'tool_result',
                    'content': [{'type': 'text', 'text': result}]}]}},
            ]
        p.write_text('\n'.join(json.dumps(m) for m in messages))
        return event(final, transcript_path=str(p))

    def test_pending_gate2_blocks(self):
        e = self.with_transcript('Entra por Router y revisa login B2B', G,
                                 'Etapa 07 pendiente de inicio, avance 20%.')
        self.assertEqual(module.evaluate(e)['decision'], 'block')

    def test_only_20_percent_blocks(self):
        e = self.with_transcript('Ejecuta el perfil LF por Router', G,
                                 'Gate 2: 20%')
        self.assertEqual(module.evaluate(e)['decision'], 'block')

    def test_terminal_claim_without_execution_id_blocks(self):
        e = self.with_transcript('Ejecuta el perfil LF por Router', G,
                                 'GATE2 11/11 COMPLETED READY')
        self.assertEqual(module.evaluate(e)['decision'], 'block')

    def test_terminal_claim_with_execution_id_without_receipt_is_blocked(self):
        e = self.with_transcript('Ejecuta el perfil LF por Router', G,
            '11/11 COMPLETED READY EXEC-PROFILE-GATE2-' + 'A' * 24)
        self.assertEqual(module.evaluate(e)['decision'], 'block')

    def test_terminal_authority_tool_readback_allows_stop(self):
        rid = 'EXEC-PROFILE-GATE2-' + 'A' * 24
        evidence = G + '\n' + json.dumps({
            'execution_id': rid, 'run_status': 'COMPLETED',
            'terminal_authority_receipt': {'status': 'READY'},
            'required_steps_pass': 11, 'required_steps': 11})
        e = self.with_transcript('Ejecuta el perfil LF por Router', evidence,
                                 '11/11 COMPLETED READY ' + rid)
        self.assertIsNone(module.evaluate(e))

    def test_neutral_handoff_without_pending_words_blocks(self):
        e = self.with_transcript('Ejecuta el perfil LF por Router', G,
                                 'La solicitud fue derivada correctamente al perfil.')
        self.assertEqual(module.evaluate(e)['decision'], 'block')

    def test_claimed_access_denial_without_tool_proof_blocks(self):
        e = self.with_transcript('Ejecuta el perfil LF por Router', G,
                                 'NOT_EXECUTED: TOOL_ACCESS_DENIED')
        self.assertEqual(module.evaluate(e)['decision'], 'block')

    def test_short_approval_continues_after_fresh_gate2(self):
        e = self.with_transcript('Ok conforme', G,
                                 'El Router entregó el contexto al perfil.')
        self.assertEqual(module.evaluate(e)['decision'], 'block')

    def test_short_ok_continues_after_fresh_gate2(self):
        e = self.with_transcript('Ok', G, 'Se preparó el handoff.')
        self.assertEqual(module.evaluate(e)['decision'], 'block')

    def test_cross_run_split_receipts_do_not_authorize_stop(self):
        rid = 'EXEC-PROFILE-GATE2-' + 'A' * 24
        different = 'EXEC-PROFILE-GATE2-' + 'B' * 24
        fragments = [G, json.dumps({'execution_id':rid,'status':'COMPLETED',
                    'required_steps_pass':11}),
                    json.dumps({'execution_id':different,
                    'terminal_authority_receipt':{'status':'READY'},
                    'required_steps_pass':11,'required_steps':11})]
        e = self.with_transcript('Ok conforme', fragments,
              '11/11 COMPLETED READY ' + rid)
        self.assertEqual(module.evaluate(e)['decision'], 'block')

    def test_informative_conversation_does_not_trigger(self):
        e = self.with_transcript('¿Qué es Gate 2 en la arquitectura?', G,
                                 'Etapa 07 pendiente')
        self.assertIsNone(module.evaluate(e))

    def test_quote_from_older_turn_ignored(self):
        e = self.with_transcript('¿Cómo funciona el recibo?', 'READY', 'No iniciado')
        self.assertIsNone(module.evaluate(e))

    def test_old_tool_result_before_latest_prompt_ignored(self):
        e = self.with_transcript('¿Puedes explicar el registro?', G, 'Etapa 07 pendiente')
        self.assertIsNone(module.evaluate(e))

    def test_denied_with_evidence_can_finish_truthfully(self):
        e = self.with_transcript('Ejecuta el perfil LF', G + '\nTOOL_ACCESS_DENIED: Github Issue not permitted',
            'NOT_EXECUTED: TOOL_ACCESS_DENIED; cannot open GitHub Issue')
        self.assertIsNone(module.evaluate(e))

    def test_generic_not_executed_without_provider_error_blocks(self):
        e = self.with_transcript('Ejecuta el perfil LF', G,
            'NOT_EXECUTED: queda pendiente, etapa 07 no iniciada')
        self.assertEqual(module.evaluate(e)['decision'], 'block')

    def test_recursion_guard(self):
        e = self.with_transcript('Ejecuta el perfil LF', G, 'Etapa 07 pendiente')
        e['stop_hook_active'] = True
        self.assertIsNone(module.evaluate(e))

    def test_no_evidence_no_block(self):
        self.assertIsNone(module.evaluate(event('Etapa 07 pendiente')))
        self.assertIsNone(module.evaluate(event('Otra operación sin relación con LF.')))

    def test_fallback_explicit_pair(self):
        self.assertEqual(module.evaluate(event(G + ': stage 7 pendiente'))['decision'], 'block')

    def test_pre_gate2_scope_block_plus_propose_only_cannot_claim_100_percent(self):
        receipt = ('ACT-0001 BLOCK_SCOPE_SEMANTICS_UNATTESTED '
                   'lf_router_dispatch_v1 PROPOSE_ONLY_OPEN')
        e = self.with_transcript(
            'Entra por Router y define la política de intentos fallidos B2B',
            receipt,
            'Definición registrada — 100%. Issue #3505 preparado.')
        self.assertEqual(module.evaluate(e)['decision'], 'block')
        self.assertIn('PRE_GATE2_ROUTE_CONTINUITY_BLOCK',
                      module.evaluate(e)['reason'])

    def test_pre_gate2_proposal_issue_is_not_equivalent_to_run(self):
        e = self.with_transcript(
            'Continúa por el Router y registra la regla LF',
            'BLOCK_SCOPE_SEMANTICS_UNATTESTED; PROPOSE_ONLY_OPEN',
            'Se entregó el Issue #3505 como resultado del recorrido.')
        self.assertEqual(module.evaluate(e)['decision'], 'block')

    def test_pre_gate2_honest_blocked_state_can_stop(self):
        e = self.with_transcript(
            'Entra por el Router y define una regla B2B',
            'BLOCK_SCOPE_SEMANTICS_UNATTESTED; PROPOSE_ONLY_OPEN',
            'BLOCK_SCOPE_SEMANTICS_UNATTESTED / NOT_EXECUTED / '
            'NO_CANONICAL_EFFECT. Sin sujeto resuelto ni escritura oficial; '
            'se necesita una decisión de la autoridad correspondiente.')
        self.assertIsNone(module.evaluate(e))

    def test_pre_gate2_explicit_denial_with_tool_receipt_can_stop(self):
        e = self.with_transcript(
            'Entra por el Router y define una regla B2B',
            'BLOCK_SCOPE_SEMANTICS_UNATTESTED; PROPOSE_ONLY_OPEN; '
            'TOOL_ACCESS_DENIED: missing Github authorization',
            'NOT_EXECUTED / TOOL_ACCESS_DENIED: la operación no puede continuar')
        self.assertIsNone(module.evaluate(e))

    def test_pre_gate2_honest_block_with_completed_claim_still_blocks(self):
        e = self.with_transcript(
            'Ejecuta la actualización de regla LF',
            'BLOCK_SCOPE_SEMANTICS_UNATTESTED; PROPOSE_ONLY_OPEN',
            'BLOCK_SCOPE_SEMANTICS_UNATTESTED / NOT_EXECUTED / '
            'NO_CANONICAL_EFFECT. Definición registrada y completada 100%.')
        self.assertEqual(module.evaluate(e)['decision'], 'block')

    def test_pre_gate2_block_without_proposal_requires_explicit_no_effect(self):
        e = self.with_transcript(
            'Entra por el Router y revisa la definición LF',
            'BLOCK_SCOPE_SEMANTICS_UNATTESTED',
            'BLOCK_SCOPE_SEMANTICS_UNATTESTED / NOT_EXECUTED / '
            'NO_CANONICAL_EFFECT. No se aplicó ninguna modificación.')
        self.assertIsNone(module.evaluate(e))
        e = self.with_transcript(
            'Entra por el Router y revisa la definición LF',
            'BLOCK_SCOPE_SEMANTICS_UNATTESTED',
            'La política quedó VIGENTE en Supabase.')
        self.assertEqual(module.evaluate(e)['decision'], 'block')

    def test_pre_gate2_alternate_blocker_can_close_only_as_blocked(self):
        e = self.with_transcript(
            'Entra por el Router y actualiza las reglas LF',
            'BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED; PROPOSE_ONLY_OPEN',
            'BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED / NOT_EXECUTED / '
            'NO_CANONICAL_EFFECT. No se han registrado cambios.')
        self.assertIsNone(module.evaluate(e))

    def test_pre_gate2_provider_denial_cannot_mask_claimed_completion(self):
        e = self.with_transcript(
            'Entra por Router y define regla LF',
            'BLOCK_SCOPE_SEMANTICS_UNATTESTED; PROPOSE_ONLY_OPEN; '
            'TOOL_ACCESS_DENIED',
            'NOT_EXECUTED / TOOL_ACCESS_DENIED. Definición registrada al 100%.')
        self.assertEqual(module.evaluate(e)['decision'], 'block')

    def test_subsequent_valid_gate2_run_uses_existing_terminal_guard(self):
        rid = 'EXEC-PROFILE-GATE2-' + 'A' * 24
        receipts = [
            'BLOCK_SCOPE_SEMANTICS_UNATTESTED PROPOSE_ONLY_OPEN',
            G,
            json.dumps({'execution_id': rid, 'run_status': 'COMPLETED',
                        'terminal_authority_receipt': {'status': 'READY'},
                        'required_steps_pass': 11, 'required_steps': 11}),
        ]
        e = self.with_transcript('Ejecuta perfil por Router',
                                 receipts, '11/11 COMPLETED READY ' + rid)
        self.assertIsNone(module.evaluate(e))

    def test_no_direct_writes(self):
        source = M.read_text()
        for x in ('UPDATE lf_ops.reglas', 'service_role_key',
                  'lf_router_pipeline_context_profile_admit_v2('):
            self.assertNotIn(x, source)


if __name__ == '__main__': unittest.main()
