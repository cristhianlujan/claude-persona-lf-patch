# P01 — Cinco casos semánticos observados en LF

Fecha: 2026-10-28. Fuente: consultas de lectura a definiciones de reglas, pantallas, vínculos y selectores. Sin implementación, sin aprobación de gerencia, sin segunda revisión independiente.

## Método

Se contrastaron las descripciones y condiciones de cada regla con el objetivo y las dependencias reales de la pantalla. Se consultó `binding_source`, el shell de uso explícito y el selector N-4, si existía. No se tomó popularidad como autoridad. Los hallazgos son hipótesis de trabajo, no veredictos certificados.

| Caso | Evidencia consultada | Observación preliminar | Contraprueba necesaria |
|---|---|---|---|
| S01 `REG_SES_001` → `B2B-AUTH-001` | Regla: vencimiento del onboarding incompleto tras OTP pendiente; destino: autenticación B2B; origen vinculado a 25 pantallas del shell cliente; llega como DERIVED_GLOBAL | Posible falso positivo de alcance: onboarding cliente no equivale a login empresarial | Probar que el destino no comparte el proceso/política exacto de onboarding antes de rechazar formalmente |
| S02 `REG_ABT_004` → `B2B-AUTH-001` | Regla: experimentos del onboarding (orden de campos, CTA, OTP y correo); 23 vínculos propios en shell cliente; llega DERIVED_GLOBAL | Posible falso positivo por reutilización indiscriminada | Contrastar owner del experimento, público y variantes válidas |
| S03 `B2B-RULE-SESSION-001` → `ONB_004` | Regla: inactividad referenciada a políticas de sesión; 11 vínculos explícitos, 47 derivados; destino: alta cliente | Inconcluso: podría haber o no política compartida; no se debe inferir ausencia solo por el nombre | Contrastar referencias numéricas de políticas, fase autenticada, fuente y duración |
| S04 `B2B-RULE-DESIGN-001` → `B2B-AUTH-001` y `B2B-AUTH-002` | Selector ACTIVE, match N-4 positivo en ambos, 14 vínculos declarativos | Caso positivo del mecanismo declarativo; no prueba autorización para ampliar más allá del selector | Validar la procedencia de publicación y casos negativos fuera del alcance |
| S05 `B2B-RULE-STORY-READINESS-001` → `B2B-AUTH-001` | Texto menciona múltiples pantallas B2B; selector vigente coincide solo con pantalla id 51; en prueba `B2B-AUTH-002` no coincide | Posible subcobertura semántica, no permiso para modificar selector | Verificar decisión original del owner antes de proponer ampliación |

## Evidencia de pruebas negativas

La consulta read-only verificó que `B2B-RULE-DESIGN-001` **no coincide** con `HOME_FAQ` ni `ONB_004`; `B2B-RULE-STORY-READINESS-001` **no coincide** con `B2B-AUTH-002`, `HOME_FAQ` ni `ONB_004`. Esto confirma selección determinista observable, no pertinencia universal.

## Limitaciones y siguiente gate

- Solo cinco reglas fueron examinadas semánticamente; faltan 236 para completar cobertura de la cohorte heredada.
- La matriz estructural de 241 reglas ya está versionada en `IG_LOTE_A_P07_INVENTARIO_241_EVIDENCIA_20261028.csv`; sus señales son indicios para investigación, nunca autorizaciones.
- No hay segundo dictamen independiente ni validación de policies completas; no se calificaron scores 0–6 de producción.
- NO modificar datos ni retirar herencia en bloque. P01 queda en estado PILOTO / PENDING INDEPENDENT VALIDATION.
