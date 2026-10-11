INSERT INTO transversal.decision_log(adr,titulo,decision,razon,impacto,estado) SELECT
'DEC-IG-M98-RECEIPT-CYCLE-V6-20261011','M9.8 two-phase evidence binding',
'Verified producer is anchored first, independent field decision second, technical gate third. The second references the immutable producer receipt ID. D4 stays blocking; release requires separate authority.',
'Prior producer and decision receipts depended on mutually unavailable generated IDs.',
'Align M9.6-M9.8 technical governance without fabricating evidence or production activation.',
'VIGENTE' WHERE NOT EXISTS(SELECT 1 FROM transversal.decision_log WHERE adr='DEC-IG-M98-RECEIPT-CYCLE-V6-20261011');
UPDATE programacion.engineering_plan_units
SET unit_metadata=jsonb_set(unit_metadata,'{m9_receipt_lifecycle_v6}',jsonb_build_object('producer','FIRST','verified_decision','SECOND','admission','THIRD','consumer_activation',false,'governance','DEC-IG-M98-RECEIPT-CYCLE-V6-20261011'),true)
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code IN ('M9.6','M9.7','M9.8');