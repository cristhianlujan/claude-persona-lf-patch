# SOURCE_RESOLUTION_POLICY

Política transversal LF que determina qué fuente es operativamente autoritativa antes de leer, comparar o modificar un objeto gobernado.

## Estado

- Asset: `SOURCE_RESOLUTION_POLICY`
- Nombre canónico: `TRANSVERSAL_SOURCE_RESOLUTION_POLICY`
- Policy: `POL-LF-SOURCE-RESOLUTION`
- Versión actual: `v1.4-transversal-supabase-authority-visual-support`
- Estado documental: `VIGENTE`
- Estado operativo: `ACTIVO`
- Inventory status: `ACTIVE_TRANSVERSAL_POLICY`
- Autoridad operacional: Supabase
- Vista canónica de apoyo: `public.v_lf_fuente_operativa`
- No crea un segundo resolver, Router ni catálogo paralelo.

## Propósito

Resolver de forma determinística:

1. cuál es la fuente operacional canónica;
2. cuál es sólo visual, histórica o de apoyo;
3. qué binding exacto debe consumirse;
4. qué fallback está permitido;
5. qué evidencia debe quedar para demostrar la resolución.

La política no decide currentness. Primero se resuelve la fuente; después `CURRENTNESS_AUTHORITY` demuestra que la fuente seleccionada sigue vigente.

## Secuencia transversal

```text
operación real
   |
   v
ACT-0001 / autoridad de operación
   |
   v
SOURCE_RESOLUTION_POLICY
   |
   +-- fuente operacional canónica
   +-- binding exacto
   +-- fallback permitido, si aplica
   +-- policy version / sha
   |
   v
source-resolution receipt
   |
   v
CURRENTNESS_AUTHORITY
   |
   v
preflight / efecto
```

## Regla de autoridad

Una fuente no se vuelve autoritativa porque el caller la declare en JSON.

El preflight debe aceptar únicamente una resolución demostrable contra la policy y el inventario/current registry correspondiente.

Ejemplos:

- Supabase estructurado puede ser autoridad operacional cuando la policy así lo define.
- GitHub exact ref/blob puede ser autoridad de source para código o migration.
- Google Drive / Google Docs pueden ser soporte documental o visual cuando la policy lo permita, pero no sustituyen una autoridad operacional canónica.
- Una fuente histórica puede servir como provenance, no como current operational authority.

## Receipt requerido

Un consumidor enforced debe poder producir y validar un receipt determinístico con, como mínimo:

- `execution_id`
- `operation_code`
- `target_type`
- `target_code`
- `source_family`
- `selected_source_ref`
- `authority_class`
- `canonical_binding`
- `policy_code`
- `policy_version`
- `policy_sha`
- `fallback_used`
- `fallback_rule`
- `resolver_revision`
- `fingerprint_sha256`

El receipt debe quedar ligado a la ejecución y al target exacto. No puede ser un payload libre suministrado por el caller.

## Fallback

Un fallback es válido sólo cuando:

1. la policy lo permite explícitamente;
2. el source primario no está disponible o no aplica;
3. el fallback conserva autoridad suficiente para esa operación;
4. el uso del fallback queda declarado en el receipt;
5. la siguiente fase de currentness puede verificarlo.

Si no existe fallback permitido, la resolución debe fallar cerrada.

## Integración con ACTUALIZACION_DB_LF

Para `ACTUALIZACION_DB_LF`, la resolución de fuente ocurre antes de aceptar `schema_source_readback`.

El preflight no debe considerar suficiente un payload como:

```json
{
  "declared_authority": "GOOGLE_DOCS",
  "canonical_binding": null
}
```

aunque el resto del preflight sea correcto.

Debe existir un receipt server-side válido y luego currentness/readback.

## Fallos y EKB

Si una operación bound detecta:

- source authority inválida;
- binding ausente;
- fallback no permitido;
- source/target mismatch;
- receipt fabricado;
- stale policy binding;
- bypass de source resolution;

el fallo debe entrar por la única ruta productiva:

```text
operation
 -> GATE_CHECK_OBSERVABILITY
 -> public.lf_operation_gate_check_results
 -> PRE_EKB_GATE
 -> ACT-0001
 -> EJECUCION_SKILL_LF
 -> ACT-0057
 -> ESCRITURA_BASE_CONOCIMIENTO_LF
 -> EKB receipt/readback
```

`SOURCE_RESOLUTION_POLICY` no escribe EKB directamente.

## Negativos mínimos

Todo consumidor enforced debe probar al menos:

1. fuente autoritativa válida -> PASS;
2. fuente visual/no autoritativa declarada como operacional -> BLOCK;
3. binding nulo -> BLOCK;
4. target distinto al receipt -> BLOCK;
5. operation distinta al receipt -> BLOCK;
6. policy version/sha stale -> BLOCK;
7. fallback no permitido -> BLOCK;
8. receipt fabricado por caller -> BLOCK;
9. replay de receipt de otra execution -> BLOCK;
10. cambio de fuente después de validar y antes del efecto -> BLOCK + zero effect.

## Readback

Un cierre válido debe demostrar:

- policy actual leída desde Supabase;
- source resolution receipt exacto;
- target y operation coincidentes;
- currentness posterior;
- source ref exacto;
- fallback, si hubo;
- resultado de negativos;
- cero efecto en bypass;
- EKB receipt cuando el negativo reveló un defecto real.

## Cómo agregar un consumidor

No copiar la lógica dentro de cada operación.

1. confirmar que `SOURCE_RESOLUTION_POLICY` está current;
2. declarar el operation/step consumidor;
3. usar el resolver/receipt transversal;
4. agregar enforcement en el preflight de la operación;
5. ejecutar positivos, negativos y adversariales;
6. registrar hallazgos reales por PRE_EKB;
7. actualizar inventario/README sólo si cambia el contrato transversal.

## Separación de responsabilidades

`SOURCE_RESOLUTION_POLICY`:
- decide qué fuente puede ser autoridad;
- selecciona binding/fallback permitido;
- emite identidad de resolución.

No:
- reemplaza Router;
- decide currentness;
- ejecuta el write;
- persiste EKB directamente;
- autoriza una fuente sólo porque el caller la declara.

## Fuente e inventario

Asset lógico:
- `SOURCE_RESOLUTION_POLICY`

Implementación/autoridad:
- `POL-LF-SOURCE-RESOLUTION`
- `public.v_lf_fuente_operativa`

Gap conocido:
- expandir enforcement donde la autoridad de fuente todavía sea operation-local o meramente declarativa.
