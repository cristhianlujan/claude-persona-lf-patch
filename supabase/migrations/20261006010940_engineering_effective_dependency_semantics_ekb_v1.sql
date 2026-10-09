
update public.lf_error_knowledge
set
  titulo='Effective dependency semantics must ignore inactive CANCELLED edges and resolve FUSED through fused_into',
  causa_raiz='Dependency evaluation previously treated every REQUIRES target with status different from DONE as unmet, mixing executable dependencies with cancelled historical work and FUSED indirection.',
  prevencion='Use programacion.fn_engineering_effective_dependencies_v1 as the single dependency predicate. DIRECT active statuses BACKLOG/READY/IN_PROGRESS/IN_REVIEW/BLOCKED remain unmet until DONE. CANCELLED is non-executable and does not block. FUSED resolves through fused_into and blocks only when the effective target is not DONE. Deleted or annulled edges are absent from engineering_work_dependencies and are not evaluated. Bootstrap, derived blockers and checkpoint transition must consume the same helper.',
  validacion='PASS when fn_engineering_unit_bootstrap_v1, fn_engineering_effective_open_blockers_v1 and fn_engineering_checkpoint_transition_v1 all consume fn_engineering_effective_dependencies_v1; CANCELLED evaluates is_unmet=false; FUSED evaluates the fused_into target; global current-state parity shows zero unintended dependency-count drift.',
  evidencia=concat_ws(E'\n',nullif(evidencia,''),'2026-10-05 adjustment: migration engineering_effective_dependency_semantics_v1 created programacion.fn_engineering_effective_dependencies_v1 and rewired bootstrap/blockers/transition. Live parity: 0 changed work_items, max_delta=0; M3.9 remains DONE 100%, unmet_deps=0.'),
  ultima_vez=now(),
  updated_at=now()
where codigo='ENGINEERING-FUSED-DEPENDENCY-RESOLUTION-001';
