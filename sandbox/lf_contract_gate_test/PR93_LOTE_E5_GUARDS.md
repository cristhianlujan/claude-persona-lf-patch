# PR #93 · LOTE-E.5 · Cierre CA-N74 a CA-N76

## Alcance

Este addendum cierra los hallazgos bajos e informativos posteriores a LOTE-E.4 sin
modificar la migración `20260801180530_writer_evidence_runtime_hardening_v7.sql`, el
readback de 25 vectores ni la batería adversarial. No autoriza conexión a Supabase,
ejecución SQL contra el proyecto LF, despliegue Edge, instalación de claves, baseline
o merge.

## Contrato acumulado de evidencia

El cierre requiere ejecutar y conservar los resultados de ambos archivos:

1. `PR93_LOTE_C_EVIDENCE_READBACK.sql`;
2. `PR93_LOTE_E5_FINAL_INTEGRITY_READBACK.sql`.

El primer readback debe publicar simultáneamente:

- `definition_checks.binder_preserves_persisted_effects=true`;
- `definition_checks.binder_definition_digest.matches=true`;
- `definition_checks.binder_mutation_pattern_controls.all_pass=true`;
- `gate_trigger.binds_pinned_function=true`.

El addendum debe publicar `binder_and_trigger_integrity=true`. Ningún campo aislado
sustituye el contrato acumulado.

## CA-N74 · el enlace del trigger forma parte del veredicto compuesto

LOTE-E.4 publicaba `gate_trigger.binds_pinned_function`, pero el booleano principal del
binder no lo consumía. El addendum crea `binder_and_trigger_integrity`, que solo puede
ser `true` cuando se cumplen conjuntamente:

1. el SHA-256 de `pg_proc.prosrc` coincide con el binder versionado;
2. existe exactamente un trigger con el nombre esperado;
3. el trigger está `ENABLE ALWAYS`;
4. es `BEFORE INSERT OR UPDATE`;
5. `tgfoid` apunta exactamente a `private.fn_bind_gate_writer_nonce_v7()`.

La ausencia del binder, la ausencia del trigger, un trigger duplicado, un trigger
homónimo apuntado a otra función o un cuerpo diferente producen `false`.

## CA-N75 · procedimiento reproducible de rotación del digest

El digest esperado es:

`3927d2b5bc724f10d5f3db09ad204e3212060c30242ccab7b9501869d6396293`

No debe editarse por conveniencia ni calcularse desde una copia manual del texto. Ante
un cambio legítimo del binder, el procedimiento obligatorio es:

1. modificar el cuerpo en la migración versionada;
2. aplicar esa migración únicamente en un PostgreSQL o Supabase aislado autorizado;
3. recomputar el valor desde `pg_proc.prosrc` con la consulta canónica:

```sql
select encode(
  extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),
  'hex'
) as prosrc_sha256
from pg_proc p
where p.oid=to_regprocedure('private.fn_bind_gate_writer_nonce_v7()');
```

4. comparar el cuerpo instalado con el cuerpo delimitado por `$function$` en la
   migración;
5. obtener auditoría independiente del cambio y del digest;
6. actualizar, en el mismo commit auditado, las constantes de los readbacks y esta
   documentación;
7. volver a ejecutar los vectores, el readback primario y el addendum final.

Un digest nuevo sin auditoría independiente previa no constituye evidencia válida.

## CA-N76 · prefijo conservador del patrón ARE

El patrón de asignaciones `INTO` usa:

`\m[a-z]*?(?:select|execute|returning|fetch)\M`

El prefijo no voraz restaura en PostgreSQL ARE la captura corta necesaria para terminar
la lista de targets antes de `FROM`, `USING` o `;`. Como efecto conservador puede
reconocer palabras que terminan en esas secuencias, por ejemplo `preselect`.

Este ensanchamiento puede agregar una detección textual, pero no permite ocultar una
mutación ni producir PASS sobre un binder modificado. Los 25 vectores negativos y
positivos siguen siendo el control de regresión de la capa textual, mientras que el pin
exacto de `pg_proc.prosrc` es la barrera fail-closed definitiva.

## Evidencia pendiente

1. auditoría estática independiente del nuevo head;
2. aplicación de migraciones en un entorno Supabase aislado autorizado;
3. ejecución de ambos readbacks y de la batería adversarial completa;
4. test Edge y comparación Edge/PostgreSQL;
5. controles administrativos previos al merge.
