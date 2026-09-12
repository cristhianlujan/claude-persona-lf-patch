# PR #93 · Guardas CA-N36 a CA-N38

## Alcance

Esta pieza complementa la migración:

`supabase/migrations/20260801180510_writer_full_payload_binding_v7.sql`

No autoriza despliegue, instalación de claves, merge ni regeneración de baseline.

## Contrato firmado

Edge y PostgreSQL calculan:

```text
payload_hash = SHA-256(canonical_json(payload))
preimage = frame(scope) || frame(execution_id) || frame(payload_hash)
signature = HMAC-SHA256(preimage || ":" || nonce)
frame(value) = utf8_byte_length(value) || "#" || value
```

El payload completo queda ligado a la firma. Una modificación de cualquier campo o valor anidado cambia `payload_hash`.

## JSON canónico

- claves de objetos limitadas a `[A-Za-z0-9_.-]+`;
- claves ordenadas de forma ascendente;
- arrays conservan su orden;
- strings usan escape JSON y UTF-8;
- `null`, booleanos y strings conservan semántica JSON;
- números permitidos únicamente si son enteros seguros de JavaScript:
  - mínimo `-9007199254740991`;
  - máximo `9007199254740991`;
- valores `undefined`, funciones, símbolos, números fraccionarios, `NaN`, infinito y claves no ASCII fallan en cerrado.

## Hallazgos atendidos

### CA-N36

No se usa `:` para separar campos libres. Los tres componentes del preimage se prefijan con su longitud en bytes UTF-8, por lo que `a:b + c` no puede confundirse con `a + b:c`.

### CA-N37

El HMAC ya no autentica un subconjunto del payload. Se firma el SHA-256 del JSON canónico completo, incluidos:

- `artifact_path`;
- `repository` y `target_branch`;
- estados del workflow y merge;
- `artifact_exercised_by_workflow`;
- `failure_reasons`;
- `details` y sus campos anidados;
- efectos persistidos del gate.

### CA-N38

Edge usa `Number.isSafeInteger`. PostgreSQL normaliza enteros equivalentes y rechaza números fraccionarios o fuera del rango seguro. Esto evita diferencias entre `String(number)` y la representación `numeric` de PostgreSQL.

## Vectores compartidos

Payload:

```json
{"z":"a:b","a":[1,true,null,{"k":"ñ"}],"n":1}
```

Representación canónica:

```text
{"a":[1,true,null,{"k":"ñ"}],"n":1,"z":"a:b"}
```

SHA-256:

```text
e6dbf00ab828cd67089efa5d25a5a66011ac7cea845179f9bf997187af77029b
```

Archivos que deben producir el mismo vector:

- `sandbox/lf_contract_gate_test/PR93_CA_N36_N38_ADVERSARIAL_TESTS.sql`
- `sandbox/lf_contract_gate_test/PR93_EDGE_CANONICAL_PAYLOAD_TEST.ts`

## Pruebas obligatorias en entorno aislado

1. Aplicar toda la cadena V7 hasta `180510`.
2. Ejecutar `PR93_CA_N36_N38_ADVERSARIAL_TESTS.sql`.
3. Ejecutar `deno test PR93_EDGE_CANONICAL_PAYLOAD_TEST.ts`.
4. Comparar los preimages completos producidos por Edge y PostgreSQL para un payload real de reconciliación y uno de gate.
5. Ejecutar nuevamente `PR93_WRITER_V7_ADVERSARIAL_TESTS.sql` porque el preimage cambió.
6. Ejecutar `PR93_V7_PAYLOAD_BINDING_READBACK.sql`.
7. Confirmar que `service_role`, `anon` y `authenticated` no ejecutan los helpers privados.
8. Confirmar que una mutación posterior a la firma es rechazada sin consumir evidencia autoritativa.

## Estado

La corrección es únicamente versionada. No constituye evidencia runtime.
