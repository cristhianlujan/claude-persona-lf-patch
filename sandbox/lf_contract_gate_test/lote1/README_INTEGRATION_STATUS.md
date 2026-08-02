# PR #93 · LOTE 1 · estado de integración

## Resultado de las auditorías estáticas

La auditoría del commit `2c97bb5387f4696fc6c9ea912c1a1ca7f31a5fcc` detectó cuatro SQL alternativos que redefinían relaciones de la cadena V7 activa. Esas piezas fueron retiradas y no deben restaurarse.

La auditoría del commit `33cdeaa78b6bb7059d45ae9ea0ecbf5520972fd7` detectó CA-N30 a CA-N35. Fueron atendidos mediante rotación integrada, canonicalización posicional, política explícita del keystore, `key_id` obligatorio, estado de retiro y bloqueo de `TRUNCATE`.

La auditoría del commit `1545c9749ac1f87607f13f6decf8645ebf6a7882` emitió `STATIC_AUDIT_PASS`, pero mantuvo tres correcciones previas al merge:

- CA-N36: ambigüedad por `:` dentro de componentes;
- CA-N37: campos del payload fuera de la firma;
- CA-N38: representación numérica JavaScript/PostgreSQL.

## Integración activa

Rotación:

`supabase/migrations/20260801180400_writer_key_rotation_v7.sql`

Hardening de RLS, lifecycle y canonicalización posicional:

`supabase/migrations/20260801180500_writer_canonicalization_rls_v7.sql`

Binding del payload completo:

`supabase/migrations/20260801180510_writer_full_payload_binding_v7.sql`

`180510` redefine únicamente los helpers de preimage ya utilizados por los writers públicos. No crea una segunda ruta de escritura.

## Contrato final versionado

```text
payload_hash = SHA-256(canonical_json(payload))
preimage = frame(scope) || frame(execution_id) || frame(payload_hash)
frame(value) = utf8_byte_length(value) || "#" || value
signature = HMAC-SHA256(preimage || ":" || nonce)
```

Consecuencias:

- los caracteres `:` en rutas, URLs o textos no alteran límites;
- cualquier campo o valor anidado del payload queda ligado a la firma;
- claves de objetos se restringen al dominio ASCII definido;
- números deben ser enteros seguros de JavaScript;
- Edge y PostgreSQL comparten un vector canónico y SHA-256 conocido;
- Edge no transporta ni necesita conocer `key_id`;
- firmas RPC públicas permanecen sin cambios.

## Archivos de prueba y readback

- `sandbox/lf_contract_gate_test/PR93_WRITER_V7_ADVERSARIAL_TESTS.sql`
- `sandbox/lf_contract_gate_test/PR93_CA_N36_N38_ADVERSARIAL_TESTS.sql`
- `sandbox/lf_contract_gate_test/PR93_EDGE_CANONICAL_PAYLOAD_TEST.ts`
- `sandbox/lf_contract_gate_test/PR93_V7_READBACK.sql`
- `sandbox/lf_contract_gate_test/PR93_V7_HARDENING_READBACK.sql`
- `sandbox/lf_contract_gate_test/PR93_V7_PAYLOAD_BINDING_READBACK.sql`
- `sandbox/lf_contract_gate_test/lote1/PR93_LOTE1_ADVERSARIAL_TESTS.sql`
- `sandbox/lf_contract_gate_test/lote1/PR93_LOTE1_READBACK.sql`

La batería añade colisiones por separador, mutaciones de campos anteriormente no firmados, orden de claves, vector compartido, números fraccionarios y enteros fuera del rango seguro.

## Límite

Todo permanece versionado y sin ejecución runtime. Estos archivos no autorizan despliegue, merge, instalación de claves ni regeneración de baseline.
