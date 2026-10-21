# CANDIDATE X4

Case: PE10-IG-M107-M109-P0 (same case for every candidate). Pair Q: the two candidates of a pair come from the same method family; their order is randomized.
Content below is verbatim producer output; nothing was edited.

### ROLE REPORT: ARCHITECTURE

{
  "schema": "PE10_M29_ROLE_RAW_V1",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M29",
  "definition_version": "PE10_METHOD_V1",
  "role_code": "ARCHITECTURE",
  "base_code": "B",
  "algorithm_codes": [
    "C",
    "E"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "execution_modality": {
    "role_bound_single_context": true,
    "independent_agents_claimed": false,
    "cross_method_results_used": false,
    "peer_reports_read_before_freeze": false
  },
  "findings": [
    {
      "id": "M29-ARQ-F01",
      "claim": "Frozen P0 has 38 distinct callers with no missing caller/hash fields.",
      "evidence_refs": [
        "M29_ARQ_Q01"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-ARQ-F02",
      "claim": "TLP over empirical md5(prosrc) equality reconciles exactly to 38: TRUE 16, FALSE 22, NULL 0, absent 0.",
      "evidence_refs": [
        "M29_ARQ_Q02"
      ],
      "confidence": "HIGH_FOR_EMPIRICAL_COMPARATOR"
    },
    {
      "id": "M29-ARQ-F03",
      "claim": "Changing comparator from md5(prosrc) to md5(pg_get_functiondef()) changes the equality outcome from 16 to 0; all 38 comparator outputs differ.",
      "evidence_refs": [
        "M29_ARQ_Q03"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-ARQ-F04",
      "claim": "Trigger enabled-state TLP reconciles exactly to 21: TRUE 21, FALSE 0, NULL 0, absent 0.",
      "evidence_refs": [
        "M29_ARQ_Q04"
      ],
      "confidence": "HIGH"
    }
  ],
  "algorithm_application": {
    "C": {
      "invariants": [
        {
          "id": "ARQ-I1",
          "type": "PARTITION",
          "statement": "caller_total = TRUE + FALSE + NULL + absent",
          "observed": "38=16+22+0+0",
          "status": "PASS"
        },
        {
          "id": "ARQ-I2",
          "type": "POSITIVE",
          "statement": "All frozen caller identities are populated and distinct.",
          "observed": "38/38 distinct, 0 missing",
          "status": "PASS"
        },
        {
          "id": "ARQ-I3",
          "type": "PARTITION",
          "statement": "trigger_total = TRUE + FALSE + NULL + absent",
          "observed": "21=21+0+0+0",
          "status": "PASS"
        },
        {
          "id": "ARQ-I4",
          "type": "NEGATIVE",
          "statement": "Comparator substitution must not be assumed semantics-preserving.",
          "observed": "16 matches via prosrc vs 0 via functiondef; 38/38 comparator outputs differ",
          "status": "PASS"
        }
      ],
      "metamorphic_tests": [
        {
          "id": "ARQ-MT1",
          "transform": "Substitute md5(pg_get_functiondef()) for md5(prosrc).",
          "expected_relation": "If comparator representation were canonical-equivalent, classification should be invariant.",
          "observed_relation": "Not invariant: 16→0 matches.",
          "result": "COUNTEREXAMPLE_FOUND"
        }
      ],
      "tlp_reconciled": true,
      "solver_used": false,
      "solver_reason": "No compatible QED/SMT verifier was available or necessary for these SQL set/partition invariants.",
      "overfitting_checks": [
        "Do not select comparator because it reproduces a preferred answer.",
        "Treat both comparator outputs as empirical until historical serialization is demonstrated."
      ]
    },
    "E": {
      "state": "VERIFY_FIRST",
      "rationale": "Set partitions are internally consistent, but comparator sensitivity proves that current hash-equality interpretation depends on an unverified representation.",
      "demonstrated_defect": false,
      "potential_falsifiers": [
        "Historical source proves canonical hash serialization.",
        "Governed semantic route verification closes current equivalence independently of hash representation."
      ],
      "reversal_criteria": {
        "to_REPAIR_REQUIRED": "A governed invariant fails on an active route or trigger.",
        "to_NO_ACTION_SUPPORTED": "Canonical representation and semantic equivalence are attested.",
        "to_NEEDS_MORE_EVIDENCE": "Canonical representation remains unavailable."
      }
    }
  },
  "negative_falsifiers": [
    "Do not infer canonical hash method from the comparator that happens to match 16 rows.",
    "Do not treat TLP consistency as proof that the business rule/universe is complete.",
    "Do not infer full trigger semantics from enabled-state partition alone."
  ],
  "unresolved": [
    "Canonical historical hash representation",
    "Current semantic route equivalence",
    "Full trigger semantic equivalence"
  ],
  "next_safe_step": "Prove canonical comparator/semantic equivalence through governed evidence; no runtime mutation.",
  "measured_costs": {
    "select_attempts": 4,
    "successful_selects": 4,
    "query_errors": 0,
    "negative_tests": 3,
    "invariants": 4,
    "metamorphic_tests": 1,
    "production_writes": 0
  },
  "sql_log": [
    {
      "query_id": "M29_ARQ_Q01",
      "status": "SUCCESS",
      "result": {
        "total": 38,
        "distinct_callers": 38,
        "missing_caller": 0,
        "missing_hash": 0
      }
    },
    {
      "query_id": "M29_ARQ_Q02",
      "status": "SUCCESS",
      "result": {
        "total": 38,
        "tlp_true": 16,
        "tlp_false": 22,
        "tlp_null": 0,
        "absent": 0
      }
    },
    {
      "query_id": "M29_ARQ_Q03",
      "status": "SUCCESS",
      "result": {
        "equal_prosrc": 16,
        "equal_functiondef": 0,
        "comparator_outputs_differ": 38
      }
    },
    {
      "query_id": "M29_ARQ_Q04",
      "status": "SUCCESS",
      "result": {
        "total": 21,
        "tlp_true": 21,
        "tlp_false": 0,
        "tlp_null": 0,
        "absent": 0
      }
    }
  ],
  "frozen_at": "2026-10-18T22:50:00Z"
}


### ROLE REPORT: PERFORMANCE

{
  "schema": "PE10_M29_ROLE_RAW_V1",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M29",
  "definition_version": "PE10_METHOD_V1",
  "role_code": "PERFORMANCE",
  "base_code": "B",
  "algorithm_codes": [
    "C",
    "E"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "execution_modality": {
    "role_bound_single_context": true,
    "independent_agents_claimed": false,
    "cross_method_results_used": false,
    "peer_reports_read_before_freeze": false
  },
  "findings": [
    {
      "id": "M29-PERF-F01",
      "claim": "Independent schema discovery identifies readiness, direct-request and validator-chunk timing sources.",
      "evidence_refs": [
        "M29_PERF_Q01"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-PERF-F02",
      "claim": "Curator timing partition reconciles 255=7 null+75 zero+173 positive; Validator reconciles 255=22+99+134.",
      "evidence_refs": [
        "M29_PERF_Q02"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-PERF-F03",
      "claim": "Positive-only p50/p90 are Curator 28,148/115,850.6 ms and Validator 78,758.5/257,428.6 ms.",
      "evidence_refs": [
        "M29_PERF_Q03"
      ],
      "confidence": "HIGH_FOR_DESCRIPTION"
    },
    {
      "id": "M29-PERF-F04",
      "claim": "Chunk component-sum relation partitions 493 rows into 385 greater-than, 10 equal, 98 less-than total duration.",
      "evidence_refs": [
        "M29_PERF_Q04"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-PERF-F05",
      "claim": "All 6 pre-cut direct requests have nonnegative e2e ordering and map to 5 distinct runs.",
      "evidence_refs": [
        "M29_PERF_Q05"
      ],
      "confidence": "HIGH"
    }
  ],
  "algorithm_application": {
    "C": {
      "invariants": [
        {
          "id": "PERF-I1",
          "type": "PARTITION",
          "statement": "Curator total=null+zero+positive",
          "observed": "255=7+75+173",
          "status": "PASS"
        },
        {
          "id": "PERF-I2",
          "type": "PARTITION",
          "statement": "Validator total=null+zero+positive",
          "observed": "255=22+99+134",
          "status": "PASS"
        },
        {
          "id": "PERF-I3",
          "type": "PARTITION",
          "statement": "Chunk total=sum_gt+sum_eq+sum_lt",
          "observed": "493=385+10+98",
          "status": "PASS"
        },
        {
          "id": "PERF-I4",
          "type": "POSITIVE",
          "statement": "finished_at>=requested_at for finished direct requests",
          "observed": "6/6 nonnegative, 0 negative",
          "status": "PASS"
        },
        {
          "id": "PERF-I5",
          "type": "NEGATIVE",
          "statement": "Component sums need not equal duration_ms.",
          "observed": "Only 10/493 equal; 385 greater, 98 less",
          "status": "PASS"
        }
      ],
      "metamorphic_tests": [
        {
          "id": "PERF-MT1",
          "transform": "Replace additive-stage assumption with three-way relation partition.",
          "expected_relation": "If stages were strictly additive, equality would dominate/all.",
          "observed_relation": "Equality only 10/493.",
          "result": "COUNTEREXAMPLE_FOUND"
        }
      ],
      "tlp_reconciled": true,
      "solver_used": false,
      "solver_reason": "Set/count invariants are directly testable in SQL; no compatible SMT/QED verifier used.",
      "overfitting_checks": [
        "Do not convert partition consistency into causal performance proof.",
        "Do not drop null/zero rows to manufacture a preferred performance conclusion."
      ]
    },
    "E": {
      "state": "NEEDS_MORE_EVIDENCE",
      "rationale": "Timing populations reconcile internally, but the invariant checks do not establish zero/null semantics, additive stage semantics, matched cohorts or causal intervention effects.",
      "demonstrated_defect": false,
      "potential_falsifiers": [
        "Authoritative timing contract defines zero/null and overlap semantics.",
        "Controlled matched replay proves or excludes material regression."
      ],
      "reversal_criteria": {
        "to_REPAIR_REQUIRED": "Controlled evidence proves material attributable regression.",
        "to_VERIFY_FIRST": "A governed matched verification protocol is established.",
        "to_NO_ACTION_SUPPORTED": "Matched evidence excludes material regression."
      }
    }
  },
  "negative_falsifiers": [
    "Do not equate partition consistency with causal validity.",
    "Do not assume component additivity.",
    "Do not discard null/zero rows without semantic authority."
  ],
  "unresolved": [
    "Null/zero semantics",
    "Stage overlap semantics",
    "Matched workload/intervention boundary",
    "Request/run reuse semantics"
  ],
  "next_safe_step": "Use canonical timing semantics and matched replay before any performance repair.",
  "measured_costs": {
    "select_attempts": 5,
    "successful_selects": 5,
    "query_errors": 0,
    "negative_tests": 3,
    "invariants": 5,
    "metamorphic_tests": 1,
    "production_writes": 0
  },
  "sql_log": [
    {
      "query_id": "M29_PERF_Q01",
      "status": "SUCCESS",
      "result": "Timing/request tables discovered"
    },
    {
      "query_id": "M29_PERF_Q02",
      "status": "SUCCESS",
      "result": {
        "total": 255,
        "curator_null": 7,
        "curator_zero": 75,
        "curator_positive": 173,
        "validator_null": 22,
        "validator_zero": 99,
        "validator_positive": 134
      }
    },
    {
      "query_id": "M29_PERF_Q03",
      "status": "SUCCESS",
      "result": {
        "curator_p50_positive": 28148,
        "curator_p90_positive": 115850.6,
        "validator_p50_positive": 78758.5,
        "validator_p90_positive": 257428.6
      }
    },
    {
      "query_id": "M29_PERF_Q04",
      "status": "SUCCESS",
      "result": {
        "total": 493,
        "sum_gt": 385,
        "sum_eq": 10,
        "sum_lt": 98
      }
    },
    {
      "query_id": "M29_PERF_Q05",
      "status": "SUCCESS",
      "result": {
        "total": 6,
        "unfinished": 0,
        "nonnegative_e2e": 6,
        "negative_e2e": 0,
        "distinct_runs": 5
      }
    }
  ],
  "frozen_at": "2026-10-18T22:52:00Z"
}


### ROLE REPORT: AUTHORITY

{
  "schema": "PE10_M29_ROLE_RAW_V1",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M29",
  "definition_version": "PE10_METHOD_V1",
  "role_code": "AUTHORITY",
  "base_code": "B",
  "algorithm_codes": [
    "C",
    "E"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "execution_modality": {
    "role_bound_single_context": true,
    "independent_agents_claimed": false,
    "cross_method_results_used": false,
    "peer_reports_read_before_freeze": false
  },
  "findings": [
    {
      "id": "M29-AUT-F01",
      "claim": "Event 20161 is a READBACK_VERIFICADO inventory-only historical snapshot with non-null created_by_execution_id and null migration_batch_id.",
      "evidence_refs": [
        "M29_AUT_Q01"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-AUT-F02",
      "claim": "Current principal is supabase_read_only_user with transaction_read_only=on; it cannot execute IG runtime.",
      "evidence_refs": [
        "M29_AUT_Q02"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-AUT-F03",
      "claim": "Identity partition reconciles 255=0 same+248 different+7 any-null.",
      "evidence_refs": [
        "M29_AUT_Q03"
      ],
      "confidence": "HIGH_FOR_RECORDED_FIELDS"
    },
    {
      "id": "M29-AUT-F04",
      "claim": "Component partition reconciles 255=0 same+247 different+8 any-null.",
      "evidence_refs": [
        "M29_AUT_Q04"
      ],
      "confidence": "HIGH_FOR_RECORDED_FIELDS"
    },
    {
      "id": "M29-AUT-F05",
      "claim": "Event execution-link partition reconciles 1=0 null+0 matched+1 unmatched in public.lf_operation_execution.",
      "evidence_refs": [
        "M29_AUT_Q05"
      ],
      "confidence": "HIGH_FOR_VISIBLE_LEDGER"
    }
  ],
  "algorithm_application": {
    "C": {
      "invariants": [
        {
          "id": "AUT-I1",
          "type": "PARTITION",
          "statement": "Identity total=same+different+any_null",
          "observed": "255=0+248+7",
          "status": "PASS"
        },
        {
          "id": "AUT-I2",
          "type": "PARTITION",
          "statement": "Component total=same+different+any_null",
          "observed": "255=0+247+8",
          "status": "PASS"
        },
        {
          "id": "AUT-I3",
          "type": "PARTITION",
          "statement": "Event linkage total=id_null+matched+unmatched",
          "observed": "1=0+0+1",
          "status": "PASS"
        },
        {
          "id": "AUT-I4",
          "type": "POSITIVE",
          "statement": "Research principal is transaction read-only for this session.",
          "observed": "transaction_read_only=on; can_execute_ig=false",
          "status": "PASS"
        },
        {
          "id": "AUT-I5",
          "type": "NEGATIVE",
          "statement": "Distinct labels/components do not by themselves prove material independence.",
          "observed": "No same pairs, but material principal/session provenance is not present in these fields.",
          "status": "PASS"
        }
      ],
      "metamorphic_tests": [
        {
          "id": "AUT-MT1",
          "transform": "Collapse authority evidence to label inequality only.",
          "expected_relation": "A material-independence conclusion must remain unsupported unless provenance survives the reduction.",
          "observed_relation": "Only label/component inequality remains; material independence is still unproven.",
          "result": "OVERFITTING_REJECTED"
        }
      ],
      "tlp_reconciled": true,
      "solver_used": false,
      "solver_reason": "Partition and privilege invariants directly testable in SQL.",
      "overfitting_checks": [
        "Do not interpret unmatched public ledger as proof of no authority anywhere.",
        "Do not equate label inequality with independent execution."
      ]
    },
    "E": {
      "state": "VERIFY_FIRST",
      "rationale": "Authority partitions are internally consistent, but material Curator/Validator independence and canonical historical event provenance remain unresolved.",
      "demonstrated_defect": false,
      "potential_falsifiers": [
        "Authorized historical ledger matches event execution identity.",
        "Material execution provenance proves separate principals/sessions/inputs."
      ],
      "reversal_criteria": {
        "to_REPAIR_REQUIRED": "A real authority bypass or shared effective principal is proven.",
        "to_NO_ACTION_SUPPORTED": "Canonical provenance and material independence are fully attested.",
        "to_NEEDS_MORE_EVIDENCE": "Required authority provenance remains unavailable."
      }
    }
  },
  "negative_falsifiers": [
    "Do not equate distinct labels with material independence.",
    "Do not infer global lack of authority from one unmatched ledger.",
    "Do not infer system-wide inability from this read-only principal."
  ],
  "unresolved": [
    "Canonical historical authority link",
    "Material Curator/Validator independence",
    "Historical executor namespace"
  ],
  "next_safe_step": "Resolve provenance/material independence through authorized readbacks; no grant widening.",
  "measured_costs": {
    "select_attempts": 5,
    "successful_selects": 5,
    "query_errors": 0,
    "negative_tests": 3,
    "invariants": 5,
    "metamorphic_tests": 1,
    "production_writes": 0
  },
  "sql_log": [
    {
      "query_id": "M29_AUT_Q01",
      "status": "SUCCESS",
      "result": {
        "id": 20161,
        "evento_tipo": "READBACK_VERIFICADO",
        "migration_batch_id": null,
        "created_by_execution_id": "CHATGPT-IG-M10.9-20261004-001"
      }
    },
    {
      "query_id": "M29_AUT_Q02",
      "status": "SUCCESS",
      "result": {
        "current_user": "supabase_read_only_user",
        "transaction_read_only": "on",
        "can_execute_ig": false,
        "can_transition_checkpoint": true
      }
    },
    {
      "query_id": "M29_AUT_Q03",
      "status": "SUCCESS",
      "result": {
        "total": 255,
        "both_same": 0,
        "both_different": 248,
        "any_null": 7
      }
    },
    {
      "query_id": "M29_AUT_Q04",
      "status": "SUCCESS",
      "result": {
        "total": 255,
        "both_same": 0,
        "both_different": 247,
        "any_null": 8
      }
    },
    {
      "query_id": "M29_AUT_Q05",
      "status": "SUCCESS",
      "result": {
        "total_events": 1,
        "id_null": 0,
        "matched": 0,
        "unmatched": 1
      }
    }
  ],
  "frozen_at": "2026-10-18T22:54:00Z"
}


### ROLE REPORT: COVERAGE

{
  "schema": "PE10_M29_ROLE_RAW_V1",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M29",
  "definition_version": "PE10_METHOD_V1",
  "role_code": "COVERAGE",
  "base_code": "B",
  "algorithm_codes": [
    "C",
    "E"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "execution_modality": {
    "role_bound_single_context": true,
    "independent_agents_claimed": false,
    "cross_method_results_used": false,
    "peer_reports_read_before_freeze": false
  },
  "findings": [
    {
      "id": "M29-COV-F01",
      "claim": "Frozen P0 inventories are internally deduplicated: 38 callers, 21 triggers and 6 external entries.",
      "evidence_refs": [
        "M29_COV_Q01"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-COV-F02",
      "claim": "All 38 frozen caller names currently resolve; partition reconciles 38=38 resolved+0 absent.",
      "evidence_refs": [
        "M29_COV_Q02"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-COV-F03",
      "claim": "Bounded current pattern scan decomposes 75 candidates into 27 overlap+48 outside-P0, while P0 decomposes 38 into 27 overlap+11 outside-pattern.",
      "evidence_refs": [
        "M29_COV_Q03"
      ],
      "confidence": "HIGH_FOR_BOUNDED_PATTERN"
    },
    {
      "id": "M29-COV-F04",
      "claim": "Trigger enabled-state TLP reconciles 21=21 TRUE+0 FALSE+0 NULL+0 absent.",
      "evidence_refs": [
        "M29_COV_Q04"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-COV-F05",
      "claim": "Pre-cut readiness rows span 42 screens and family_count is invariant at 47; this does not by itself reproduce the governed receipt cohort.",
      "evidence_refs": [
        "M29_COV_Q05"
      ],
      "confidence": "HIGH_FOR_RAW_RELATION"
    }
  ],
  "algorithm_application": {
    "C": {
      "invariants": [
        {
          "id": "COV-I1",
          "type": "SET",
          "statement": "P0 inventory dedupe cardinalities equal totals.",
          "observed": "38/38 callers, 21/21 triggers, 6/6 external",
          "status": "PASS"
        },
        {
          "id": "COV-I2",
          "type": "PARTITION",
          "statement": "P0 caller total=resolved+absent",
          "observed": "38=38+0",
          "status": "PASS"
        },
        {
          "id": "COV-I3",
          "type": "SET_DECOMPOSITION",
          "statement": "candidate_total=overlap+candidate_outside_P0",
          "observed": "75=27+48",
          "status": "PASS"
        },
        {
          "id": "COV-I4",
          "type": "SET_DECOMPOSITION",
          "statement": "P0_total=overlap+P0_outside_candidate",
          "observed": "38=27+11",
          "status": "PASS"
        },
        {
          "id": "COV-I5",
          "type": "PARTITION",
          "statement": "trigger total=TRUE+FALSE+NULL+absent",
          "observed": "21=21+0+0+0",
          "status": "PASS"
        },
        {
          "id": "COV-I6",
          "type": "NEGATIVE",
          "statement": "Raw screen/family relation must not be substituted for governed cohort without predicate reproduction.",
          "observed": "42 screens with constant family_count=47, but no governed inclusion predicate in this query.",
          "status": "PASS"
        }
      ],
      "metamorphic_tests": [
        {
          "id": "COV-MT1",
          "transform": "Change population from frozen P0 to bounded current name-pattern candidates.",
          "expected_relation": "A complete universe claim should be stable only if the selector is authoritative.",
          "observed_relation": "Sets differ materially: 48 candidate-only and 11 P0-only.",
          "result": "COUNTEREXAMPLE_FOUND"
        }
      ],
      "tlp_reconciled": true,
      "solver_used": false,
      "solver_reason": "Set/partition invariants directly testable in SQL.",
      "overfitting_checks": [
        "Do not treat bounded name pattern as authoritative current universe.",
        "Do not use raw 42-screen count as governed receipt denominator."
      ]
    },
    "E": {
      "state": "VERIFY_FIRST",
      "rationale": "Historical coverage sets reconcile internally, but selector metamorphism shows bounded current discovery and frozen P0 are not interchangeable; current totality remains unverified.",
      "demonstrated_defect": false,
      "potential_falsifiers": [
        "Authorized current universe manifest classifies all complements/exclusions.",
        "Exact governed receipt predicate reproduces the intended historical cohort."
      ],
      "reversal_criteria": {
        "to_REPAIR_REQUIRED": "A material in-scope consumer/trigger is proven omitted.",
        "to_NO_ACTION_SUPPORTED": "Current universe and governed cohort reconcile with no material omission.",
        "to_NEEDS_MORE_EVIDENCE": "Authoritative universe predicate remains unavailable."
      }
    }
  },
  "negative_falsifiers": [
    "Do not equate frozen completeness with current completeness.",
    "Do not equate pattern candidates with runtime consumers.",
    "Do not replace governed cohort with raw relation counts."
  ],
  "unresolved": [
    "Current governed universe predicate",
    "Materiality of 48 candidate-only objects",
    "Reason for 11 P0-only callers",
    "Exact governed receipt cohort predicate"
  ],
  "next_safe_step": "Use an authorized current-universe manifest and exact receipt predicate; no runtime mutation.",
  "measured_costs": {
    "select_attempts": 5,
    "successful_selects": 5,
    "query_errors": 0,
    "negative_tests": 3,
    "invariants": 6,
    "metamorphic_tests": 1,
    "production_writes": 0
  },
  "sql_log": [
    {
      "query_id": "M29_COV_Q01",
      "status": "SUCCESS",
      "result": {
        "callers": 38,
        "callers_distinct": 38,
        "triggers": 21,
        "triggers_distinct": 21,
        "external_entries": 6,
        "external_distinct": 6
      }
    },
    {
      "query_id": "M29_COV_Q02",
      "status": "SUCCESS",
      "result": {
        "total": 38,
        "resolved": 38,
        "absent": 0
      }
    },
    {
      "query_id": "M29_COV_Q03",
      "status": "SUCCESS",
      "result": {
        "cand_total": 75,
        "overlap": 27,
        "cand_outside_p0": 48,
        "p0_total": 38,
        "p0_outside_cand": 11
      }
    },
    {
      "query_id": "M29_COV_Q04",
      "status": "SUCCESS",
      "result": {
        "total": 21,
        "tlp_true": 21,
        "tlp_false": 0,
        "tlp_null": 0,
        "absent": 0
      }
    },
    {
      "query_id": "M29_COV_Q05",
      "status": "SUCCESS",
      "result": {
        "pre_cut_screens": 42,
        "family_count_values": 1,
        "min_family_count": 47,
        "max_family_count": 47
      }
    }
  ],
  "frozen_at": "2026-10-18T22:56:00Z"
}


### ROLE REPORT: INNOVATION

{
  "schema": "PE10_M29_ROLE_RAW_V1",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M29",
  "definition_version": "PE10_METHOD_V1",
  "role_code": "INNOVATION",
  "base_code": "B",
  "algorithm_codes": [
    "C",
    "E"
  ],
  "source_cutoff": "2026-10-15T00:00:00Z",
  "execution_modality": {
    "role_bound_single_context": true,
    "independent_agents_claimed": false,
    "cross_method_results_used": false,
    "peer_reports_read_before_freeze": false
  },
  "findings": [
    {
      "id": "M29-INN-F01",
      "claim": "The bounded related-function surface contains 75 functions: 10 cached, 4 context, 1 manifest and 4 receipt-named.",
      "evidence_refs": [
        "M29_INN_Q01"
      ],
      "confidence": "HIGH_FOR_QUERY_RULE"
    },
    {
      "id": "M29-INN-F02",
      "claim": "Exact raw-body and whitespace-normalized duplicate grouping both produce 2 groups containing 5 functions.",
      "evidence_refs": [
        "M29_INN_Q02"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-INN-F03",
      "claim": "Among 16 manifest/receipt-related functions, volatility partitions into 1 immutable, 4 stable and 11 volatile; 9 are executable by current principal, including 5 volatile.",
      "evidence_refs": [
        "M29_INN_Q03"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-INN-F04",
      "claim": "track_functions=none with zero function-stat rows/calls, so zero stats are non-informative about runtime use.",
      "evidence_refs": [
        "M29_INN_Q04"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-INN-F05",
      "claim": "Frozen static graph has 38 callers and 76 declared edges, max out-degree 5 and no zero-callee caller.",
      "evidence_refs": [
        "M29_INN_Q05"
      ],
      "confidence": "HIGH_FOR_STATIC_GRAPH"
    }
  ],
  "algorithm_application": {
    "C": {
      "invariants": [
        {
          "id": "INN-I1",
          "type": "PARTITION",
          "statement": "Manifest/receipt volatility total=immutable+stable+volatile",
          "observed": "16=1+4+11",
          "status": "PASS"
        },
        {
          "id": "INN-I2",
          "type": "POSITIVE",
          "statement": "Existing evidence-related surfaces exist before proposing a new subsystem.",
          "observed": "75 related functions incl. cache/context/manifest/receipt surfaces",
          "status": "PASS"
        },
        {
          "id": "INN-I3",
          "type": "METAMORPHIC",
          "statement": "Whitespace normalization should not create spurious duplicate-body groups in this set.",
          "observed": "raw and normalized both 2 groups/5 functions",
          "status": "PASS"
        },
        {
          "id": "INN-I4",
          "type": "NEGATIVE",
          "statement": "EXECUTE privilege is not equivalent to read-only safety for volatile functions.",
          "observed": "5 executable functions are volatile",
          "status": "PASS"
        },
        {
          "id": "INN-I5",
          "type": "NEGATIVE",
          "statement": "Zero pg_stat_user_functions rows cannot imply zero use when track_functions=none.",
          "observed": "track_functions=none, stats_rows=0",
          "status": "PASS"
        },
        {
          "id": "INN-I6",
          "type": "NEGATIVE",
          "statement": "Static declared graph cannot establish runtime frequency/criticality.",
          "observed": "38 callers/76 edges only",
          "status": "PASS"
        }
      ],
      "metamorphic_tests": [
        {
          "id": "INN-MT1",
          "transform": "Whitespace-normalize function bodies before duplicate grouping.",
          "expected_relation": "If duplicates are formatting artifacts only, grouping changes.",
          "observed_relation": "No change: 2 groups/5 functions both ways.",
          "result": "INVARIANT_HELD"
        }
      ],
      "tlp_reconciled": true,
      "solver_used": false,
      "solver_reason": "Catalog/count invariants directly testable in SQL.",
      "overfitting_checks": [
        "Do not infer deletion safety from duplicate body equality.",
        "Do not invoke volatile evidence functions merely because EXECUTE is granted.",
        "Do not infer non-use from disabled statistics."
      ]
    },
    "E": {
      "state": "NO_ACTION_SUPPORTED",
      "rationale": "No runtime defect is demonstrated. Existing evidence surfaces and duplicate variants warrant verification/reuse before any new subsystem or deletion.",
      "demonstrated_defect": false,
      "potential_falsifiers": [
        "Compatibility ownership proves one duplicate variant unsafe/obsolete.",
        "Authorized safe manifest readback reveals material inconsistency.",
        "Governed runtime telemetry contradicts static graph assumptions."
      ],
      "reversal_criteria": {
        "to_REPAIR_REQUIRED": "A material current inconsistency or unsafe duplicate is proven.",
        "to_VERIFY_FIRST": "Existing safe evidence surfaces can close a bounded gap.",
        "to_NEEDS_MORE_EVIDENCE": "Safe evidence inputs/authority remain unavailable."
      }
    }
  },
  "negative_falsifiers": [
    "Do not delete duplicate variants based on body equality alone.",
    "Do not invoke volatile functions solely due EXECUTE.",
    "Do not infer zero use from disabled stats.",
    "Do not infer runtime criticality from static edges."
  ],
  "unresolved": [
    "Compatibility ownership for duplicate groups",
    "Safe manifest inputs",
    "Governed runtime-edge evidence"
  ],
  "next_safe_step": "Reuse authorized safe evidence surfaces first; no runtime subsystem or duplicate removal.",
  "measured_costs": {
    "select_attempts": 5,
    "successful_selects": 5,
    "query_errors": 0,
    "negative_tests": 4,
    "invariants": 6,
    "metamorphic_tests": 1,
    "production_writes": 0
  },
  "sql_log": [
    {
      "query_id": "M29_INN_Q01",
      "status": "SUCCESS",
      "result": {
        "related_functions": 75,
        "cached_functions": 10,
        "context_functions": 4,
        "manifest_functions": 1,
        "receipt_functions": 4
      }
    },
    {
      "query_id": "M29_INN_Q02",
      "status": "SUCCESS",
      "result": {
        "raw_duplicate_groups": 2,
        "raw_functions_in_groups": 5,
        "normalized_duplicate_groups": 2,
        "normalized_functions_in_groups": 5
      }
    },
    {
      "query_id": "M29_INN_Q03",
      "status": "SUCCESS",
      "result": {
        "total": 16,
        "immutable_count": 1,
        "stable_count": 4,
        "volatile_count": 11,
        "executable_count": 9,
        "executable_volatile": 5
      }
    },
    {
      "query_id": "M29_INN_Q04",
      "status": "SUCCESS",
      "result": {
        "track_functions": "none",
        "stats_rows": 0,
        "calls": 0
      }
    },
    {
      "query_id": "M29_INN_Q05",
      "status": "SUCCESS",
      "result": {
        "callers": 38,
        "declared_edges": 76,
        "max_declared_out_degree": 5,
        "zero_declared_callees": 0
      }
    }
  ],
  "frozen_at": "2026-10-18T22:58:00Z"
}


### SYNTHESIS

{
  "schema": "PE10_M29_SYNTHESIS_V1",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M29",
  "definition_version": "PE10_METHOD_V1",
  "base_code": "B",
  "algorithm_codes": [
    "C",
    "E"
  ],
  "synthesizer_contract": {
    "inputs": "Only the five separately frozen M29 role RAW files.",
    "role_bound_single_context": true,
    "independent_agents_claimed": false,
    "cross_method_results_used": false,
    "voting_used": false,
    "reconciliation_rule": "Resolve by invariant scope, metamorphic counterexamples, provenance and falsifiers; never by majority."
  },
  "frozen_role_inputs": [
    {
      "role_code": "ARCHITECTURE",
      "blob_sha": "0e0a67b0201fb2a6f2da3078d0edb145ca23cbaa",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M29_roles/ARCHITECTURE_RAW_V1.json"
    },
    {
      "role_code": "PERFORMANCE",
      "blob_sha": "dbb1207c8851d146252b691e05a9526361503710",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M29_roles/PERFORMANCE_RAW_V1.json"
    },
    {
      "role_code": "AUTHORITY",
      "blob_sha": "68025c383816c06ba717f3e207bb9d2c94b6b713",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M29_roles/AUTHORITY_RAW_V1.json"
    },
    {
      "role_code": "COVERAGE",
      "blob_sha": "ac04186e6aaff50ebb24c6ea78ad1ec3a8210781",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M29_roles/COVERAGE_RAW_V1.json"
    },
    {
      "role_code": "INNOVATION",
      "blob_sha": "de07ac22541b4a49b62992978786ee8d80b07d8b",
      "path": "docs/profile_updater/experiments/pe10_methods32_p0/M29_roles/INNOVATION_RAW_V1.json"
    }
  ],
  "role_states": {
    "ARCHITECTURE": "VERIFY_FIRST",
    "PERFORMANCE": "NEEDS_MORE_EVIDENCE",
    "AUTHORITY": "VERIFY_FIRST",
    "COVERAGE": "VERIFY_FIRST",
    "INNOVATION": "NO_ACTION_SUPPORTED"
  },
  "reconciliation": [
    {
      "id": "M29-SYN-RC01",
      "issue": "All SQL partitions reconcile, yet current semantic equivalence remains open.",
      "resolution": "Partition consistency validates the measured sets, not the missing business/currentness rule. The comparator metamorphic test proves hash interpretation is representation-sensitive."
    },
    {
      "id": "M29-SYN-RC02",
      "issue": "Performance invariants pass while causal performance remains unresolved.",
      "resolution": "Internal arithmetic/set consistency is necessary but not sufficient for clock semantics or matched causal comparison."
    },
    {
      "id": "M29-SYN-RC03",
      "issue": "Authority identity/component partitions show separation in recorded fields, but material independence is not proved.",
      "resolution": "Preserve field-level invariant only; require execution provenance for material independence."
    },
    {
      "id": "M29-SYN-RC04",
      "issue": "Innovation finds stable duplicate-body grouping and existing evidence surfaces.",
      "resolution": "That supports reuse-first verification, not deletion or runtime intervention."
    }
  ],
  "integrated_findings": [
    {
      "id": "M29-SYN-F01",
      "claim": "P0 caller/trigger populations are internally consistent and current names structurally resolve; TLP/set partitions reconcile exactly.",
      "support": [
        "M29-ARQ-F01",
        "M29-ARQ-F02",
        "M29-ARQ-F04",
        "M29-COV-F01",
        "M29-COV-F02",
        "M29-COV-F04"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-SYN-F02",
      "claim": "Hash equality is comparator-sensitive: md5(prosrc) yields 16 matches while md5(pg_get_functiondef()) yields 0, so no canonical historical hash method is established by coincidence alone.",
      "support": [
        "M29-ARQ-F03"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-SYN-F03",
      "claim": "Bounded current candidate and frozen P0 sets are not interchangeable: 75=27 overlap+48 outside, while 38=27 overlap+11 outside-pattern.",
      "support": [
        "M29-COV-F03"
      ],
      "confidence": "HIGH_FOR_BOUNDED_PATTERN"
    },
    {
      "id": "M29-SYN-F04",
      "claim": "Timing partitions and nonnegative request ordering are internally consistent, but chunk additivity fails as a general invariant and causal performance remains unproven.",
      "support": [
        "M29-PERF-F02",
        "M29-PERF-F03",
        "M29-PERF-F04",
        "M29-PERF-F05"
      ],
      "confidence": "HIGH"
    },
    {
      "id": "M29-SYN-F05",
      "claim": "Recorded identity/component partitions reconcile and show no equal non-null pairs, but canonical authority linkage and material execution independence are not established.",
      "support": [
        "M29-AUT-F03",
        "M29-AUT-F04",
        "M29-AUT-F05"
      ],
      "confidence": "HIGH_FOR_RECORDED_FIELDS"
    },
    {
      "id": "M29-SYN-F06",
      "claim": "Existing evidence surfaces and stable duplicate-body grouping support reuse-first verification; no runtime repair or duplicate deletion is justified.",
      "support": [
        "M29-INN-F01",
        "M29-INN-F02",
        "M29-INN-F03",
        "M29-INN-F04",
        "M29-INN-F05"
      ],
      "confidence": "MEDIUM_HIGH"
    }
  ],
  "algorithm_application": {
    "C": {
      "executed": true,
      "invariant_count": 26,
      "metamorphic_test_count": 5,
      "all_partition_arithmetic_reconciled": true,
      "cross_role_metamorphic_tests": [
        {
          "id": "SYN-MT1",
          "transform": "Hash comparator prosrc→functiondef",
          "result": "COUNTEREXAMPLE_FOUND",
          "effect": "Blocks canonical-hash inference from empirical match rate."
        },
        {
          "id": "SYN-MT2",
          "transform": "Stage timing additive assumption→three-way relation partition",
          "result": "COUNTEREXAMPLE_FOUND",
          "effect": "Blocks additive decomposition."
        },
        {
          "id": "SYN-MT3",
          "transform": "Material-independence claim→label-only evidence reduction",
          "result": "OVERFITTING_REJECTED",
          "effect": "Blocks independence claim from labels alone."
        },
        {
          "id": "SYN-MT4",
          "transform": "Frozen P0 selector→bounded current name-pattern selector",
          "result": "COUNTEREXAMPLE_FOUND",
          "effect": "Blocks selector interchangeability/closed-world claim."
        },
        {
          "id": "SYN-MT5",
          "transform": "Raw body duplicate grouping→whitespace-normalized grouping",
          "result": "INVARIANT_HELD",
          "effect": "Shows duplicate grouping is not merely whitespace-induced, but does not prove deletion safety."
        }
      ],
      "solver_used": false,
      "solver_reason": "All implemented checks were SQL set/partition/metamorphic invariants; no compatible QED/VeriEQL/SMT verifier was available or required.",
      "overfitting_checks": [
        "TLP consistency cannot prove a missing business/currentness rule.",
        "Comparator yielding preferred matches is not privileged without canonical provenance.",
        "Distinct labels are not material independence.",
        "Pattern candidates are not automatically runtime universe.",
        "Duplicate bodies are not automatically safe to remove."
      ]
    },
    "E": {
      "executed": true,
      "state": "VERIFY_FIRST",
      "rationale": "No material runtime defect is demonstrated. Invariants expose important representation/selector/semantics limits that require governed verification before either repair or no-action closure. Performance remains NEEDS_MORE_EVIDENCE within this path.",
      "demonstrated_defect": false,
      "implemented_repair": false,
      "runtime_modified": false,
      "potential_falsifiers": [
        "Canonical historical hash serialization is demonstrated and current semantic equivalence is attested.",
        "Authorized current universe manifest reconciles material consumers/exclusions.",
        "Canonical provenance proves authority and material Curator/Validator independence.",
        "Controlled matched performance replay proves or excludes a material regression."
      ],
      "reversal_criteria": {
        "to_REPAIR_REQUIRED": "A governed invariant/currentness verification proves a material active defect.",
        "to_NO_ACTION_SUPPORTED": "Currentness, coverage, authority and performance unknowns close without material defect.",
        "to_NEEDS_MORE_EVIDENCE": "Required governed evidence remains inaccessible or ambiguous."
      }
    }
  },
  "chosen_repair": {
    "immediate": "NO_RUNTIME_REPAIR",
    "next_verification": [
      "CANONICAL_HASH_AND_CURRENT_SEMANTIC_ATTESTATION",
      "CURRENT_UNIVERSE_MANIFEST",
      "AUTHORITY_AND_MATERIAL_INDEPENDENCE_READBACK",
      "MATCHED_PERFORMANCE_VERIFICATION"
    ]
  },
  "constraints_preserved": [
    "READ_ONLY research",
    "No production/runtime mutation",
    "No grant widening",
    "P0 historical facts separated from post-cut observations",
    "Five role RAWs frozen before synthesis",
    "No independent-agent claim",
    "No cross-method result input",
    "No domain READY/DONE claim"
  ],
  "unresolved": [
    "Canonical historical hash serialization",
    "Current semantic equivalence",
    "Authoritative current consumer universe",
    "Canonical historical authority link",
    "Material Curator/Validator independence",
    "Timing semantics and matched intervention boundary"
  ],
  "measured_costs": {
    "producer_select_attempts": 24,
    "producer_successful_selects": 24,
    "producer_query_errors": 0,
    "negative_falsifiers": 16,
    "invariants": 26,
    "metamorphic_tests": 5,
    "producer_files": 5,
    "production_writes": 0,
    "tokens": "NO_MEDIDO"
  },
  "final_state": "VERIFY_FIRST",
  "synthesized_at": "2026-10-18T23:00:00Z"
}

