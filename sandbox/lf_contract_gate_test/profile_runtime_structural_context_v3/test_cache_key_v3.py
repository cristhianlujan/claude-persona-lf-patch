#!/usr/bin/env python3
import importlib.util
from pathlib import Path
p=Path(__file__).with_name('cache_key_v3.py');s=importlib.util.spec_from_file_location('c',p);c=importlib.util.module_from_spec(s);s.loader.exec_module(c)
A='a'*64; B='b'*64; C='c'*64
k=c.make_cache_key(image_sha=A,context_sha=B,runtime_version='tesseract-5.5.0-eng+spa-psm3',resolver_version='structural-context-v3.1')
assert k==c.make_cache_key(image_sha=A,context_sha=B,runtime_version='tesseract-5.5.0-eng+spa-psm3',resolver_version='structural-context-v3.1')
assert k!=c.make_cache_key(image_sha=C,context_sha=B,runtime_version='tesseract-5.5.0-eng+spa-psm3',resolver_version='structural-context-v3.1')
assert k!=c.make_cache_key(image_sha=A,context_sha=C,runtime_version='tesseract-5.5.0-eng+spa-psm3',resolver_version='structural-context-v3.1')
assert k!=c.make_cache_key(image_sha=A,context_sha=B,runtime_version='tesseract-5.3.4-eng+spa-psm3',resolver_version='structural-context-v3.1')
assert k!=c.make_cache_key(image_sha=A,context_sha=B,runtime_version='tesseract-5.5.0-eng+spa-psm3',resolver_version='structural-context-v3.2')
assert c.cacheable_payload({'observations':[],'geometry':{}})
for field in ['profile_contract_valid','semantic_utility','downstream_authorized','authorization','quality_verdict']:
 assert not c.cacheable_payload({field:'PASS'}), field
try:c.make_cache_key(image_sha='bad',context_sha=B,runtime_version='x',resolver_version='y');raise AssertionError('bad sha accepted')
except c.CacheKeyError:pass
print('STRUCTURAL_CACHE_KEY_V3_TESTS_PASS 12/12')
