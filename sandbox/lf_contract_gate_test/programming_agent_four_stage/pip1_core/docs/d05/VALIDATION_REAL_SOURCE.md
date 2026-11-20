# D-05: fuente exacta, paridad y límites

- Repo: `cristhianlujan/claude-persona-lf-patch`.
- PR #3220 HEAD confirmado por GitHub conectado: `eb0e4f3f912538b1cd2f2c9635854cbf86aeb783` (draft, CANDIDATE_NOT_APPROVED).
- Archivo: `docs/programming/PROGRAMMING_PIPELINE_INVENTORY_CANDIDATE_V1.json`.
- Evidencia externa provista por owner/chat C (no recalculada localmente): tamaño 44704 bytes, SHA256 archivo `fc4cd3a387858d3091bee99cbec85721744792db7fed5ffdc1cc348b1a2719c9`, SHA256 core `cd2f7a964b9901d9e58b8d5f4271532f480966424d37fd2d9a40332a7b440ffb`.
- GitHub conectado confirmó SHA1 Git blob `47dd1f611ac36325b57d5129a87dc57919de330f` y consultó el contenido directamente en ese commit.
- Comprobación del JSON real directamente en conector (JavaScript, NO loader Python): 108 IDs únicos, 11 PG00, 97 operacionales, 22 aristas; sin ciclo ni referencias inexistentes; PG05<-PG04, PG11<-PG09+PG10, PG18<-PG16+PG17; capas paralelas PG02+PG10 y PG16+PG17; PG07.C7 excluido. `approval_ref` y `pg00_certification_ref` nulos.
- BLOQUEADO: el checkout local carece de bytes reales. `verify_exact_inventory.py --file ...` y mutaciones Python contra bytes auténticos NO pudieron ejecutarse; el fetch desde la red local falló. La comprobación conectada no acredita ejecución del loader.
- PASS LOCAL: 53 pruebas con fixtures (51 anteriores + 2 guardias SHA-256/archivo inválido), `compileall`, `git diff --check`.
- PASE oficial NOT_RUN: no hay checkout LF completo ni commit candidato LF para el plan de CI exact-head. No inferir PASS.
- Verificación independiente: NOT_RUN; eventual revisión de Claude pendiente.

## Reproducción cuando haya checkout real

```bash
cd path/to/lf-checkout
# Debe apuntar exactamente a #3220 HEAD; sin reemplazar por main.
git show eb0e4f3f912538b1cd2f2c9635854cbf86aeb783:docs/programming/PROGRAMMING_PIPELINE_INVENTORY_CANDIDATE_V1.json > /tmp/PIP1_INVENTORY_EXACT.json
cd path/to/pip1-core
python verify_exact_inventory.py --file /tmp/PIP1_INVENTORY_EXACT.json --out /tmp/PIP1_INVENTORY_VERIFIED.json
python -m unittest discover -s tests -v
```

No incluir el inventario copiado en el PR de núcleo puro; el verificador conserva pin por commit SHA.
