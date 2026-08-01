# PR #93 · LOTE 1 · estado de integración

## Resultado de las auditorías estáticas

La auditoría del commit `2c97bb5387f4696fc6c9ea912c1a1ca7f31a5fcc` detectó cuatro SQL alternativos que redefinían relaciones de la cadena V7 activa. Esas piezas fueron retiradas y no deben restaurarse.

La auditoría del commit `33cdeaa78b6bb7059d45ae9ea0ecbf5520972fd7` confirmó la integración de rotación, pero detectó cinco brechas adicionales:

- CA-N30: canonicalización Edge/PostgreSQL con posiciones `NULL` no equivalentes;
- CA-N31: lectura del keystore dependiente de `BYPASSRLS` de `postgres`;
- CA-N32: política de nonces sin obligación estructural de `key_id`;
- CA-N33/CA-N34: retiro pendiente sin causa explícita y asimetría temporal;
- CA-N35: ausencia de bloqueo de `TRUNCATE`.

## Integración activa

La rotación continúa en:

`supabase/migrations/20260801180400_writer_key_rotation_v7.sql`

El hardening posterior está en:

`supabase/migrations/20260801180500_writer_canonicalization_rls_v7.sql`

`180500`:

- mantiene una sola cadena activa;
- sustituye `concat_ws` en los writers mediante helpers de posiciones fijas;
- reproduce las representaciones primitivas usadas por Edge;
- exige booleanos en los dos campos que Edge convierte con `String(...)`;
- crea una política explícita del keystore para `postgres`;
- mantiene RLS/FORCE RLS y cero acceso API;
- exige `key_id` para todo nonce nuevo;
- conserva compatibilidad con nonces históricos;
- completa la restricción temporal de `RETIRED`;
- bloquea `TRUNCATE` en keystore y nonces;
- expone un estado de rotación no secreto.

El contrato HMAC permanece:

```text
HMAC-SHA256(preimage || ':' || nonce)
```

Edge no transporta ni necesita conocer `key_id`.

## Archivos de prueba y readback

- `sandbox/lf_contract_gate_test/PR93_WRITER_V7_ADVERSARIAL_TESTS.sql`
- `sandbox/lf_contract_gate_test/PR93_V7_READBACK.sql`
- `sandbox/lf_contract_gate_test/PR93_V7_HARDENING_READBACK.sql`
- `sandbox/lf_contract_gate_test/lote1/PR93_LOTE1_ADVERSARIAL_TESTS.sql`
- `sandbox/lf_contract_gate_test/lote1/PR93_LOTE1_READBACK.sql`

La batería canónica incluye controles positivos privado y público, replay, expiración, canonicalización posicional, cambio efectivo a `service_role`, protección de `RESET ROLE`, cero efectos sobre nonces/reconciliaciones/eventos y rotación con aceptación doble.

## Límite

Todo permanece versionado y sin ejecución runtime. Estos archivos no autorizan despliegue, merge, instalación de claves ni regeneración de baseline.
