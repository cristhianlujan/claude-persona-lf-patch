# D-04 · Gobernanza y PASE

- GitHub PR #3220: HEAD `eb0e4f3f912538b1cd2f2c9635854cbf86aeb783` readback conectado, draft/open.
- Inventario: CANDIDATE_NOT_APPROVED; `approval_ref` y `pg00_certification_ref` son null.
- `AGENTS.md` leído: Router first para DB writes; PASE required; Merge Train único merge; prohibidos DB secrets en workflows.
- Acceso real al inventario: `mcp__GitHub__fetch_file` por commit exacto; SHA Git blob reportado por proveedor `47dd1f611ac36325b57d5129a87dc57919de330f`. Lectura conectada no equivale a materialización local ni al cálculo local del SHA256 del archivo.
- Descarga byte-exact al contenedor: **BLOCKED** por acceso de red/DNS; los bytes no se reconstruyeron.
- Validación de `inventory_core` en proceso local: **BLOCKED**, no atribuir PASS de fixture al objeto real.
- PASE oficial: **NOT_RUN**, ya que el diff no está en checkout completo LF, no se presentó PR y el plan exacto no fue evaluado.
- Lint/compile, unittest y `git diff --check`: ejecutados localmente, ver `D04_VALIDATION_REPORT.md`.
- Revisión independiente: **NOT_RUN**. Este review es adversarial propio, no certificado por Claude.
- Push/PR/merge/labels/PG-00/Supabase/rulesets: **NO MODIFICADOS**.
