-- IG N-6 / INDEPENDENT_JUDGE prerequisite.
-- INDEPENDENT_ASSURANCE 1.0.0/1.0.1 declared usage.measure = public.lf_independent_assurance_measure_v1; 2.0.0 (current) dropped it,
-- so programacion.fn_engineering_capability_execution_descriptor_v1 returns implementation_ref=null and the transversal compiler blocks
-- with BLOCK_TRANSVERSAL_MEASURE_IMPLEMENTATION_REF_MISSING. 2.0.1 is 2.0.0 plus that single additive field. Nothing else changes.
-- Promotion is guarded by the expected current manifest sha256 of 2.0.0.
INSERT INTO public.lf_capability_version_registry
  (capability_code, version, version_major, version_minor, version_patch, release_state, supersedes_version, manifest,
   source_ref, docs_ref, validator_ref, created_by_execution_id)
SELECT v.capability_code, '2.0.1', 2, 0, 1, 'RELEASED', '2.0.0',
       jsonb_set(jsonb_set(v.manifest, '{version}', '"2.0.1"'), '{usage,measure}', '"public.lf_independent_assurance_measure_v1"'),
       'supabase/migrations/20261009170000_independent_assurance_measure_ref_v2_0_1.sql',
       v.docs_ref, v.validator_ref, 'CLAUDE-N6-IA-MEASURE-REF-20261009'
FROM public.lf_capability_version_registry v
WHERE v.capability_code = 'INDEPENDENT_ASSURANCE' AND v.version = '2.0.0'
  AND NOT EXISTS (SELECT 1 FROM public.lf_capability_version_registry x WHERE x.capability_code = v.capability_code AND x.version = '2.0.1');

SELECT public.fn_lf_capability_promote_v1('INDEPENDENT_ASSURANCE', '2.0.1',
  'bfdd4ca3190c3d3e2529f2bfc48db67d898a772aa0d8a9958a911647b3057843',
  'CLAUDE-N6-IA-MEASURE-REF-20261009',
  'Restore usage.measure dropped in 2.0.0 so the engineering compiler can resolve the read-only measure');
