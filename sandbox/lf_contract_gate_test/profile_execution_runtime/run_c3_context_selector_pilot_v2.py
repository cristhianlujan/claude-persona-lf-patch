#!/usr/bin/env python3
from __future__ import annotations

import run_c3_context_selector_pilot as base

# Pilot-only structured-output boundary. Every object declares explicit properties
# so the pinned llama.cpp JSON-schema -> grammar converter never has to materialize
# an unconstrained/empty object shape. This does not alter the canonical profile.
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
                        'specialties': {'type': 'array', 'items': {'type': 'string'}},
                        'assumptions': {'type': 'array', 'items': {'type': 'string'}},
                    },
                    'required': ['task_mode', 'screen_name'],
                },
                'component_tree': {
                    'type': 'array',
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
                            'color_tokens': {'type': 'array', 'items': {'type': 'string'}},
                            'typography': {
                                'type': 'object',
                                'additionalProperties': False,
                                'properties': {'entries': {'type': 'array', 'items': ENTRY}},
                                'required': ['entries'],
                            },
                            'spacing': {
                                'type': 'object',
                                'additionalProperties': False,
                                'properties': {'entries': {'type': 'array', 'items': ENTRY}},
                                'required': ['entries'],
                            },
                            'state': {'type': 'string'},
                            'allowed_variants': {'type': 'array', 'items': {'type': 'string'}},
                            'blocked_variants': {'type': 'array', 'items': {'type': 'string'}},
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
                        'responsive_notes': {'type': 'array', 'items': {'type': 'string'}},
                    },
                    'required': ['pattern', 'responsive_notes'],
                },
                'visual_hierarchy': {
                    'type': 'array',
                    'items': {
                        'type': 'object',
                        'additionalProperties': False,
                        'properties': {
                            'parent_id': {'type': 'string'},
                            'child_ids': {'type': 'array', 'items': {'type': 'string'}},
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
                    'properties': {'entries': {'type': 'array', 'items': ENTRY}},
                    'required': ['entries'],
                },
                'spacing_typography': {
                    'type': 'object',
                    'additionalProperties': False,
                    'properties': {'entries': {'type': 'array', 'items': ENTRY}},
                    'required': ['entries'],
                },
                'density_rules': {'type': 'array', 'items': {'type': 'string'}},
                'risk_controls': {'type': 'array', 'items': {'type': 'string'}},
                'prompt_constraints': {'type': 'array', 'items': {'type': 'string'}},
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
                'layout_precision': {'type': 'integer'},
                'visual_hierarchy': {'type': 'integer'},
                'lf_system_fidelity': {'type': 'integer'},
                'state_mapping': {'type': 'integer'},
                'handoff_quality': {'type': 'integer'},
                'total': {'type': 'integer'},
                'evidence_by_criterion': {'type': 'array', 'items': {'type': 'string'}},
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
                'notes': {'type': 'array', 'items': {'type': 'string'}},
            },
            'required': ['status', 'notes'],
        },
        'self_verdict': {'type': 'string'},
    },
    'required': ['worker','output_type','deliverable_created','score','handoff_to_next','self_verdict'],
}

base.C3_RUNTIME_SCHEMA = C3_RUNTIME_SCHEMA_V2
base.OUTPUT_GUARD = '''
RUNTIME OUTPUT GUARD — deterministic materialization
Return one compact JSON object only; no Markdown fences or prose.
Root keys exactly: worker, output_type, deliverable_created, score, handoff_to_next, self_verdict.
deliverable_created sibling keys exactly: screen_definition, component_tree, layout_grid, visual_hierarchy, state_map, token_map, spacing_typography, density_rules, risk_controls, prompt_constraints.
component_tree is flat. content is terminal text; relationships use IDs only.
visual_hierarchy is a flat array of {parent_id:string, child_ids:[string,...]}; child_ids NEVER contains objects.
For generic key/value metadata use {entries:[{key:string,value:string}, ...]}.
state_map uses {entries:[{component_id:string,state:string,behavior:string}, ...]}.
Keep every section minimal and bounded. Do not repeat financial facts unless required for meaning.
self_verdict must be a string. Preserve every supplied case requirement exactly; do not invent financial truth.
'''.strip()

if __name__ == '__main__':
    raise SystemExit(base.main())
