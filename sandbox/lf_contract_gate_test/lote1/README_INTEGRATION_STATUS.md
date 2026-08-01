# PR #93 · LOTE 1 · estado de integración

## Resultado de la auditoría estática

La auditoría del commit `2c97bb5387f4696fc6c9ea912c1a1ca7f31a5fcc` detectó que las piezas SQL alternativas `20260801_0001` a `20260801_0004` redefinían relaciones ya creadas por la cadena V7 activa. La combinación de estructuras incompatibles con `create table if not exists` podía dejar una migración parcialmente aplicada o una ruta de escritura muerta.

Esas cuatro piezas fueron retiradas del directorio ejecutable. No deben restaurarse ni ejecutarse.

## Integración activa

La capacidad útil del paquete —rotación con aceptación doble temporal— se integró mediante una única migración hacia adelante:

`supabase/migrations/20260801180400_writer_key_rotation_v7.sql`

La migración:

- extiende `private.lf_writer_hmac_keys_v7` sin crear una segunda relación;
- mantiene `postgres` como owner del almacén de claves;
- añade `key_id` público y lifecycle `PREPARED → ACTIVE → RETIRING → RETIRED`;
- conserva el contrato HMAC actual `preimage:nonce`;
- no cambia Edge ni las firmas de los RPC públicos;
- acepta una clave `RETIRING` solo durante una ventana de diez minutos;
- registra en cada nonce qué generación validó la firma;
- mantiene `key_id` nullable para filas anteriores a la migración;
- expone funciones administrativas únicamente a `postgres`;
- mantiene `service_role` sin lectura de la clave ni ejecución de verificadores privados.

## Archivos de prueba y readback

- `sandbox/lf_contract_gate_test/PR93_WRITER_V7_ADVERSARIAL_TESTS.sql`
- `sandbox/lf_contract_gate_test/PR93_V7_READBACK.sql`
- `sandbox/lf_contract_gate_test/lote1/PR93_LOTE1_ADVERSARIAL_TESTS.sql`
- `sandbox/lf_contract_gate_test/lote1/PR93_LOTE1_READBACK.sql`

Las baterías apuntan a la ruta activa `private.fn_consume_writer_proof_v7` y a los writers públicos. La prueba 13 cambia efectivamente a `service_role`, comprueba denegación del keystore y del verificador privado, llama al writer público con una firma fabricada y verifica que no se persista evidencia.

## Límite

Todo permanece versionado y sin ejecución runtime. La presencia de esta migración y de las pruebas no autoriza despliegue, merge, instalación de claves ni regeneración de baseline.
