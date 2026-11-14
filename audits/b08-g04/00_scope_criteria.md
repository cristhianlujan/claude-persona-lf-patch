B08 G04 LAB (read-only Supabase; Docker only)

Source normative: audits/rule-quality-lote28/12_criterios_cierre_motor_7.md, branch lf/issue-3779-lote28-blocker-closure-plan-v1. This PR tests the exact public.lf_ig_rule_owner_decide_v2 source shipped in 20261113030000_lf_ig_rule_lifecycle_writer_v2.sql, on isolated PG17.6 and PG18.7 only.

Positive RECHAZAR: six-field documentary record, record hash, source/proposal hash, documentary actor separation, eligible synthetic parent profile, table readback, identity_verified=false (writer output) and identity_mode=UNVERIFIED_CHAT_DECLARATION (table default), then ROLLBACK. Positive APROBAR: exercise official child+promotion entirely within ROLLBACK and assert zero persisted changes. Negative x6: wrong decisor, self-approval, stale source SHA, duplicate decision, malformed date, forged identity_verified=true (seventh field). Extra: out-of-scope timestamp. All negative errors exact and zero rows.

These labs do not certify a real native judge, human signature, or live rule decision. The G04 requirement for a real eligible profile RUN, a real governed decision/receipt in Supabase and actor audit still requires separate authorization and live route. Never call the live writer here. Do not close B08 via this PR.
