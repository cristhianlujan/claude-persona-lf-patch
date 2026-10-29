# PIP-1 · Carril D · Lote D-04 · Informe de validación

Fecha: 2026-10-28. Owner: Paulo. Ámbito: rama Git **local** `lf/pip1-d01-d03-isolated`; sin push ni PR.

| Checkpoint | Estado | Evidencia | Bloqueante |
|---|---|---|---|
| D-04.1 · Inventario exacto | **BLOCKED parcial** | GitHub fetch_file SHA pinned exitoso; blob Git `47dd1f611ac36325b57d5129a87dc57919de330f`; 44,401 caracteres UTF-8 leídos por conector; metadata core digest declarado `cd2f7a...ffb` | No materialización de bytes en contenedor, SHA256 completo y core no calculados localmente |
| D-04.2 · DAG real | **BLOCKED** | Estructura remota observada: 20 unidades, 97 operacionales, 11 PG-00, 22 edges; loader y tests de mutación sobre fixtures PASS | No ejecución del código contra archivo byte-exacto remoto |
| D-04.3 · Review adversarial | **PASS propio; NO independiente** | `D04_ADVERSARIAL_REVIEW.md` y regresiones | Revisión separada de Claude no ejecutada |
| D-04.4 · Correcciones + gobernanza | **PASS local / PASE NOT_RUN** | 51 unittest PASS; compileall PASS; git diff --check PASS | PASE necesita checkout/diff/manifiesto clasificado y ambiente LF |
| D-04.5 · Integración | **PASS diseño** | `D04_INTEGRATION_MATRIX.md`, sin adapters | Selección de autoridades externas y GO fuera de alcance |
| D-04.6 · Paquete reproducible | **PASS local** | ZIP, README, diff, manifest hashes | Reproducibilidad de inventario real pendiente de ejecución externa |

## Procedencia y hashes

- HEAD PR #3220: `eb0e4f3f912538b1cd2f2c9635854cbf86aeb783`, open/draft al readback.
- Git blob SHA1 declarado por GitHub para la ruta exacta: `47dd1f611ac36325b57d5129a87dc57919de330f` (no calculado localmente).
- `inventory_digest_sha256` declarado dentro del JSON remoto: `cd2f7a964b9901d9e58b8d5f4271532f480966424d37fd2d9a40332a7b440ffb` (no recalculado sobre los bytes remotos localmente).
- SHA256 del archivo remoto completo: **NOT_VERIFIED / BLOCKED**.
- SHA256 del objeto core recalculado localmente: **NOT_VERIFIED / BLOCKED**.
- SHA256 de los ficheros generados localmente: `SHA256SUMS.txt` dentro del ZIP (se calcula en packaging).

## Autoridad y límites

Inventario `CANDIDATE_NOT_APPROVED`, version `0.1.1-candidate`; `approval_ref=null`, `pg00_certification_ref=null`. PG-00 y sus labores de certificación pertenecen al Carril C. El código local no emite recibos verificados operacionales, no valida firmas, no acredita PG-00, no contiene persistencia ni conexiones a sistema real. El cierre `SYNTHETIC_CLOSURE` es únicamente un fixture de prueba. `operational=True` está bloqueado fail-closed.

## Cambios

Se corrigió interpretación de exclusiones propuestas, inmutabilidad de mappings, emisión espuria de cierre operacional por cadena de provenance simulable y validaciones de entrada (límite tamaño, canonicalización, shape). Se agregaron tests adversariales, verificador externo por SHA exacto y matriz de integración. No se incorporó cambio al modelo aprobado ni a sistemas operacionales.

## Decisiones pendientes

1. Conseguir un transporte fiable de bytes desde GitHub al checkout local y ejecutar el verificador completo.
2. Obtener review independiente de Claude del diff exacto.
3. Decidir por autoridad quién verifica N/A y qué certificación exacta de PG-00 es requisito para cierre operacional.
4. Clasificar diff con PASE y manifest según repo antes de contemplar PR; sin push automático.
