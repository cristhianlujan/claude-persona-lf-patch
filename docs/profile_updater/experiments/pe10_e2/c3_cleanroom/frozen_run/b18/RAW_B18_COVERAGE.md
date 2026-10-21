===ROLE_REPORT:COVERAGE BEGIN===

Scope: CURRENT executable dependency surfaces outside the original function-body caller inventory, including DML triggers, SQL rules, scheduled commands, queue dispatch, event triggers, foreign tables, and queue-entry authorization.

Evidence: QUERY_RESULT Q25–Q31, Q32R, Q33, and Q34R. QUERY_ERROR Q32 and QUERY_ERROR Q34 are retained as failed query attempts and contribute no catalog findings.

DML-trigger inventory: Q25 identified 16 enabled triggers across four programacion tables, targeting 11 distinct functions. These are trigger-to-function edges, not ordinary function-body calls. No matching SQL rules were found under Q25's specified lexical search criteria.

Scheduled-job inventory: Q27 identified 11 CURRENT cron jobs: nine configured active and two inactive. Job ID 45, ig-direct-sql-worker-v1, is configured active every 30 seconds and invokes programacion.fn_input_governance_queue_worker_v1() as postgres.

Recorded execution: Q30 identified 26,075 succeeded and one failed scheduler execution records for job 45. Scheduler success cannot be equated with completed governance work.

Worker source: Q28 confirmed the queue worker, OID 242617, is SECURITY DEFINER, owned by postgres, and directly invokes programacion.fn_input_governance_direct_step_v1, OID 242597. It uses a transaction-scoped advisory lock, FOR UPDATE SKIP LOCKED, step limits, and stored error outcomes.

Dispatcher source: Q29 confirmed direct calls to governance readback, Curator materialization, Validator handoff continuation, and auxiliary receipt emitters. The source requires verified handoff evidence for eligible Validator continuation and explicitly returns promotion_authorized=false and production_authorized=false.

Queue-request inventory: Q31 preserved eight individual requests, all DONE. Six had governance result BLOCKED, and two had READY. All eight linked readiness runs were COMPLETED. The two READY requests link to runs 933 and 944; queue completion, run completion, governance readiness, and production authorization remain separate states.

Queue-entry access: Q33 identified four public queue wrappers directly executable by service_role, with no corresponding direct path for anon or authenticated. The five examined internal programacion queue functions are not directly callable by those application roles under combined function/schema privileges.

Queue-table protection: Q34R established that anon, authenticated, and service_role lack schema USAGE and SELECT/INSERT/UPDATE/DELETE on programacion.ig_direct_requests_v1. The table has RLS enabled and no registered policies; postgres has owner access.

Event triggers and foreign tables: Q32R identified six enabled event triggers related to extension lifecycle or DDL notification, with no direct governance target. It found zero registered foreign tables.

Coverage findings: CURRENT governance execution includes a concrete service-role submission → persistent queue → scheduled postgres worker → privileged dispatcher → governance workflow path. It must be represented separately from P0 historical caller edges and CURRENT lexical function-body references.

Negative falsifiers: No direct application-role queue-table path was found. No direct governance event-trigger target or registered foreign table was found. No production or promotion authorization was evidenced by the dispatcher or eight queue results. No duplicated workflow execution was demonstrated by repeated linked run identities.

Constraints preserved: Historical P0 and CURRENT evidence remain separate. Function-body lexical references, trigger edges, scheduler configuration, scheduler attempts, queue outcomes, and governance readiness are distinct evidence classes. False-positive lexical witnesses and individual caller identities remain preserved in the frozen Architecture report.

Unresolved: Historical P0 scheduler configuration; external application and Edge-function consumers; dynamic SQL beyond inspected sources; upstream service-role authorization; completeness of unexamined database schemas and functions; and causal correspondence between individual cron attempts and individual queue requests.

Decision: MEASURE_FIRST. No proven coverage defect requiring database changes. Retain the newly confirmed dependency classes in any subsequent inventory design.

Costs: NO_MEDIDO.

Blindness limitation: Strict role independence cannot be independently attested in this shared conversation.

===ROLE_REPORT:COVERAGE END===
