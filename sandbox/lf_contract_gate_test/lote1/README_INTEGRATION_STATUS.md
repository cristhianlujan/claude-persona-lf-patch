# PR #93 · LOTE 1 · estado de integración

## Naturaleza del paquete

Los archivos de este directorio son una propuesta versionada derivada del handoff consolidado. No forman parte de `supabase/migrations/` y no se ejecutan automáticamente.

## No es una migración aditiva

El PR ya contiene objetos V7 con los mismos nombres y una estructura distinta. Por ello, las piezas `20260801_0001` a `20260801_0004` deben evaluarse como una alternativa de diseño que sustituiría la implementación draft correspondiente; no deben ejecutarse encima de la cadena V7 actual sin una migración de integración revisada y probada.

## Integraciones todavía pendientes

1. Adaptar `public.record_external_ci_verification_v7` para usar el `key_id` firmado.
2. Adaptar `public.record_lf_gate_test_v7` para usar el mismo contrato.
3. Actualizar Edge V7 para firmar exactamente:

```text
<preimage> + 0x0a + <writer_token> + 0x0a + <key_id>
```

4. Transportar el `key_id` público junto con la firma, sin transportar la clave.
5. Probar byte a byte los preimages de reconciliación y gate entre Edge y PostgreSQL.
6. Definir la migración que sustituye o transforma los objetos V7 ya versionados.
7. Ejecutar la batería adversarial únicamente en un entorno aislado.

## Interpretación correcta

- El diagnóstico runtime de CA-N22, CA-N23 y CA-N29 proviene del handoff.
- El código de este directorio no tiene evidencia runtime.
- La batería SQL está versionada, pero no ejecutada.
- La presencia de estos archivos no autoriza merge, despliegue, baseline ni modificación del proyecto activo.
