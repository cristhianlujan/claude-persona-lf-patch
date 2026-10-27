# PE10A_CT01 — Paquete para el revisor independiente (ronda 2)

Fecha: 2026-10-27 · Repo `cristhianlujan/claude-persona-lf-patch` en `main` = `e3231f9816f8d95db02bd32df32dfe63a1349aa6` · Supabase `mhwmirqcgxxukpctffuv`
Plan `PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1`, unidad `PE10A_CONTRACTS`, checkpoint `PE10A_CT01` (**PENDING**).
Sustituye al paquete V1. Ronda 1 (revisor GPT): FAIL por 3 superficies SQL omitidas; el productor las verificó y las incorporó (ver sección 5.8 del inventario).

## 0. Reglas para el revisor
1. **No eres el productor.** No reutilices sus resultados: vuelve a ejecutar cada comprobación. Un PASS copiado de este documento no vale.
2. Solo lectura. No escribas en Supabase ni en GitHub. No actives Profile Updater v0.2.
3. Si algo no se puede comprobar, di `NO_VERIFICADO`. No lo rellenes.
4. Si no puedes ejecutar el script Python, replica su comparación en SQL y dilo; eso es válido (así se hizo en la ronda 1).

## 1. Decisión de alcance del dueño (obligatoria de respetar)
El router y su encadenamiento **se ven al final, en la integración**. CT01 se evalúa solo sobre el funcionamiento propio del updater.
Cada superficie de `frozen_inventory_v1.json` (v3) lleva `scope`:
- `UPDATER` (8, cierran CT01): `lf_profile_update_begin_v1`, `lf_profile_update_effective_route_v1`, `lf_profile_update_evolution_step_guard_v1`, `lf_profile_update_post_merge_reconcile_v1`, `lf_profile_update_result_class_v1`, `lf_profile_update_substantive_block_v1`, `lf_profile_update_verified_receipt_v1`, `lf_record_profile_operation_step_v1`.
- `DEFERRED_ROUTER` (3, **no se evalúan aquí**, quedan rastreadas): `lf_router_governed_caller_route_v1`, `lf_router_resolve_v1`, `lf_router_semantic_resume_route_v1`.
- `OUT_OF_SCOPE_CREATION` (1): `lf_record_creacion_perfil_step_v1`.
No marques FAIL por una superficie del router o de creación. **Sí** marca FAIL por una superficie propia del updater que falte.

## 2. Qué se afirma
| # | Afirmación del productor |
|---|---|
| A1 | Las 8 funciones `UPDATER` existen en producción con la firma, el `md5(prosrc)` y el SECURITY DEFINER del inventario. |
| A2 | De las 6 Edge de perfiles, solo `run-creacion-perfil-lf` llama a funciones SQL de la ruta del updater. |
| A3 | El falsificador detecta deriva de cuerpo, firma y función sin propietario, y pasa limpio hoy. |
| A4 | La condición de cierre de CT01 está en producción y es válida (6 condiciones en `true`); CT02 a CT07 siguen bloqueados. |
| A5 | El inventario `UPDATER` es exhaustivo: no existe otra función SQL, Edge, workflow o contrato propio de la actualización de perfiles que falte. |

## 3. Archivos fijos (verifica el sha256 antes de leer)
| Archivo | sha256 |
|---|---|
| `docs/profile_updater/PE10A_CT01_INVENTARIO_BORRADOR_V1_20261027.md` | `00caa420c659ec389cdad27059be7fc1f52ffd48b6fa6e14630fd89e01a584c4` |
| `docs/profile_updater/pe10a_ct01_falsifier/frozen_inventory_v1.json` | `e90b6e32a170dcd2a330304a073f8fc4c5539072e1722d039153a2c060dfe875` |
| `docs/profile_updater/pe10a_ct01_falsifier/gen_falsifier_sql.py` | `8f83faf8d6e62bee7f29258a7543a9a9ffed1abc287d7aa84b5502d24a0e573c` |
| `supabase/migrations/20261027214500_lf_pe10a_ct01_assertion_contract_ready_v1.sql` | `a1c02b07ba6c1ecb5aae5726dcee4efad533265dc0306c4d85333aa5bbc1e709` |

## 4. Preguntas y resultado esperado
**P1 (A1).** Recalcula tú `md5(prosrc)`, argumentos y `prosecdef` de las 8 funciones `UPDATER` directo de `pg_proc` (schema `public`) y compáralos con el JSON. Esperado: 8/8 coinciden.

**P2 (A3).** Ejecuta el generador (`--negatives`) o replica la comparación en SQL. Esperado: UPDATER 8 PASS, DEFERRED_ROUTER 3 PASS, OUT_OF_SCOPE_CREATION 1 PASS, y 3 fallos esperados (`FAIL_BODY_DRIFT`, `FAIL_SIGNATURE_DRIFT`, `FAIL_MISSING_OR_OWNERLESS`). Inventa **una mutación distinta** de esas tres y comprueba que se detecta.

**P3 (A2).** Inspecciona el código de las 6 Edge de perfiles y lista todo `rpc(...)`. Esperado: solo `run-creacion-perfil-lf` llama a las funciones `UPDATER`. Clasifica cada otro RPC que encuentres como `UPDATER`, `DEFERRED_ROUTER` u otro, con su evidencia.

**P4 (A4).** `programacion.fn_engineering_checkpoint_action_spec_v3('PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10A_CONTRACTS','PE10A_CT01')` pasado por `programacion.fn_engineering_action_spec_assertion_contract_v1` debe dar `READY` con 6 claves en `true`. CT02 a CT07: `BLOCK_ACTION_SPEC_NOT_READY`. CT01 debe seguir `PENDING`.

**P5 (A5, la más importante).** Busca lo que **falta dentro del alcance del updater**:
(a) funciones SQL cuyo nombre empiece por `lf_profile_update_` o que la ruta de actualización llame (por Edge, por otra función `UPDATER`, por workflow o por contrato) y no estén en el inventario;
(b) Edge, workflows (`.github/workflows/*`) o contratos de `skills/profile_creator/contracts/` que gobiernen la actualización y no estén mencionados en el inventario;
(c) para cada hallazgo, di si pertenece a `UPDATER`, `DEFERRED_ROUTER` o creación. Un hallazgo `UPDATER` no inventariado es `FAIL`; uno de router o creación se reporta pero no es `FAIL`.

## 5. Debilidades conocidas del productor
- "Mencionada en" es búsqueda de texto del nombre en `prosrc`: no distingue llamada de comentario.
- El falsificador compara cuerpo, firma y SECURITY DEFINER. No compara ACL, triggers ni dependencias fuera de `public`.
- Los 16 contratos JSON se inventariaron por claves de primer nivel, no campo a campo. No hay archivo con `V0_7R1` en su ruta.
- Las Edge no tienen schema formal de respuesta; se declaró fuera de alcance de CT01 (decisión reversible).
- `fn_engineering_action_spec_assertion_contract_v1` devuelve `READY` aunque falte `pass_when` (`pass_when: null`); la migración lo compensa.
- Pendientes rastreados fuera de CT01: escrituras indirectas de la cadena del router; EXECUTE de `anon`/`authenticated` sobre `lf_record_creacion_perfil_step_v1`.

## 6. Formato del recibo
```json
{
  "checkpoint": "PE10A_CT01",
  "subject_repo_head": "e3231f9816f8d95db02bd32df32dfe63a1349aa6",
  "verdict": "PASS | FAIL",
  "per_question": {"P1": "", "P2": "", "P3": "", "P4": "", "P5": ""},
  "evidence_refs": ["consulta o comando ejecutado + resultado propio"],
  "rationale_summary": "",
  "mutation_invented_by_reviewer": "",
  "omissions_found": [{"surface": "", "scope": "UPDATER|DEFERRED_ROUTER|OTRO", "evidence": ""}],
  "independence": {"dependency": "", "data": "", "author": ""}
}
```

## 7. Limitación abierta
Este recibo es evidencia técnica de un revisor distinto del productor. **No he comprobado que el sistema lo acepte como recibo independiente de cierre:** el precedente PE10_C3 exige procedencia del proveedor verificada del lado servidor. La vía de admisión (revisión orquestada o recibo manual aceptado por el dueño) está pendiente de decisión.
