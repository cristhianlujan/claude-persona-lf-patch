# PG-11: cierre candidato de dos huecos — PG-10→PG-11 y vencimiento de waivers
Fecha: 2026-11-04

## Contexto exacto

- PR: #3542, apilado encima de #3541. HEAD base original de PG-11 antes de correcciones: `4ad97bad5a22b414992bb77e90cea7887b1e3d5b`.
- Dictamen externo (Claude) de ese HEAD: 14/14 pruebas PASS. Se detectaron dos huecos: no existe binding PG10→PG11 y solo se rechaza un waiver si ya dice `EXPIRED`.
- Los cinco módulos originales C1–C5 permanecen sin modificación. Esta corrección es aditiva, con la nueva capa de enlace y una función temporal en la extensión existente.

## Hueco 1: PG10 C5 → PG11 C1

Nuevo módulo: `tools/pg11_pg10_handoff_bridge_candidate_v1.py`.
Función: `bridge_pg10_c5_to_pg11_c1`.

**Fuentes de entrada exigidas:**
- `pg10_c5` sobre real del productor `prepare_pg10_c5`, esquema `PG10_C5_NEGATIVE_ASSURANCE_CANDIDATE_V1`.
- `pg10_c4` como antecedente directo del digest `pg10_c5.source_candidate_sha256.pg10_c4`.
- `pg09_c4` para igualdad de `run_ref` y digest de escalamiento.
- `pg08_final` para `target_repo` y `base_head_sha`; incluye digest canónico y rechazo de flags de autoridad.
- `pg11_c1` producido realmente por `prepare_pg11_c1`, con `expected_base_sha` y `expected_head_sha`.
- `run_binding`: `run_ref, target_repo, base_head_sha, expected_head_sha`, declarados explícitamente por el invocador.

**Checks deterministas:** digest canónico de los cinco sobres; C5→C4 por SHA; mismo run de C5/C4/C9; mismo repositorio de PG08; mismo commit base en PG08 y PG11 C1; mismo commit HEAD esperado en PG11 C1; no PASS ni autoridad prematura. La salida conserva los cinco SHA y un `pg10_pg11_chain_shape_verified=true`.

**Rechazos probados:** run ajeno, base ajena, HEAD ajeno, SHA de C4 adulterado, `production_authority=true` falsificado y re-hasheado.

**Límite honesto:** el sobre PG10_C5 y la identidad Git no se autentican con un runner ni con fuente productiva. La prueba positiva llama a `test_pg10_decision_chain_v1.build()` —que produce PG10 C1–C5 de verdad— y `test_pg11_integrity_chain_v1.fixture()` —que produce PG11 C1–C5—; NO inventa un sobre C5. Los `run_binding` y los SHA son sintéticos, reproducibles y exclusivamente de prueba.

## Hueco 2: `expires_at` vs `evaluated_at`

Función nueva en `tools/pg11_integrity_extension_candidate_v1.py`: `reject_waiver_expired_at`.
- Ejecuta el guard existente `reject_invalid_waiver` que exige `STD-GEN-05` y estado `APPROVED`.
- Exige `expires_at` en cada waiver; si falta, bloquea.
- Recibe `evaluated_at` como ISO-8601 con zona horaria explícita; se normalizan ambos a UTC.
- Bloquea si `evaluated_at >= expires_at`.
- Un segundo antes: candidato permitido **sin permiso de supresión**; en el instante exacto y un segundo después: `PG11_WAIVER_EXPIRED_BY_TIMESTAMP`.
- Rechaza fecha sin zona horaria y compara correctamente offsets (p. ej. `19:00-05:00 = 00:00Z`).

**Límite honesto:** tiempo y waivers son entradas externas declaradas. `evaluation_clock_authenticated=false`, `waiver_registry_authenticated=false`, `suppression_allowed=false`. Este código no certifica un waiver ni concede derechos de borrar código. Si se necesita cubrir revocación posterior, el registro canónico debe consultarse en modo gobernado.

## Comandos exactos para Claude

```bash
git rev-parse HEAD
ROOT=sandbox/lf_contract_gate_test/programming_agent_four_stage
python3 -m py_compile "$ROOT"/pg11_integrity_candidate/tools/*.py "$ROOT"/pg11_integrity_candidate/tests/*.py
cd "$ROOT"/pg11_integrity_candidate
python3 -m unittest discover -s tests -p 'test_pg10_pg11_bridge_and_waiver_time_v1.py' -v
python3 -m unittest discover -s tests -p 'test_pg11_integrity_chain_v1.py' -v
cd ../pg10_conflict_candidate
python3 -m unittest discover -s tests -p 'test_pg10_decision_chain_v1.py' -v
cd ../pg09_iteration_candidate
python3 -m unittest discover -s tests -p 'test_pg09_iteration_chain_v1.py' -v
```

Exigir salida literal, HEAD exacto, conteos y ausencia de regresiones. Un archivo en GitHub no es PASS. No fusionar ni avanzar a PG12 antes de calificación.

## Estado inicial

`SOURCE_WRITTEN / 12_TESTS_ADDED / NOT_EXECUTED / OFFICIAL_PENDING`.
No se tocaron Supabase, Analysis, main, Worker productivo, Testing ni autoridad de revisión.
