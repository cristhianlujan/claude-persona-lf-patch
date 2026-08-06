# PR93 · Production readiness P0 · quarantine `run-creacion-perfil-lf`

## Objective

Stop unauthenticated disclosure of internal profile-creation contracts and destination configuration while a governed caller and minimum data contract are designed.

## Baseline

The deployed version 14:

- used `verify_jwt=false`;
- allowed wildcard CORS;
- created a Supabase client with `SUPABASE_SERVICE_ROLE_KEY`;
- returned internal operation contracts, steps, destinations and configuration;
- did not authenticate the caller;
- had no governed execution evidence after June 6, 2026.

## Quarantine behavior

The replacement:

- must be deployed with `verify_jwt=true`;
- additionally requires an exact bearer match to `SUPABASE_SERVICE_ROLE_KEY`;
- accepts only POST and OPTIONS;
- has no wildcard CORS;
- returns `Cache-Control: no-store`;
- creates no Supabase client;
- performs no database or external network access;
- returns HTTP 503 with `TEMPORARILY_DISABLED_PENDING_SECURE_REDESIGN` even for a valid service-role caller.

## Why quarantine instead of compatibility

No current governed caller has been demonstrated. Preserving anonymous access for hypothetical compatibility would retain a verified information-disclosure path. The endpoint will remain unavailable until all of the following are defined:

1. caller identity and authentication mechanism;
2. exact input schema;
3. minimum output fields;
4. authorization by operation and destination;
5. logging and rate limits;
6. positive and negative runtime tests;
7. rollback and support owner.

## Required runtime negatives

After sandbox deployment:

- no Authorization header → gateway HTTP 401;
- malformed bearer → gateway HTTP 401;
- ordinary user JWT → function-level HTTP 403;
- valid service-role bearer → HTTP 503 quarantine response and `data_accessed=false`.

The first two cases can be executed without exposing any credential. The latter two require controlled credential facilities and remain pending if those facilities are unavailable.

## Excluded

This lot does not redesign profile creation, restore the endpoint, authorize production use, merge to `main`, or grant `RUNTIME_PASS` / `PRODUCTION_READINESS_PASS`.
