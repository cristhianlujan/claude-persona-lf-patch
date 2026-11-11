# PG-13 — Freeze, rebuild y mutación real, revisión exact-HEAD (2026-11-04)

## Base y alcance
- PR nuevo apilado sobre #3546, HEAD exacto `26e09c08c2a70ab06d778166652c0577850b3d06`, PG-12 12/12 verificado por Claude; C4 readback real comprobado por Claude en PostgreSQL 16.15 desechable.
- Rama `lf/pg13-freeze-integrity-chain-20261104`.
- Tres productores originales `pg13_c1_freeze_intent_candidate_v1.py`, `pg13_c2_rebuild_comparison_candidate_v1.py`, `pg13_c3_mutation_block_candidate_v1.py` portados **sin alteración** del PR #3528.
- Se añadieron `pg13_pg12_exact_freeze_bridge_v1.py`, pruebas C1–C3 y un arnés independiente de Git temporal.

## C1 — Enlace exacto a PG-12
`bridge_pg12_c4_to_pg13_c1` usa salidas reales `prepare_pg12_c1`, `prepare_pg12_c4` y `prepare_pg13_c1`. Exige:
- `pg12_c4.source_pg12_c1_sha256 == pg12_c1.candidate_sha256`;
- `pg13_c1.source_pg12_c4_sha256 == pg12_c4.candidate_sha256`;
- `pg13_c1.source_pg12_c1_sha256 == pg12_c1.candidate_sha256`;
- igualdad **exacta** de commit y tree del candidato entre PG-12 C1 y PG-13 C1;
- recalcula el SHA-256 del `payload_candidate` de C4 y lo compara con `payload_candidate_sha256`;
- rechaza digests inválidos y elevación de autoridad, incluso si el atacante recalcula el digest externo.

Importante: el bridge **NO presenta un nuevo readback PostgreSQL** ni verifica que una copia productiva sea la misma base desechable usada por Claude. Es continuidad de un paquete candidato, no freeze ejecutado. `freeze_enforced=false`.

## C2 — Rebuild
El productor original `prepare_pg13_c2` examina parejas `baseline_digest_sha256` / `rebuild_digest_sha256` por artefacto:
- iguales con `difference_ref=None` → `digest_equal_reported=true`, sin atribuir reconstrucción ejecutada;
- diferentes sin `difference_ref` → `C2_DIFFERENCE_UNDOCUMENTED`, BLOCK;
- diferentes con documento tipado → candidato reporta diferencia, `rebuild_reproducibility_verified=false`;
- iguales pero con una diferencia declarada → `C2_SPURIOUS_DIFFERENCE`, BLOCK.

No se ha realizado un rebuild real del artefacto ni se han autenticado las fuentes de sus digests; PG-13_C2 GO operativo exige dos builds reproducibles en un entorno aislado con receta, toolchain y bytes de artefactos.

## C3 — Intento real contra Git aislado
Archivo `tools/pg13_disposable_git_mutation_test_v1.py` con `tempfile.TemporaryDirectory`, Git bare y working repo local:
1. Crea bare remoto temporal y establece `receive.denyNonFastForwards=true`.
2. Hace commit A y commit B; publica B en rama `frozen`.
3. Retrocede el working repo hasta A, crea un commit divergente C distinto.
4. Invoca **realmente** `git push --force origin frozen`.
5. Exige salida no-cero y compara el SHA de `refs/heads/frozen` remoto antes/después, sin cambios.
6. Verifica que el commit local C sea distinto del congelado B; el checkout real se destruye al finalizar el contexto temporal.

**Evidencia ejecutada localmente en este turno** (reproducción del mismo procedimiento en el entorno local):
```
PG13_C3_DISPOSABLE_GIT_FORCE_PUSH_BLOCK=PASS
PG13_C3_GIT_FORCE_PUSH_COMMAND_EXIT_NONZERO=TRUE
PG13_C3_REMOTE_SHA_UNCHANGED=TRUE
PG13_C3_LOCAL_DIVERGENT_COMMIT_BLOCK=PASS
PG13_C3_FROZEN_COMMIT_SHA=25f7d95665ce29b9d476f48b984b80001842d707
PG13_C3_PRODUCTION_FREEZE_VERIFIED=FALSE
```

La evidencia real es **exclusivamente del repositorio temporal**. No verifica reglas productivas, protección de `main`, ausencia de privilegios administrativos de force-push ni verificación de SHA sobre una rama de release real. La suite `test_pg13_disposable_git_enforcement_v1.py` invoca el script y exige las marcas literales.

## Ejecutar sobre el HEAD exacto en el checkout Git de Claude
```bash
git rev-parse HEAD
ROOT=sandbox/lf_contract_gate_test/programming_agent_four_stage
python3 -m py_compile "$ROOT"/pg13_freeze_candidate/tools/*.py "$ROOT"/pg13_freeze_candidate/tests/*.py
cd "$ROOT"/pg13_freeze_candidate
python3 -m unittest discover -s tests -p 'test_pg13_freeze_chain_v1.py' -v
python3 -m unittest discover -s tests -p 'test_pg13_disposable_git_enforcement_v1.py' -v
python3 tools/pg13_disposable_git_mutation_test_v1.py
cd ../pg12_identity_candidate
python3 -m unittest discover -s tests -p 'test_pg12_identity_chain_v1.py' -v
cd ../pg11_integrity_candidate
python3 -m unittest discover -s tests -p 'test_pg10_pg11_bridge_and_waiver_time_v1.py' -v
```

El autor solo ejecutó la **simulación local real de Git temporal**, no la suite unitaria de cadena sobre el checkout Git del PR. **No se puede declarar 11/11 PASS hasta que Claude ejecute ambos archivos y revise el HEAD**.

No se fusionó, no se escribió en Supabase, no se modificó Analysis, Worker productivo, `main` ni Testing. Detener antes de PG-14 hasta revisión independiente.


## Corrección de C3 posterior a auditoría independiente (2026-11-04)

Claude calificó el HEAD anterior `fb05cce445a8e2a3b2acc4fba071961a99b41234` con 12/12, pero comprobó que `receive.denyNonFastForwards=true` **NO** protege contra fast-forward normal ni contra eliminación. Por tanto aquel C3 NO era un freeze inmutable.

Se actualizó `tools/pg13_disposable_git_mutation_test_v1.py` para:
- Establecer primero el commit B en `refs/heads/frozen` y el tag **anotado** `refs/tags/frozen/<B-SHA>`.
- Activar `receive.denyNonFastForwards=true` **y** `receive.denyDeletes=true`.
- Instalar un **hook pre-receive** después del congelamiento; rechaza cualquier creación, actualización o eliminación en `refs/heads/frozen` y `refs/tags/frozen/*`, sin excepción por fast-forward.
- Ejecutar realmente los intentos contra Git: `FORCE_PUSH` (commit divergente), `NORMAL_FAST_FORWARD` (commit descendiente), `DELETE` (rama congelada), `RECREATE_DIFFERENT_SHA` (crear un ref alterno bajo el namespace protegido) y, adicionalmente, `DELETE_ANNOTATED_TAG`.
- Exigir en **todos**: exit code no cero, mensaje literal del hook `LF_FROZEN_REF_IMMUTABLE`, mismo SHA remoto de la rama y mismo OID del tag.
- Probar que el ref alternativo no fue creado y que `PG13_C3_PRODUCTION_FREEZE_VERIFIED=FALSE`.

**Nota de semántica:** no puede ejecutarse «borrar ref original y recrearlo» exitosamente porque el borrado ya está prohibido. La prueba de recreación verifica el intento de crear un nuevo ref protegido apuntando a un SHA distinto. Esto no sustituye un ensayo de ref update tras bypass de hook administrativo.

**Procedimiento local ejecutado por el autor:** cinco casos `..._BLOCK=PASS` y `..._REFS_UNCHANGED=TRUE` sobre bare repo desechable. La ejecución local fue sobre la misma estrategia, pero **la versión GitHub exacta del HEAD nuevo debe ser calificada de nuevo por Claude**. El HEAD anterior no cubría los ataques adicionales.

Comandos a ejecutar en el nuevo HEAD:

```bash
git rev-parse HEAD
ROOT=sandbox/lf_contract_gate_test/programming_agent_four_stage
python3 -m py_compile "$ROOT"/pg13_freeze_candidate/tools/*.py "$ROOT"/pg13_freeze_candidate/tests/*.py
cd "$ROOT"/pg13_freeze_candidate
python3 -m unittest discover -s tests -p 'test_pg13_freeze_chain_v1.py' -v
python3 -m unittest discover -s tests -p 'test_pg13_disposable_git_enforcement_v1.py' -v
python3 tools/pg13_disposable_git_mutation_test_v1.py
```

**No promover PG-13 C3 ni abrir PG-14 antes de esta recalificación.** Los permisos de GitHub, las reglas de la rama productiva y la resistencia a administradores con acceso a hooks son dependencias separadas no demostradas por el bare local.
