#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import os
import subprocess
import sys
from pathlib import Path

import github_actions_local_runtime as runtime_module
import run_c3_context_selector_pilot as base
from profile_runtime_runner import RuntimeExecutionBlocked


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def _schema_converter() -> Path:
    cli = Path(os.environ['LF_LLAMA_CLI_PATH']).resolve()
    candidate = (cli.parents[2] / 'examples' / 'json_schema_to_grammar.py').resolve()
    if not candidate.is_file():
        raise RuntimeExecutionBlocked('C3_GBNF_CONVERTER_MISSING', str(candidate))
    return candidate


class GBNFSchemaAdapter(base.GitHubHostedLlamaCppAdapter):
    """Pilot-only transport fix: preconvert -jf schema to pinned GBNF."""

    def __init__(self, *args, **kwargs):
        # Long authoritative cases reached the score section with every functional
        # requirement preserved but truncated at the previous output ceiling.
        # Keep generation bounded while giving structured JSON enough room to close.
        if kwargs.get('max_output_tokens') == 2048:
            kwargs['max_output_tokens'] = 4096
        super().__init__(*args, **kwargs)

    def execute(self, request):
        converter = _schema_converter()
        original_run = runtime_module.subprocess.run
        converted: dict[str, Path] = {}

        def intercept(command, *args, **kwargs):
            if isinstance(command, list) and '-jf' in command:
                if converted:
                    raise RuntimeExecutionBlocked('C3_GBNF_DUPLICATE_CONVERSION')
                idx = command.index('-jf')
                if idx + 1 >= len(command):
                    raise RuntimeExecutionBlocked('C3_GBNF_SCHEMA_ARG_MISSING')
                schema_path = Path(command[idx + 1]).resolve()
                if not schema_path.is_file():
                    raise RuntimeExecutionBlocked('C3_GBNF_SCHEMA_MISSING', str(schema_path))

                conversion = original_run(
                    [sys.executable, str(converter), str(schema_path)],
                    cwd=self.work_dir,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=120,
                    check=False,
                )
                grammar_text = conversion.stdout.strip()
                if conversion.returncode != 0 or not grammar_text or 'root ::=' not in grammar_text:
                    detail = conversion.stderr[-1200:].replace('\n', ' ').strip()
                    raise RuntimeExecutionBlocked(
                        'C3_GBNF_CONVERSION_FAILED',
                        f'rc={conversion.returncode} stderr={detail}',
                    )

                output_idx = command.index('-o') + 1
                grammar_path = Path(command[output_idx]).resolve().with_name('runtime-output.gbnf')
                grammar_path.write_text(grammar_text + '\n', encoding='utf-8')
                converted['schema'] = schema_path
                converted['grammar'] = grammar_path

                rewritten = list(command)
                rewritten[idx:idx + 2] = ['--grammar-file', str(grammar_path)]
                return original_run(rewritten, *args, **kwargs)
            return original_run(command, *args, **kwargs)

        runtime_module.subprocess.run = intercept
        try:
            response = super().execute(request)
        finally:
            runtime_module.subprocess.run = original_run

        if converted:
            grammar_path = converted['grammar']
            self.structured_output_grammar_path = grammar_path
            attestation = response.get('runtime_attestation')
            if not isinstance(attestation, dict):
                raise RuntimeExecutionBlocked('C3_GBNF_ATTESTATION_MISSING')
            attestation.update({
                'structured_output_transport': 'GBNF_PRECONVERTED',
                'structured_output_grammar_sha256': _sha256_file(grammar_path),
                'json_schema_converter_ref': 'llama.cpp/examples/json_schema_to_grammar.py',
                'json_schema_converter_sha256': _sha256_file(converter),
            })
        return response


# Pilot-only structured-output boundary. Cardinalities are explicitly bounded so
# the grammar cannot consume the output budget by expanding optional/repeated data.
# This does not alter the canonical profile or its domain authority.
ENTRY = {
    'type': 'object',
    'additionalProperties': False,
    'properties': {
        'key': {'type': 'string'},
        'value': {'type': 'string'},
    },
    'required': ['key', 'value'],
}

C3_RUNTIME_SCHEMA_V2 = {
    'type': 'object',
    'additionalProperties': False,
    'properties': {
        'worker': {'type': 'string'},
        'output_type': {'type': 'string'},
        'deliverable_created': {
            'type': 'object',
            'additionalProperties': False,
            'properties': {
                'screen_definition': {
                    'type': 'object',
                    'additionalProperties': False,
                    'properties': {
                        'task_mode': {'type': 'string'},
                        'screen_name': {'type': 'string'},
                        'purpose': {'type': 'string'},
                        'mode_operativo': {'type': 'string'},
                        'specialties': {'type': 'array', 'maxItems': 4, 'items': {'type': 'string'}},
                    },
                    'required': ['task_mode', 'screen_name'],
                },
                'component_tree': {
                    'type': 'array',
                    'maxItems': 10,
                    'items': {
                        'type': 'object',
                        'additionalProperties': False,
                        'properties': {
                            'zone_id': {'type': 'string'},
                            'component_id': {'type': 'string'},
                            'component_type': {'type': 'string'},
                            'role': {'type': 'string'},
                            'content': {'type': 'string'},
                            'visual_priority': {'type': 'integer'},
                            'color_tokens': {'type': 'array', 'maxItems': 4, 'items': {'type': 'string'}},
                            'typography': {
                                'type': 'object',
                                'additionalProperties': False,
                                'properties': {'entries': {'type': 'array', 'maxItems': 3, 'items': ENTRY}},
                                'required': ['entries'],
                            },
                            'spacing': {
                                'type': 'object',
                                'additionalProperties': False,
                                'properties': {'entries': {'type': 'array', 'maxItems': 3, 'items': ENTRY}},
                                'required': ['entries'],
                            },
                            'state': {'type': 'string'},
                            'allowed_variants': {'type': 'array', 'maxItems': 4, 'items': {'type': 'string'}},
                            'blocked_variants': {'type': 'array', 'maxItems': 4, 'items': {'type': 'string'}},
                        },
                        'required': [
                            'zone_id','component_id','component_type','role','content','visual_priority',
                            'color_tokens','typography','spacing','state','allowed_variants','blocked_variants'
                        ],
                    },
                },
                'layout_grid': {
                    'type': 'object',
                    'additionalProperties': False,
                    'properties': {
                        'pattern': {'type': 'string'},
                        'columns': {'type': 'integer'},
                        'rows': {'type': 'integer'},
                        'responsive_notes': {'type': 'array', 'maxItems': 3, 'items': {'type': 'string'}},
                    },
                    'required': ['pattern', 'responsive_notes'],
                },
                'visual_hierarchy': {
                    'type': 'array',
                    'maxItems': 10,
                    'items': {
                        'type': 'object',
                        'additionalProperties': False,
                        'properties': {
                            'parent_id': {'type': 'string'},
                            'child_ids': {'type': 'array', 'maxItems': 10, 'items': {'type': 'string'}},
                        },
                        'required': ['parent_id', 'child_ids'],
                    },
                },
                'state_map': {
                    'type': 'object',
                    'additionalProperties': False,
                    'properties': {
                        'entries': {
                            'type': 'array',
                            'maxItems': 10,
                            'items': {
                                'type': 'object',
                                'additionalProperties': False,
                                'properties': {
                                    'component_id': {'type': 'string'},
                                    'state': {'type': 'string'},
                                    'behavior': {'type': 'string'},
                                },
                                'required': ['component_id', 'state', 'behavior'],
                            },
                        },
                    },
                    'required': ['entries'],
                },
                'token_map': {
                    'type': 'object',
                    'additionalProperties': False,
                    'properties': {'entries': {'type': 'array', 'maxItems': 8, 'items': ENTRY}},
                    'required': ['entries'],
                },
                'spacing_typography': {
                    'type': 'object',
                    'additionalProperties': False,
                    'properties': {'entries': {'type': 'array', 'maxItems': 8, 'items': ENTRY}},
                    'required': ['entries'],
                },
                'density_rules': {'type': 'array', 'maxItems': 6, 'items': {'type': 'string'}},
                'risk_controls': {'type': 'array', 'maxItems': 8, 'items': {'type': 'string'}},
                'prompt_constraints': {'type': 'array', 'maxItems': 8, 'items': {'type': 'string'}},
            },
            'required': [
                'screen_definition','component_tree','layout_grid','visual_hierarchy','state_map',
                'token_map','spacing_typography','density_rules','risk_controls','prompt_constraints'
            ],
        },
        'score': {
            'type': 'object',
            'additionalProperties': False,
            'properties': {
                'layout_precision': {'type': 'integer', 'minimum': 0, 'maximum': 5},
                'visual_hierarchy': {'type': 'integer', 'minimum': 0, 'maximum': 5},
                'lf_system_fidelity': {'type': 'integer', 'minimum': 0, 'maximum': 4},
                'state_mapping': {'type': 'integer', 'minimum': 0, 'maximum': 5},
                'handoff_quality': {'type': 'integer', 'minimum': 0, 'maximum': 5},
                'total': {'type': 'integer', 'minimum': 0, 'maximum': 24},
                'evidence_by_criterion': {'type': 'array', 'maxItems': 5, 'items': {'type': 'string'}},
            },
            'required': [
                'layout_precision','visual_hierarchy','lf_system_fidelity','state_mapping',
                'handoff_quality','total','evidence_by_criterion'
            ],
        },
        'handoff_to_next': {
            'type': 'object',
            'additionalProperties': False,
            'properties': {
                'next_worker': {'type': 'string'},
                'status': {'type': 'string'},
                'notes': {'type': 'array', 'maxItems': 3, 'items': {'type': 'string'}},
            },
            'required': ['status', 'notes'],
        },
        'self_verdict': {'type': 'string'},
    },
    'required': ['worker','output_type','deliverable_created','score','handoff_to_next','self_verdict'],
}


def _bound_free_strings(node, path: tuple[str, ...] = ()) -> None:
    """Bound only unconstrained free-form strings without changing schema shape."""
    if isinstance(node, dict):
        if (
            node.get('type') == 'string'
            and 'enum' not in node
            and 'const' not in node
            and 'maxLength' not in node
            and path[-4:] != ('component_tree', 'items', 'properties', 'content')
        ):
            node['maxLength'] = 320
        for key, value in node.items():
            _bound_free_strings(value, path + (str(key),))
    elif isinstance(node, list):
        for idx, value in enumerate(node):
            _bound_free_strings(value, path + (str(idx),))


_bound_free_strings(C3_RUNTIME_SCHEMA_V2)

base.C3_RUNTIME_SCHEMA = C3_RUNTIME_SCHEMA_V2
base.GitHubHostedLlamaCppAdapter = GBNFSchemaAdapter
base.OUTPUT_GUARD = '''
RUNTIME OUTPUT GUARD — deterministic materialization
Return one compact JSON object only; no Markdown fences or prose.
Root keys exactly: worker, output_type, deliverable_created, score, handoff_to_next, self_verdict.
deliverable_created sibling keys exactly: screen_definition, component_tree, layout_grid, visual_hierarchy, state_map, token_map, spacing_typography, density_rules, risk_controls, prompt_constraints.
component_tree is flat and bounded; represent each material requirement once. content is terminal text; relationships use IDs only.
visual_hierarchy is a flat array of {parent_id:string, child_ids:[string,...]}; child_ids NEVER contains objects.
For generic key/value metadata use {entries:[{key:string,value:string}, ...]}.
state_map uses {entries:[{component_id:string,state:string,behavior:string}, ...]}.
Keep every section minimal. score.evidence_by_criterion uses short non-duplicative evidence, never a restatement of the whole screen.
Do not repeat financial facts across sections unless required for meaning.
self_verdict must be a string. Preserve every supplied case requirement exactly; do not invent financial truth.
'''.strip()

if __name__ == '__main__':
    raise SystemExit(base.main())
