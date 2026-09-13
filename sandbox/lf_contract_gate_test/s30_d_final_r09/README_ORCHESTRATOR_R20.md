# S30 R20 — ORQUESTACION_ESTRATEGIAS_LF source candidate

Bounded non-production source package for the Strategy Portfolio Orchestrator.

Authority boundary:
- parent supervises portfolio control only;
- each strategy target is delegated to one `EJECUCION_ESTRATEGIA_LF` child;
- parent cannot perform multi-target business writes;
- `ORQUESTACION_PIPELINE_LF` identity/state authority reuse is forbidden;
- blocked child does not suppress unrelated safe children;
- checkpoint/readback/report are mandatory before close;
- runtime, scheduler, production and business-effect dispatch remain off.

Current gate sequence:
1. source exact-head CI;
2. governed S30 broker promotion;
3. PR/main source readback;
4. candidate-only Supabase registration;
5. controlled no-business-effect canary / C08;
6. bounded Strategy 30 snapshot reconciliation and final non-production closeout.
