# F3 host integrity harness

Scope: executable pre-provider harness for HOST01/HOST02 and an AUTH-EXEC01
provenance probe. It is independent of the withheld LF F1 enablement migration.

- HOST01_HARNESS proves that the exact downloaded bytes are hashed before the
  provider probe and only equal bytes are passed onward.
- HOST02_HARNESS mutates the bytes while preserving the logical reference and
  proves fail-closed behavior with provider_calls=0 and native_transmitted=false.
- AUTH-EXEC01 captures current GitHub CI test-channel metadata only. It MUST keep
  historical_status=NO_ACREDITADO_HISTORICAMENTE and native_runtime_attested=false.

These tests advance F3-B readiness but do not close HOST01/HOST02 against a real
native host/provider. Final PASS still requires the runtime evidence specified in
docs/saly/creative_factory/F3_COMPILATION_TRANSPORT_PLAN_20261128.md.
