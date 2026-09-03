#!/usr/bin/env python3
"""Apply accepted targeted-reread decisions as a non-destructive overlay.

Original OCR text/bbox/role are immutable evidence. An accepted reread may add
`effective_text` for downstream consumers, together with explicit provenance.
Rejected/unmapped decisions leave the original observation untouched.
"""
from __future__ import annotations
import copy


def apply_overlay(resolver_result: dict, reread_result: dict) -> dict:
    if resolver_result.get('schema') != 'lf-structural-context-resolver/v3':
        raise ValueError('resolver_schema_invalid')
    observations=copy.deepcopy(resolver_result.get('observations') or [])
    decisions={}
    for region in reread_result.get('regions') or []:
        rid=region.get('id'); d=region.get('decision') or {}
        if rid is None or rid in decisions:
            if rid in decisions: raise ValueError('duplicate_reread_region_id')
            continue
        decisions[rid]=(region,d)
    adopted_ids=[]
    for obs in observations:
        rid=obs.get('id')
        if rid not in decisions: continue
        region,d=decisions[rid]
        # Geometry/role binding must match the residual request; no cross-region overlay.
        if region.get('role') is not None and region.get('role') != obs.get('role'):
            raise ValueError(f'role_mismatch:{rid}')
        if region.get('bbox') is not None:
            ob=[float(obs.get(k,0)) for k in ('x','y','w','h')]
            rb=[float(x) for x in region.get('bbox')]
            if len(rb)!=4 or any(abs(a-b)>0.001 for a,b in zip(ob,rb)):
                raise ValueError(f'bbox_mismatch:{rid}')
        if d.get('adopted') is not True or d.get('source') != 'TARGETED_REREAD':
            continue
        new_text=str(d.get('text','')).strip()
        if not new_text: raise ValueError(f'adopted_empty_text:{rid}')
        obs['effective_text']=new_text
        obs['effective_text_source']='TARGETED_REREAD'
        obs['original_text']=obs.get('text','')
        obs['reread_provenance']={
            'psm':d.get('psm'),
            'original_role_fit':d.get('original_role_fit'),
            'reread_role_fit':d.get('reread_role_fit'),
            'minimum_absolute_fit':d.get('minimum_absolute_fit'),
            'visible_span_selected':d.get('visible_span_selected',False),
        }
        adopted_ids.append(rid)
    out=copy.deepcopy(resolver_result)
    out['observations']=observations
    out['reread_overlay']={
        'schema':'lf-targeted-reread-overlay/v3-candidate',
        'adopted_count':len(adopted_ids),
        'adopted_ids':adopted_ids,
        'original_evidence_mutated':False,
    }
    return out
