#!/usr/bin/env python3
"""Claude Code Stop hook: shared PRE-Gate2 + existing Gate2 proof guard.

Never invokes Router, provider, Issue or RPC. This is NOT server-side
attestation or a universal ChatGPT hook; GPT uses the shared pre-Gate2
classifier explicitly and existing server-side terminal receipts.
"""
import json
import re
import sys
from pathlib import Path

GATE2 = 'GATE2_DERIVED_PENDING_GOVERNED_ADMISSION'
HANDOFF = 'HANDOFF_CONTEXT_TO_SELECTED_PROFILE'
EXECUTION_ID = re.compile(r'EXEC-PROFILE-GATE2-[0-9A-F]{24}\b')
ACTION = re.compile(r'\b(?:entra|ejecuta|ejecutar|revisa|revisar|corrige|corregir|'
                    r'mejora|mejorar|completa|completar|contin[uú]a|continuar|'
                    r'registra|registrar|actualiza|actualizar|inicia|iniciar)\b', re.I)
APPROVAL = re.compile(r'(?:ok|conforme|ok conforme|de acuerdo|adelante|procede|sí|si|aprobado|aprobada)[.! ]*', re.I)
PENDING = re.compile(r'\b(?:pendiente|sin iniciar|no iniciad[ao]|no ejecutad[ao]|'
                     r'bloquead[ao]|no hay recibo|sin permiso|no existe un recibo|'
                     r'no se ejecut[oó])\b|20\s*%', re.I)
KNOWN_PROVIDER_FAILURE = re.compile(r'\b(?:TOOL_ACCESS_DENIED|CONNECTOR_DENIED|'
                                    r'PROVIDER_BLOCKED_PENDING_REVIEW|'
                                    r'PROVIDER_BLOCKED|PERMISSION_DENIED|'
                                    r'ERROR_HTTP_[45]\d\d)\b', re.I)
# Shared pre-Gate2 classifier is also callable by ChatGPT (GPT_NATIVE).
# Claude Code's existing Stop hook is its local automatic entry point.
from lf_pre_gate2_consumer_gate_v1 import evaluate as evaluate_shared_continuity

PRE_GATE2_REASON = (
    "LF PRE_GATE2_ROUTE_CONTINUITY_BLOCK: no sustituir ACT-0001 por "
    "PROPOSE_ONLY_OPEN. Retoma la resolución semántica gobernada; "
    "si es imposible, informa NOT_EXECUTED / NO_CANONICAL_EFFECT "
    "con bloqueo real y evidencia, sin declarar PASS ni 100%."
)
CLOSED_CLAIM = re.compile(r'\bCOMPLETED\b', re.I)
READY_CLAIM = re.compile(r'\bREADY\b', re.I)
BLOCK_REASON = (
    'LF Gate 2 no es terminal. No cierres en 20%: con el contexto REAL '
    'recibido de ACT-0001 genera LF_PROFILE_NATIVE_BEGIN_REQUEST_V1 '
    '(sin alterar router_context, usando lf_profile_begin_payload.py), abre el Issue '
    'en el repositorio existente y etiqueta lf-profile-resume-governed; '
    'la operación nativa utiliza GitHub OIDC→Edge. Verifica en Supabase '
    'execution_id NUEVO ligado a ese workflow; continúa mismo ID 40/50/60/70/80 '
    'hasta recibo terminal 11/11 COMPLETED READY. No invoques admit_v2 '
    'con SQL RO ni muevas credenciales al Router. '
    'Si no hay transporte real, informa NOT_EXECUTED y evidencia exacta.'
)
RECEIPT_REASON = (
    'La respuesta reclama COMPLETED/READY, pero falta readback verificable '
    'del execution_id nuevo en la salida de herramientas del turno. Comprueba en Supabase '
    '11/11 STEP_PASS_WITH_EVIDENCE y el recibo terminal READY del mismo ID. '
    'Si no existe readback, informa NOT_CERTIFIED/NOT_EXECUTED sin inventar PASS.'
)


def _prompt_text(message):
    if not isinstance(message, dict):
        return ''
    content = message.get('content')
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return ' '.join(i.get('text', '') for i in content
                        if isinstance(i, dict) and i.get('type') == 'text'
                        and isinstance(i.get('text'), str))
    return ''


def _tool_text(value):
    """Read actual tool text, not JSON-escaped strings that hide word boundaries."""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return '\n'.join(_tool_text(v) for v in value)
    if isinstance(value, dict):
        if value.get('type') == 'text' and isinstance(value.get('text'), str):
            return value['text']
        return json.dumps(value, ensure_ascii=False)
    return ''


def read_current_turn(path):
    """Return prompt + tool receipts after last real user prompt.

    Tool results are commonly JSONL 'user' messages, but are not user prompts.
    Last final assistant text is supplied by the hook (transcript may lag).
    """
    if not isinstance(path, str) or not path:
        return '', ''
    try:
        p = Path(path).expanduser()
        if not p.is_file() or p.stat().st_size > 12 * 1024 * 1024:
            return '', ''
        events = []
        for line in p.read_text(encoding='utf-8').splitlines()[-1600:]:
            try:
                e = json.loads(line)
            except (TypeError, ValueError):
                continue
            if isinstance(e, dict):
                events.append(e)
        last = -1
        prompt = ''
        for ix, e in enumerate(events):
            if e.get('type') != 'user':
                continue
            msg = e.get('message')
            t = _prompt_text(msg)
            if t:
                last, prompt = ix, t
        if last < 0:
            return '', ''
        receipts = []
        for e in events[last+1:]:
            msg = e.get('message')
            content = msg.get('content') if isinstance(msg, dict) else None
            if e.get('type') == 'user' and isinstance(content, list):
                for part in content:
                    if isinstance(part, dict) and part.get('type') == 'tool_result':
                        receipts.append(_tool_text(part.get('content', '')))
        return prompt, '\n__LF_TOOL_RESULT_BOUNDARY__\n'.join(receipts)
    except (OSError, UnicodeError):
        return '', ''


def evaluate(event):
    if not isinstance(event, dict) or event.get('hook_event_name') not in (None, 'Stop'):
        return None
    final = event.get('last_assistant_message')
    if not isinstance(final, str) or not final.strip():
        return None
    # Claude Code Stop's documented recursion guard (one further stop allowed).
    if event.get('stop_hook_active') is True:
        return None
    prompt, receipts = read_current_turn(event.get('transcript_path'))
    if prompt and (ACTION.search(prompt) or APPROVAL.fullmatch(prompt.strip())):
        shared = evaluate_shared_continuity({
            "consumer_mode": "CLAUDE_NATIVE",
            "request_text": prompt,
            "tool_receipts": receipts,
            "final_text": final,
        })
        if (shared["decision"] == "BLOCK"
                and shared["reason_code"] != "GATE2_CONTEXT_UNAUTHENTICATED"):
            return {"decision": "block", "reason": PRE_GATE2_REASON}
        # Honest NOT_EXECUTED reports may end the turn. Only a structured,
        # Router-observed blocker is certified (ALLOW_TRUTHFUL_BLOCK); the
        # UNVERIFIED variant is allowed to stop but never counts as success.
        if shared["decision"] in ("ALLOW_TRUTHFUL_BLOCK",
                                  "REPORT_NOT_EXECUTED_UNVERIFIED"):
            return None
        # GATE2_CONTEXT_UNAUTHENTICATED falls through: the existing terminal
        # readback guard below is stricter than the shared classifier.
        # DEFER_TO_GATE2_RECEIPT_GUARD is NOT a PASS. The existing
        # same-run terminal-readback check continues below.

    if prompt:
        # Explanations, quote reviews and 'how does this work?' are not
        # a profile execution command. Avoid an unrelated user turn stall.
        if not ACTION.search(prompt) and not APPROVAL.fullmatch(prompt.strip()):
            return None
    elif not (GATE2 in final and HANDOFF in final):
        # No transcript and no explicit, fresh evidence in the final message.
        return None
    # Only fresh Gate 2 output or explicit no-transcript fallback can trigger.
    # Once Gate 2 is observed, final phrasing cannot silently bypass handoff.
    found = (GATE2 in receipts and HANDOFF in receipts)
    if not found and (GATE2 not in final or HANDOFF not in final):
        return None

    # A denied connector can finish honestly only if the denial is observable
    # in THIS turn's tool results, not merely asserted by the assistant.
    if (KNOWN_PROVIDER_FAILURE.search(final) and 'NOT_EXECUTED' in final
        and KNOWN_PROVIDER_FAILURE.search(receipts)):
        return None

    # The legitimate terminal proof is a SAME-RUN, same-turn readback; no
    # textual completion claim can substitute a Supabase authority receipt.
    run = EXECUTION_ID.search(final)
    terminal_readbacks = receipts.split('\n__LF_TOOL_RESULT_BOUNDARY__\n')
    if run and any(
        run.group() in proof
        and 'terminal_authority_receipt' in proof
        and 'READY' in proof
        and ('required_steps_pass' in proof or '11/11' in proof)
        and ('COMPLETED' in proof or 'required_steps' in proof)
        for proof in terminal_readbacks
    ):
        return None

    if CLOSED_CLAIM.search(final) or READY_CLAIM.search(final):
        return {'decision': 'block', 'reason': RECEIPT_REASON}

    # Always block an uncompleted Gate-2 turn, including neutrally worded
    # responses (e.g. 'handoff passed to profile'). Stop recursion is bounded
    # by Claude Code's documented stop_hook_active flag above.
    return {'decision': 'block', 'reason': BLOCK_REASON}



def main():
    try:
        event = json.load(sys.stdin)
    except (ValueError, TypeError):
        return 0
    result = evaluate(event)
    if result:
        print(json.dumps(result, ensure_ascii=False))
    return 0

if __name__ == '__main__':
    sys.exit(main())
