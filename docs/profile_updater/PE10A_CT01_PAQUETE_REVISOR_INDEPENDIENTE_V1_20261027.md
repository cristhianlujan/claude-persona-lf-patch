# PE10A_CT01 — Paquete para el revisor independiente

Fecha: 2026-10-27 · Repo `cristhianlujan/claude-persona-lf-patch` en `main` = `d29e1882d2233160a317e8b1be103812aa4342ca` · Supabase `mhwmirqcgxxukpctffuv`
Plan `PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1`, unidad `PE10A_CONTRACTS`, checkpoint `PE10A_CT01` (**PENDING**).

## 0. Reglas para el revisor
1. **No eres el productor.** El productor es la sesión de Claude que armó el inventario. No reutilices sus resultados: vuelve a ejecutar cada comprobación tú mismo. Un "PASS" copiado de este documento no vale.
2. Solo lectura. No escribas en Supabase ni en GitHub. No actives Profile Updater v0.2.
3. Si algo no se puede comprobar, di `NO_VERIFICADO`. No lo rellenes.
4. Entrega un veredicto `PASS` o `FAIL` por cada pregunta de la sección 3 con la evidencia que tú obtuviste.

## 1. Qué se afirma (lo que debes intentar refutar)
| # | Afirmación del productor |
|---|---|
| A1 | Las 9 funciones SQL de la sección 1 del inventario existen en producción con la firma, el `md5(prosrc)` y el SECURITY DEFINER del inventario. |
| A2 | De las 6 Edge de perfiles, solo `run-creacion-perfil-lf` llama a las funciones SQL del inventario. |
| A3 | El falsificador detecta tres tipos de deriva (cuerpo, firma, función sin propietario) y pasa limpio sobre el estado actual. |
| A4 | La condición de cierre de CT01 está en producción y es válida (6 condiciones, todas `true`), y CT02 a CT07 siguen bloqueados. |
| A5 | El inventario no cubre: contenido campo a campo de los contratos, Edge sin schema de respuesta, ni si `lf_router_governed_caller_route_v1` escribe. |

## 2. Archivos fijos (verifica el hash antes de leer)
| Archivo | sha256 |
|---|---|
| `docs/profile_updater/PE10A_CT01_INVENTARIO_BORRADOR_V1_20261027.md` | `211d7d6cb564c719186ef29ece1696880122dc7f717ef40d79ddc12639d98ccc` |
| `docs/profile_updater/pe10a_ct01_falsifier/frozen_inventory_v1.json` | `84dca8c6fefa4e3369019cdb79c0bc5b94be37b0fe07091ebf1ac9c0f6686382` |
| `docs/profile_updater/pe10a_ct01_falsifier/gen_falsifier_sql.py` | `0790d6ac98a3d11474ea1a9a23f536240fcd5ba0e4a42ad9160bc5294ff6b9b5` |
| `supabase/migrations/20261027214500_lf_pe10a_ct01_assertion_contract_ready_v1.sql` | `a1c02b07ba6c1ecb5aae5726dcee4efad533265dc0306c4d85333aa5bbc1e709` |

## 3. Qué ejecutar y qué esperar
**P1 (A1).** `python3 gen_falsifier_sql.py > f.sql` y ejecuta `f.sql` en solo lectura. Esperado: 9 filas `PASS`. Después **recalcula tú** `md5(prosrc)` y los argumentos de las 9 funciones directo de `pg_proc` y compáralos con el JSON, sin pasar por el generador.

**P2 (A3).** `python3 gen_falsifier_sql.py --negatives`. Esperado: 9 `PASS` + `FAIL_BODY_DRIFT`, `FAIL_SIGNATURE_DRIFT`, `FAIL_MISSING_OR_OWNERLESS`. Inventa **una mutación distinta** de las tres (por ejemplo, cambiar `secdef` de una función) y confirma que da `FAIL_SECDEF_DRIFT`.

**P3 (A2).** Busca en el código de las 6 Edge (`get_edge_function` o su fuente) cualquier llamada `rpc(...)` a las 9 funciones. Esperado: solo `run-creacion-perfil-lf` (`lf_profile_update_begin_v1`, `lf_record_profile_operation_step_v1`). Cuenta además cuántas Edge llaman a cualquier otro `rpc`, para ver si el inventario omitió superficies.

**P4 (A4).** Consulta `programacion.fn_engineering_checkpoint_action_spec_v3('PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10A_CONTRACTS','PE10A_CT01')` y pásalo a `programacion.fn_engineering_action_spec_assertion_contract_v1`. Esperado: `READY` con `pass_when` de 6 claves en `true`. Repite para CT02 a CT07: esperado `BLOCK_ACTION_SPEC_NOT_READY`. Confirma que CT01 sigue `PENDING` en `programacion.engineering_work_checkpoints`.

**P5 (A5, la más importante).** Busca lo que **falta**: (a) otra función SQL, Edge, workflow o contrato que toque la actualización de perfiles y no esté en el inventario; (b) si el cuerpo de `lf_router_governed_caller_route_v1` escribe (es SECURITY DEFINER, volátil, y `supabase_read_only_user` tiene EXECUTE). Un inventario que omite una superficie es un `FAIL`.

## 4. Debilidades conocidas del productor (verifica si importan)
- La columna "mencionada en" usa búsqueda de texto del nombre en `prosrc`: no distingue una llamada de un comentario.
- El falsificador compara cuerpo, firma y SECURITY DEFINER. No compara ACL, triggers ni dependencias fuera de `public`.
- Los 16 contratos JSON se inventariaron solo por claves de primer nivel. No se encontró ningún archivo `V0_7R1` por nombre.
- Las Edge no tienen schema formal de respuesta; se declaró fuera de alcance de CT01 por defecto (decisión reversible).
- La función oficial `fn_engineering_action_spec_assertion_contract_v1` devuelve `READY` aunque falte `pass_when` (`pass_when: null`). La migración lo compensa; el defecto sigue sin corregir.
- Pruebas de la migración corridas en réplica local PostgreSQL 16; producción usa 17.6.

## 5. Formato del recibo que se espera
```json
{
  "checkpoint": "PE10A_CT01",
  "subject_repo_head": "d29e1882d2233160a317e8b1be103812aa4342ca",
  "verdict": "PASS | FAIL",
  "per_question": {"P1": "PASS|FAIL|NO_VERIFICADO", "P2": "...", "P3": "...", "P4": "...", "P5": "..."},
  "evidence_refs": ["consulta o comando ejecutado + resultado propio"],
  "rationale_summary": "",
  "mutation_invented_by_reviewer": "",
  "omissions_found": [],
  "independence": {"dependency": "", "data": "", "author": ""}
}
```
`independence` debe decir con qué recursos obtuviste los datos, distintos de los del productor.

## 6. Limitación abierta (importante)
El precedente PE10_C3 (`skills/profile_creator/contracts/pe10_c3_gpt_native_independent_handoff_candidate_v1.md`) establece que una respuesta transcrita desde un chat **no aporta atestación del proveedor** y que el sistema debe verificarla del lado servidor. **No he comprobado que un recibo emitido en otra sesión sea aceptado por el sistema como independiente.** Antes de usar este recibo para cerrar CT01 hay que decidir cuál es la vía de admisión: la revisión orquestada (`REVISION_INDEPENDIENTE_ESTRATEGIA_LF`) o un recibo manual aceptado por el dueño. Hasta entonces el recibo es evidencia, no cierre.
