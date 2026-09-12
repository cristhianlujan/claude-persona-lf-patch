#!/usr/bin/env python3
"""Fail-closed semantic AFTER evidence gate for PROFILE_RUNTIME V3.

This module does not execute a model. It only decides whether externally produced candidate
results contain enough exact-artifact evidence to be called semantic AFTER PASS.
"""
from __future__ import annotations
from dataclasses import dataclass, asdict

ARTIFACT_SHA='ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287'
EXPECTED_PROFILES={
 'PERFIL-UI-ARCHITECT',
 'PERFIL-PRODUCT-DIRECTOR-LF',
 'PERFIL-QUALITY-PACK',
}

@dataclass(frozen=True)
class SemanticAfterDecision:
 pass_after: bool
 reasons: tuple[str,...]
 def to_dict(self): return asdict(self)

def evaluate(payload: dict) -> SemanticAfterDecision:
 reasons=[]
 if payload.get('artifact_sha256') != ARTIFACT_SHA:
  reasons.append('ARTIFACT_SHA_MISMATCH')
 results=payload.get('results')
 if not isinstance(results,list) or len(results)!=3:
  reasons.append('RESULT_COUNT_NOT_3')
  results=[] if not isinstance(results,list) else results
 profiles=[x.get('profile_code') for x in results if isinstance(x,dict)]
 if set(profiles)!=EXPECTED_PROFILES or len(profiles)!=3:
  reasons.append('PROFILE_SET_INVALID')
 for item in results:
  if not isinstance(item,dict):
   reasons.append('RESULT_INVALID'); continue
  code=item.get('profile_code','UNKNOWN')
  if item.get('transport_status')!='SUCCEEDED': reasons.append(f'TRANSPORT_NOT_SUCCEEDED:{code}')
  if item.get('contract_valid') is not True: reasons.append(f'CONTRACT_NOT_VALID:{code}')
  if item.get('semantic_utility_valid') is not True: reasons.append(f'SEMANTIC_UTILITY_NOT_VALID:{code}')
  if not item.get('output_sha256'): reasons.append(f'OUTPUT_SHA_MISSING:{code}')
  if not item.get('runtime_observed_ms'): reasons.append(f'RUNTIME_TELEMETRY_MISSING:{code}')
 if payload.get('critical_regressions_count') != 0:
  reasons.append('CRITICAL_REGRESSIONS_NONZERO_OR_UNKNOWN')
 return SemanticAfterDecision(not reasons,tuple(reasons))
