-- LOTE 20 - ROLLBACK DRAFT ONLY / NEVER RUN LIVE WITHOUT REVIEW.
-- Data in any new column would be LOST upon applying this DOWN.
-- The PG18 sandbox tests prove reversibility ONLY while new columns are empty.
ALTER TABLE saly.reglas
  DROP COLUMN lifecycle_state,
  DROP COLUMN effective_to,
  DROP COLUMN successor_rule_code,
  DROP COLUMN next_review_at,
  DROP COLUMN reviewed_at;

ALTER TABLE lf_ops.reglas
  DROP COLUMN effective_to,
  DROP COLUMN successor_rule_code,
  DROP COLUMN next_review_at,
  DROP COLUMN reviewed_at;
