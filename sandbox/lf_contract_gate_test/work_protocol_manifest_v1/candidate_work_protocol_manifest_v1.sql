-- DEPRECATED: LF_WORK_PROTOCOL_MANIFEST_V1
-- DO NOT MATERIALIZE OR APPLY.
-- Historical implementation remains available through Git history only.
-- Any direct execution of this tombstone intentionally fails closed.

DO $$
BEGIN
  RAISE EXCEPTION 'WORK_PROTOCOL_V1_DEPRECATED_DO_NOT_USE';
END
$$;
