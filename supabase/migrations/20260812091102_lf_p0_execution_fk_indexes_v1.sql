-- Cover P0 persistence foreign keys used by reconstruction and integrity checks.

create index lf_p0_execution_artifacts_v1_external_ref_idx
  on private.lf_p0_execution_artifacts_v1(external_evidence_ref)
  where external_evidence_ref is not null;

create index lf_p0_execution_element_evidence_v1_element_idx
  on private.lf_p0_execution_element_evidence_v1(execution_id, element_id);

create index lf_p0_execution_elements_v1_parent_idx
  on private.lf_p0_execution_elements_v1(execution_id, parent_element_id)
  where parent_element_id is not null;

create index lf_p0_execution_persist_attempts_v1_execution_idx
  on private.lf_p0_execution_persist_attempts_v1(execution_id, attempted_at, attempt_id);
