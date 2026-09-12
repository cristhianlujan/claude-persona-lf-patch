# Frontend Prototype Architect LF — candidate semantic judge

Status: `PASS_CANDIDATE_SEMANTIC_GATE / INDEPENDENT_REAUDIT_REQUIRED`
Execution: `EXEC-ACTUALIZACION-PERFIL-FRONTEND-PROTOTYPE-ARCHITECT-LF-20260827-004`
Audit target: Carril B findings against PR #246.

## Question under judgment
Does the candidate remediation preserve the Frontend Prototype Architect's advisory role while preventing an implementation specification, candidate-supplied flags/hashes, or stale/fictitious upstream references from being misrepresented as a verified created prototype?

## Authority checks
- Existing identity remains `ACT-0051 / frontend_prototype_architect_lf`.
- Product decisions remain upstream authority; this profile does not invent product scope or claims.
- UI hierarchy remains upstream UI Architect authority; this profile does not redefine visual/product authority.
- Shell/adapter constraints already present on baseline main are preserved; `implementation_boundary_contract.md` is not modified by this lot.
- Runtime enablement, production deployment, `VALIDATED`, and automatic promotion remain blocked.

## Semantic properties checked
1. **Advisory capability preserved** — `ADVISORY_SPEC_ONLY` can complete as `ADVISORY_COMPLETE` without pretending a file was created.
2. **Creation claim strengthened** — `CREATE_AND_VERIFY_ARTIFACT` can use `PASS_ARTIFACT_VERIFIED` only after deterministic external workspace readback.
3. **Specification is not artifact evidence** — `files_to_create`, `html_structure`, and `css_structure` alone cannot establish implementation completion.
4. **Upstream provenance is resolved, not trusted** — Product/UI refs must exist in the current workspace and their SHA-256 is recomputed from read bytes.
5. **Candidate booleans are not proof** — `exists`, `readback`, `currentness`, verdict labels, and candidate-provided matching hashes cannot override missing/tampered files or sources.
6. **Direction of failure is safe** — nonexistent/stale/mismatched sources and missing/tampered/unparseable artifacts fail closed rather than being silently accepted.
7. **Score is subordinate to evidence** — a high numeric score cannot substitute for source/artifact verification.

## Regression evidence
The profile-local adversarial matrix executed on the candidate profile blobs and passed 7/7:
- positive real artifact + current Product/UI readback -> PASS;
- empty spec -> FAIL;
- missing artifact -> FAIL;
- tampered artifact/SHA -> FAIL;
- fictitious upstream -> FAIL;
- stale upstream -> FAIL;
- advisory holdout -> PASS without artifact claim.

GitHub Actions evidence: run `33130229085`, job `98717761396`, result `SUCCESS`.

## Router/direct consistency
Both direct invocation and Router-mediated invocation are constrained by the same `SKILL.md`, HTML sandbox contract, schema, deterministic validator and mini-judge. No alternate Router-only artifact-PASS rule is introduced by this patch.

## Candidate verdict
`PASS_CANDIDATE_SEMANTIC_GATE`.

This verdict is not the independent re-audit requested by the campaign. Final `REMEDIATED_VERIFIED` remains reserved for a fresh independent audit after merge/readback.
