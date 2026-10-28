# AI Sales 3.0 — Calificación transversal y confianza por evidencia (v0.7)

**Estado:** diseño de plan. Sin políticas comerciales ACTIVAS, sin contacto automático, sin alteración de Router ni perfil en producción.

## Problema de negocio
El mismo universo de empresas puede calificar distinto según SALY u otro negocio. No deben copiarse criterios SALY a todos los clientes, ni asumir que una empresa poco documentada carece de potencial. Separar **filtros obligatorios**, **encaje comercial**, **intención**, **calidad de la evidencia** y **permiso de contacto**.

## Selección de reglas
Resolver en el contexto de la acción: `business_code > product > market > action > effective_policy_version`.
- **Contrato transversal:** campos, evidencias, niveles de confianza, semántica de tres estados, protección de datos, decisión y trazabilidad.
- **Política por negocio:** ICP, atributos deseables, exclusiones, pesos/umbrales candidatos, señales de compra, fuentes autorizadas y personas compradoras.
- **Refinamiento por producto y mercado:** categoría real, zona, tamaño objetivo y demás restricciones.
- **Permiso para contactar:** validación independiente y al momento del envío; ni un score alto ni una fuente pública confieren autorización.
- Resolver una sola vez y distribuir una cápsula compacta a perfiles de Radar, Enrichment y SDR; reutilizar infraestructura de políticas existentes, sin segundo Router. Antes de registrar políticas comerciales vivas, comprobar que el catálogo actual permite el nuevo tipo; no reutilizar `lf_policy_versions` para propósitos no admitidos.

## Algoritmo v1 — auditable y determinista
1. Validar contexto: negocio y producto registrados, mercado, finalidad, versión de política y etapa.
2. Resolver identidad RUC/dominio/razón social, conservando filiales distintas.
3. Aplicar filtros `PASS / FAIL / UNKNOWN`, con motivo: `FAIL` excluye donde la política así lo exige; `UNKNOWN` solicita evidencia o congela la acción, no equivale a bajo encaje. Las prohibiciones de canal nunca se compensan con puntuación.
4. Para cada atributo observado: `value, source, source_type, fetched_at, observed_at, TTL, conflict, evidence_level, relevant_to_business`.
5. Confianza ordinal, no probabilidad matemática: `C0` no verificado/contradictorio; `C1` débil; `C2` fuente relevante, reciente pero insuficientemente corroborada; `C3` primaria actual o corroboración robusta independiente. No sumar republicaciones de una noticia.
6. Calcular por separado `FIT` (reglas empresariales), `INTENT` (señales de compra observables), `EVIDENCE_QUALITY` (por atributo) y `COVERAGE` (proporción de campos requeridos con evidencia). Los pesos dependen de la política y solo se calibran con resultados. No colapsar incertidumbre y encaje en una cifra opaca.
7. Decidir `PRIORITIZE / ENRICH / EXCLUDE / HOLD`. Para `ENRICH`, escoger la **siguiente mejor evidencia** por reducción esperada de incertidumbre decisiva, costo de búsqueda y permiso de fuente. Sin necesidad de un ML nuevo.
8. Guardar **un recibo compacto por cambio material** con negocio, versión/hash de política, datos usados, motivos, huecos y siguiente acción. No añadir miles de registros por corrida. La historia comercial vive en CRM.

## Ejemplo didáctico (sin puntuaciones inventadas)
- **Empresa X:** RUC confirmado `C3`, sector `C3`, empleados `C1`, área de RR. HH. `C0`. Para **SALY** podría ser `ENRICH` porque nómina/plantilla y decisor son decisivos. Para otra empresa de software B2B podría ser `PRIORITIZE` si su política no exige tamaño de nómina, *sin autorizarle el envío*.
- **Empresa Y:** existe y está verificada, pero carece de operaciones en el mercado definido como obligatorio por la política SALY. Si el hecho es `C3`, se `EXCLUDE` para SALY; para otro negocio podría continuar.
- **Empresa Z:** noticia de expansión reproducida por cinco portales desde un único comunicado. Es una sola procedencia, no cinco corroboraciones; se guarda evidencia con calidad según su origen.

## Calibración comercial
El piloto G0 y U12 deben registrar por negocio los falsos descartes, leads que sí dan respuesta/reunión/convenio, calidad de datos, tasas de UNKNOWN, costo de enriquecimiento, cobertura y latencia. Solo entonces ajustar pesos y umbrales. Reutilizar experimentos de fuentes y cohortes. No agregar revisores independientes a checkpoints.

## Checkpoints nuevos
- U00-C09: plantilla/versionado de selección de prospectos.
- U02-C12: datos de evidencia por atributo.
- U03-C10: independencia y calidad de fuentes.
- U07-C18: resolución contextual de política.
- U07-C19: matriz de encaje, confianza y cobertura.
- U07-C20: siguiente mejor evidencia y decisión.
- U12-C10: calibración por negocio.
- U15-C14: binding de política y perfiles.

**Resultado de migración esperado:** 18 unidades, 188 checkpoints PENDING, 180 originales preservados, ocho nuevos; nueve criterios antiguos enriquecidos. Esta migración no crea política comercial operativa, no habilita contactos y no activa IA.
