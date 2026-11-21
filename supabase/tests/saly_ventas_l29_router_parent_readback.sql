-- SALY Ventas L29: read-only inspection of native Router/profile parent authority.
-- An ordinary SALY UI RUN is NOT the authority to write discovery/sales data.
-- This diagnostic never issues, reuses, or approves a RUN.
SELECT
  e.operation_code,e.target_type,e.target_code,e.status,
  e.manifest#>>'{router_profile_handoff,business}' AS business,
  e.manifest#>>'{router_profile_handoff,channel}' AS channel,
  e.manifest#>>'{router_profile_handoff,effect_authority}' AS effect_authority,
  COUNT(*) AS records
FROM public.lf_operation_execution e
WHERE e.manifest#>>'{router_profile_handoff,business}'='SALY'
GROUP BY 1,2,3,4,5,6,7 ORDER BY records DESC,target_code;

-- This is a discovery audit; absence is a BLOCKER for binding and writing.
SELECT operation_code,status FROM public.lf_operation_registry
WHERE operation_code ILIKE '%SALY%'
   OR operation_code ILIKE '%VENTAS%'
   OR operation_code ILIKE '%DISCOVERY%'
ORDER BY operation_code;

-- FK ability only: primary key on canonical operation execution is necessary but
-- not sufficient to establish business, profile, signed router gate, and writer.
SELECT conname,pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid='public.lf_operation_execution'::regclass
  AND contype='p';
