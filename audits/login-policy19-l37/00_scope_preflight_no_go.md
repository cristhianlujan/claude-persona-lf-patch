# LF Login — policy19 L36/L37, rehearsal only

This PR copies the **seven source files unchanged** from the Login L36 and L37 branches, including the ORIGINAL description-only candidate SQL, synthetic PostgreSQL row fixture and original dual-engine rollback harness. The wrapper in R17 checks exact Git blobs and runs that original Python script in GitHub Actions Docker. No SQL text was rewritten.

Current LF policy in live Supabase via SELECT-only: security_policy_id 19, policy_code SEC-B2B-MFA-FACTOR-ELIGIBILITY, status CANDIDATO; full-row SHA256 f82cf4ed0887d8240e1a20d193a7a3a82f92271334de6eb543e4489ecac21b07.

Description candidate SHA256 expected: 0beb7404a61197b3d2528de19a210350a02ae83a5d7fbc58d57726645173975b. This PR contains NO executable DB migration under supabase/migrations and must NEVER be labeled ready-to-merge by these tests alone.

Eight policy_config conflicts remain; original L36 nine_fields lists 8 CONFLICT and 1 NO_CONFLICT_PRESERVE (admin_profile_ids [1,2]). Config update would need distinct owner-authorized scope and provenance/enum/security tests. Current candidate only changes description and requires config not to change, so same-PR config changes invalidate the guard.

ACT-0001 blocker: public.lf_router_scope_bind_v1 and public.lf_router_scope_receipt_consume_v2 (PR #3807 deployed) are CURRENTLY OWNER_NAME-SPECIFIC: their canonical scope code LF_ACTIVOS_OWNER_NAME_WRITE_V1 only authorizes public.lf_activos.owner_name plus audit fields and explicitly forbids any other business table. Therefore these functions CANNOT attest lf_ops.politicas_seguridad.description or policy_config. A new governed server-bound positive/negative scope and authorized consumer must be defined and tested, via existing Router/Train contract, before policy19 work; route-only receipts have effect_authority=false/downstream_execution_allowed=false and DO NOT grant DB effects. No receipt fabricated and no live writer invoked.

The risk of TEMPORARY description/config contradiction (OTP vs Google SAML/passkey) remains a NO-GO for Merge Train application. Even when PG17.6/18.7 is PASS, real integration with provenance trigger, constraints, exact live migration, policy consumer and security acceptance remains pending.
