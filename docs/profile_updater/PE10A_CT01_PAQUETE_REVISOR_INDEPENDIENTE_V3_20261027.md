# PE10A_CT01 — Paquete para el revisor independiente (ronda 3)

Fecha: 2026-10-27 · Repo `cristhianlujan/claude-persona-lf-patch` en `main` = `21f4c3b14409a5bcc0b8b396b72fbe54a819efa7` · Supabase `mhwmirqcgxxukpctffuv`
Plan `PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1`, unidad `PE10A_CONTRACTS`, checkpoint `PE10A_CT01` (**PENDING**).
Sustituye a V2. Ronda 1: FAIL (3 superficies SQL omitidas, corregidas). Ronda 2: P1, P2, P4 PASS; P5 NO_VERIFICADO (sin prueba de exhaustividad de contratos/workflows/Edge); el productor lo verificó, halló que sí faltaban la Edge `lf-profile-creator-governance-caller-v1`, el workflow `lf-customer-profile-creator-governance-caller.yml`, 13 contratos y 5 validadores como superficies del updater, y los incorporó (inventario 5.10).

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
| A5 | Los archivos del repo que nombran la ruta de actualización son exactamente los 43 de `frozen_updater_files_v1.json` (generados por `enumerate_updater_files.sh`), y su categoría es correcta. La Edge `lf-profile-creator-governance-caller-v1` y el workflow de governance caller son `UPDATER`. No hay otra función SQL `UPDATER` fuera de las 8. |

## 3. Archivos fijos (verifica el sha256 antes de leer; son 6)
| Archivo | sha256 |
|---|---|
| `docs/profile_updater/PE10A_CT01_INVENTARIO_BORRADOR_V1_20261027.md` | `a7c7ac86b6187d4f818f5523eeb945890e1adadffef1defde5477522a98770a8` |
| `docs/profile_updater/pe10a_ct01_falsifier/frozen_inventory_v1.json` | `e90b6e32a170dcd2a330304a073f8fc4c5539072e1722d039153a2c060dfe875` |
| `docs/profile_updater/pe10a_ct01_falsifier/gen_falsifier_sql.py` | `8f83faf8d6e62bee7f29258a7543a9a9ffed1abc287d7aa84b5502d24a0e573c` |
| `docs/profile_updater/pe10a_ct01_falsifier/frozen_updater_files_v1.json` | `946fce82d9f89648e01bd94b67cda656d3996751ff0f3997ec38ec9ea75cad7f` |
| `docs/profile_updater/pe10a_ct01_falsifier/enumerate_updater_files.sh` | `3de6aa1a81f7e54657face64554d4685fef34679873c0c7dd81e454cf086597d` |
| `supabase/migrations/20261027214500_lf_pe10a_ct01_assertion_contract_ready_v1.sql` | `a1c02b07ba6c1ecb5aae5726dcee4efad533265dc0306c4d85333aa5bbc1e709` |

## 4. Preguntas y resultado esperado
**P1 (A1).** Recalcula tú `md5(prosrc)`, argumentos y `prosecdef` de las 8 funciones `UPDATER` directo de `pg_proc` (schema `public`) y compáralos con el JSON. Esperado: 8/8 coinciden.

**P2 (A3).** Ejecuta el generador (`--negatives`) o replica la comparación en SQL. Esperado: UPDATER 8 PASS, DEFERRED_ROUTER 3 PASS, OUT_OF_SCOPE_CREATION 1 PASS, y 3 fallos esperados (`FAIL_BODY_DRIFT`, `FAIL_SIGNATURE_DRIFT`, `FAIL_MISSING_OR_OWNERLESS`). Inventa **una mutación distinta** de esas tres y comprueba que se detecta.

**P3 (A2).** Inspecciona el código de las 6 Edge de perfiles y lista todo `rpc(...)`. Esperado: solo `run-creacion-perfil-lf` llama a las funciones `UPDATER`. Clasifica cada otro RPC que encuentres como `UPDATER`, `DEFERRED_ROUTER` u otro, con su evidencia.

**P4 (A4).** `programacion.fn_engineering_checkpoint_action_spec_v3('PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10A_CONTRACTS','PE10A_CT01')` pasado por `programacion.fn_engineering_action_spec_assertion_contract_v1` debe dar `READY` con 6 claves en `true`. CT02 a CT07: `BLOCK_ACTION_SPEC_NOT_READY`. CT01 debe seguir `PENDING`.

**P5 (A5, la más importante). Procedimiento obligatorio:** (0) ejecuta `enumerate_updater_files.sh` (o replica: `git ls-files` en `.github/workflows`, `supabase/functions`, `skills/profile_creator/contracts`, `skills/profile_creator/validators`, `docs/reconcile`, `docs/programming-agent`, `docs/operations` + grep del patrón) y compara con el JSON: ¿mismo conjunto y mismos blob sha1? (1) revisa la categoría de cada archivo y impugna las que consideres mal; (2) busca fuera de esas carpetas (p. ej. `profiles/`, `skills/profile_creator/evals/`, `sandbox/`) algún archivo que **gobierne** la actualización y no nombre el patrón. Si no puedes completar un paso, dilo como `NO_VERIFICADO` con el paso exacto; no declares PASS por falta de hallazgos. Búsqueda original: Busca lo que **falta dentro del alcance del updater**:
(a) funciones SQL cuyo nombre empiece por `lf_profile_update_` o que la ruta de actualización llame (por Edge, por otra función `UPDATER`, por workflow o por contrato) y no estén en el inventario;
(b) Edge, workflows (`.github/workflows/*`) o contratos de `skills/profile_creator/contracts/` que gobiernen la actualización y no estén mencionados en el inventario;
(c) para cada hallazgo, di si pertenece a `UPDATER`, `DEFERRED_ROUTER` o creación. Un hallazgo `UPDATER` no inventariado es `FAIL`; uno de router o creación se reporta pero no es `FAIL`.

## 5. Debilidades conocidas del productor
- "Mencionada en" es búsqueda de texto del nombre en `prosrc`: no distingue llamada de comentario.
- El falsificador compara cuerpo, firma y SECURITY DEFINER. No compara ACL, triggers ni dependencias fuera de `public`.
- Los contratos `UPDATER_CONTRACT` (15) se ven por existencia y claves de primer nivel, no campo a campo. Los 16 contratos JSON se inventariaron por claves de primer nivel, no campo a campo. No hay archivo con `V0_7R1` en su ruta.
- Las Edge no tienen schema formal de respuesta; se declaró fuera de alcance de CT01 (decisión reversible).
- `fn_engineering_action_spec_assertion_contract_v1` devuelve `READY` aunque falte `pass_when` (`pass_when: null`); la migración lo compensa.
- Pendientes rastreados fuera de CT01: escrituras indirectas de la cadena del router; EXECUTE de `anon`/`authenticated` sobre `lf_record_creacion_perfil_step_v1`.

## 6. Formato del recibo
```json
{
  "checkpoint": "PE10A_CT01",
  "subject_repo_head": "21f4c3b14409a5bcc0b8b396b72fbe54a819efa7",
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
