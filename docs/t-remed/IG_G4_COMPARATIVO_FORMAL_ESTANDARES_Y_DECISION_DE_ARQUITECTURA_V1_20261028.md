# LF Input Governance · G4 — comparación formal con fundamentos externos y evidencia local

**Corte:** 2026-10-28 · **PR #3269 / rama dev** · **Naturaleza:** estudio comparativo, **no ratificación del diseño**, no política productiva. **EKB leído antes de la auditoría y ejecución**. SQL Supabase: SELECT ONLY. GitHub: solo docs/test en rama dev. **Sin Router, sin Supabase writes, sin G5.**

## 0. Problema correcto y definición de éxito

El problema de LF tiene **dos decisiones distintas**:

1. **APLICABILIDAD:** ¿qué regla/obligación es pertinente para un target, contexto y consumidor? Ya existe N-4. Puede ser regla visual, de negocio, legal o de seguridad; NO todas las reglas LF son decisiones de permitir/denegar acceso.
2. **ADMINISTRACIÓN DEL ALCANCE:** ¿quién puede crear, modificar, exceptuar o publicar el selector que hace aplicable esa regla, bajo qué competencia y evidencia?

Agregar una tercera frontera de **publicación técnica** (PR, CI, fuente/paridad, PASE/Train) y distinguirla de las dos anteriores. Un actor que puede cambiar código **no** por ello posee competencia para alterar una obligación de Privacidad o Seguridad.

**Objetivo:** no modificar alcances por inferencias, títulos, categorías, `created_by`, `origen`, `es_transversal`, frecuencia, ni confianza semántica del LLM. En cambio, exigir fuentes verificables con competencia, condiciones, vigencia, decisiones y evidencia. Una nueva pantalla ya dentro de un selector autorizado se evalúa automáticamente **sin** abrir una decisión humana nueva.

## 1. Fuentes primarias y calificación de fuerza

| Referencia | Estado y contenido probado | Qué justifica, qué NO justifica |
|---|---|---|
| NIST SP 800-162 (2014, actualización 2019), https://csrc.nist.gov/pubs/sp/800/162/upd2/final | Definición publicada de ABAC: atributos de sujeto/objeto/acción/entorno y políticas | Sustenta selectores dinámicos y relevancia del contexto. NO suministra propietario de cada regla LF |
| NIST SP 800-205 (2019), https://doi.org/10.6028/NIST.SP.800-205 | Separa administración de políticas/datos, evaluación (PDP) y aplicación (PEP); exige integridad y actualidad de atributos | Sustenta separar curator/administración del matcher y del publicador. NO obliga a instalar un producto específico |
| ANSI/INCITS 359-2012, reseña oficial NIST https://csrc.nist.gov/projects/role-based-access-control | Estándar RBAC con roles, jerarquías, separación estática/dinámica de funciones | Sustenta verificar rol/SoD del aprobador, pero rol amplio no equivale a alcance delegado |
| OASIS XACML 3.0 Core, **OASIS Standard** (2013), https://docs.oasis-open.org/xacml/3.0/xacml-3.0-core-spec-os-en.html | Permit/Deny/NotApplicable/Indeterminate, targets, condiciones, algoritmos de combinación | Sustenta salidas no binarias y combinación explícita. **No** imponer `deny-overrides` universal a todas las reglas LF UX/negocio |
| OASIS XACML 3.0 Administration and Delegation Profile 1.0, **Committee Specification Draft 04**, 2014, https://docs.oasis-open.org/xacml/3.0/administration/v1.0/csd04/xacml-3.0-administration-v1.0-csd04.html | Describe autoridad para emitir políticas y delegación con límites; incluso una política firmada puede no estar autorizada | Fundamento directo para competencia **por alcance**, pero el perfil citado es DRAFT, **no** estándar final normativo |
| OMG DMN 1.6, versión **formal**, septiembre 2026, https://www.omg.org/spec/DMN/1.6/ | Estándar de decisiones de negocio; expresa entradas, salidas y conflictos con hit policies | Sustenta una especificación auditable de decisiones de gerencia, sin equiparar todas las reglas de contenido a permisos. **No** implica introducir motor DMN |
| Cedar — verificación guiada, FSE Companion 2024, https://doi.org/10.1145/3663529.3663854 | Modelos ejecutables, pruebas diferenciales, por propiedades, bugs descubiertos en un lenguaje de políticas | Sustenta test adversarial y equivalencia; **no** demuestra que nuestras tablas o scopes estén correctos |
| NIST SP 800-53r5 CM-3/AC-5, https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final | Gobierno de cambios y separación de funciones | Justifica control de cambios, no una firma por pantalla, regla o dominio por defecto |

**Actualidad:** a octubre 2026, OMG DMN 1.6 es versión formal; DMN 1.7 es beta. El TC de OASIS cambió denominación a ACAL en agosto 2026 y mantiene borradores nuevos; esto no convierte automáticamente el perfil de delegación de 2014 en OASIS Standard.

## 2. Precisión metodológica: no son tres teorías incompatibles

ABAC, RBAC y delegación **pueden modelarse uno dentro de otro**. Un ABAC completo también puede codificar roles, ownership y delegaciones. Nuestra comparación es entre tres **configuraciones concretas** de política:
- **A. ABAC mínimo de aplicabilidad:** contexto/estado/consumer/selector, sin política de competencia del emisor.
- **B. ABAC con control de rol (RBAC):** mismos controles + rol, todavía sin restricción documentada por recurso/acción/ámbito/versión.
- **C. ABAC con rol + administración delegada y vigente:** añade `competence source`, alcance/acción/version exactos, delegación vigente, recibo trazable, estado de fuentes, todas las autorizaciones efectivamente exigidas, veto normativo.

**C no es un nuevo software ni es necesariamente más eficiente:** es una lista de obligaciones de seguridad que el ecosistema LF debería expresar en sus controles existentes. Los tres se pueden implementar con el mismo PDP/registro de política si la fuente de competencia existe.

## 3. Experimento SQL reproducible (20 casos sintéticos)

Archivo ejecutado SELECT ONLY: `sandbox/lf_contract_gate_test/input_governance/ig_g4_comparacion_modelos_abac_rbac_delegacion_sintetica_20261028.sql`. Usa `WITH ... AS MATERIALIZED` solo para reproducibilidad del corte de fixtures, condiciones compartidas, y resultados.

### Resultados bajo un oráculo construido expresamente para este ensayo

| Configuración | Coincide con salida esperada | Escenarios donde permite algo que el oráculo prohíbe |
|---|---:|---|
| A — Solo atributos mínimos | **12/20** | M02, M03, M04, M05, M06, M09, M10, M18 |
| B — Atributos + rol | **13/20** | M03, M04, M05, M06, M09, M10, M18 |
| C — Atributos + competencia delegada verificable | **20/20** | Ninguno **en esta matriz autocontenida** |

Casos de falsación:
- **M02:** actor sin rol. A admite, B/C bloquean.
- **M03:** rol coincide pero no tiene delegación sobre ese scope. A/B admiten, C bloquea.
- **M04:** delegación expirada. A/B admiten, C bloquea.
- **M05/M18:** recibo incorrecto o ausente. A/B admiten, C bloquea.
- **M06:** dos dominios requeridos, una conformidad falta. A/B admiten, C bloquea.
- **M07:** veto no delegable. **Los tres modelos lo bloquean** cuando el veto se representa, porque ABAC puede incorporar ese control.
- **M08:** atributo de contexto necesario desconocido. Los tres lo bloquean por la condición de prueba.
- **M09:** autoridad fuente no verificada. A/B admiten, C bloquea.
- **M10:** fuente caducada. A/B admiten, C bloquea.
- **M14/M19:** nueva pantalla dentro del selector **ya publicado**. **Todos admiten automáticamente**, sin otra firma.
- **M15/M16/M20:** scope fuera de cobertura, selector no publicado, o fuente caducada. Los tres bloquean aplicar el cambio, cuando esas precondiciones están representadas.

**Limitaciones de estos 20/20:** el oráculo `expected` fue redactado con nuestros requisitos **propuestos**; no hay datos etiquetados por gerencia, no hay comparación de modelos formalmente equivalentes, no hay medición de costes/human review, ninguna evaluación real de propietarios de LF. **La cifra no constituye demostración de superioridad de C.** Únicamente prueba que un modelo que omite expresamente siete verificaciones deja pasar esas situaciones bajo esas políticas de ejemplo. Cambiar las políticas de A/B para añadir las mismas restricciones podría igualar resultados.

## 4. Confrontación con datos reales LF (corte de lectura)

Fuente canónica observada:
- `lf_ops.reglas`: `codigo, categoria, origen, valor_config, es_transversal, estado, pendiente_decision, created_by`; **sin owner funcional canónico por regla**.
- `public.lf_capability_registry`: `INPUT_GOVERNANCE` es ACTIVE con `owner_scope='LF_GOVERNANCE'`; **owner de capacidad, no prueba de competencia sobre regla de Privacidad, Seguridad o UX**.
- `private.lf_human_decision_classes_v1`: 7 clases ACTIVE.
- `private.lf_human_decision_classification_rules_v1`: 11 reglas ACTIVE.
- `private.lf_human_decision_route_policies_v1`: 7 rutas, 0 ACTIVE; IG tiene 3 para **`INPUT_GAP_PROPOSAL`**, no `RULE_APPLICABILITY_CHANGE`.
- `private.lf_human_decision_authority_policies_v1`: 0 filas; requests 0; receipts 0.
- Los selectores N-4 ACTIVE tienen `provenance.authority` textual y referencias a eventos 19948/19951 sin `acceptance_declared=true`; **no son firmas verificadas de cambios futuros**.
- `private.fn_lf_human_decision_resolve_policy_v1` evalúa una clase dominante por solicitud; la llamada read-only fue denegada por ACL, **no se debe sortear**. Para multi-dominio, resolver una sola clase no demuestra all-required-approvals.

**Conclusión sobre viabilidad hoy:** A soporta aplicabilidad técnica N-4; B comprueba pertenencia a roles pero no puede demostrar competencia por regla; C exige un **binding de owner/alcance que hoy no está identificado en fuentes canónicas**. Por ello **C NO puede habilitarse productivamente hoy** y no se debe inventar autoridad con un mapeo rígido `categoria→gerencia`.

## 5. Cinco reglas de LF, análisis no ratificado (NO clasificar catálogo)

| Regla | Evidencia real | Riesgo de autorización | Decisión **no tomada** |
|---|---|---|---|
| `REG_SES_001` | Regla onboarding/OTP 30 min; sin selector N-4 | Podría heredarse a login B2B indebidamente | Saber fuente propietaria de políticas de sesión y competencia de seguridad/producto |
| `REG_ABT_004` | Experimentos de campos/OTP/copy; sin selector N-4 | Una regla compuesta abarca distintos efectos de producto/privacidad/seguridad | Descomponer obligaciones según naturaleza y comprobar fuentes de cada efecto |
| `B2B-RULE-AUTH-001` | Seguridad post-auth; no selector N-4 en muestra | Autorizar excepción mediante gerente genérico | Política superior y delegación competente, veto de no-delegables |
| `B2B-RULE-DESIGN-001` | Selector ACTIVE: shell/modulo/IDs por `any` | Igualar coincidencia OR con autoridad universal LF | Documento/decisión del design system y scope autorizado; ninguna etiqueta es firma |
| `B2B-RULE-STORY-READINESS-001` | Selector ACTIVE por ID pantalla 51 | Convertir chequeo de 47 familias en ejecución de todas | Mantener selector determinista de familias ANTES de semántico; owner de readiness |

**La tabla sirve para calibración con datos; no se ejecutó reclasificación ni se asignó autoridad operativa a ninguna regla.**

## 6. Matriz de arquitectura comparada (criterios independientes)

| Dimensión | A ABAC mínimo | B ABAC + roles | C ABAC + roles + delegación |
|---|---|---|---|
| Selectores dinámicos N-4 | Sí | Sí | Sí |
| Restricción al acto de emitir una política | No, si no se añade | Parcial: rol | Sí **si existe evidencia de delegación** |
| Separación de funciones | No garantizada | Representable | Representable con SoD y permisos |
| Ámbito concreto por recurso/operación/consumer | Configurable | No garantizado por solo rol | Contrato exigido por alcance/version |
| Reglas vigentes con pantalla futura compatible | Automático | Automático | Automático |
| Firma humana por cada uso de regla | No necesaria | No necesaria | **No necesaria** |
| Coste de gobierno de cambios | Bajo, con riesgos | Intermedio | Mayor al principio; reutilizable luego |
| Integración actual LF | N-4 existente | Roles existentes parciales | Falta competencia/recibo/route para `RULE_APPLICABILITY_CHANGE` |
| Estado de evidencia para operación | Parcial | Parcial | **No habilitable aún** |

**Precedencia formal:** XACML/DMN muestran que los conflictos requieren una regla de combinación declarada; LF no debe hardcodear `Legal>Security>Product>UX` universal ni elegir mayor score semántico. Cuando dos competencias no son comparables, conservar `HOLD` y no ampliar scope. Políticas compatibles se pueden acumular, y veto no-delegable no se rebaja.

## 7. Recomendación como HIPÓTESIS DE ARQUITECTURA, no como cambio aprobado

**Opción preferente para diseñar/testear:** conservar N-4 como evaluador del selector; representar explícitamente autorización para **administrar el selector**, por competencia delegada y fuente actual, y reutilizar registro central LF para decisiones humanas **solo cuando se requiere cambio no preautorizado**. DMN sirve para especificar decisiones y casos de múltiples hits; no crear un motor DMN nuevo.

Pasos de diseño pendientes:
1. **Descubrir la fuente competente real** de dueño de cada política/regla y la relación con uno o más dominios; exigir fuente y versión. La clasificación semántica del Curator solo propone, no autoriza.
2. Definir un **binding lógico versionado** (no tabla nueva de entrada): `source_policy_ref + rule_ref + operation + authorized_scope + consumer + delegated_authority_ref + validity/revocation + policy_revision + evidence`. No inventar valores ni un enum rígido de especialidades.
3. Antes de escalamiento humano, intentar adquisición de evidencia puntual cuando esa evidencia pueda resolver el caso; no enviar automáticamente todas las reglas a gerencia.
4. **Ratificar** cómo distinguir una excepción que sí requiere aprobación de una nueva pantalla que ya cumple una política vigente.
5. Para conflictos multidominio, demostrar quién exige realmente cada conformidad; no imponer una firma por dominio por defecto. El registro central tiene `UNIQUE(request_id)` por recibo: un expediente con varias firmas requeriría varias solicitudes vinculadas o una extensión mínima gobernada, después de decisión de owner.
6. Pruebas reales, autoritativas y adversariales con validación independiente: permisos por rol, límites de delegación, currentness, scopes parcialmente solapados, veto, rollback, consumidor, source parity y no-regresión del selector de 47 familias.
7. **Solo con G4 autorizado** se puede proponer publicación posterior. **G5 no autorizado**: no reclasificar catálogo ni cortar `DERIVED_GLOBAL`.

## 8. Dictamen y estados

**Evidencia formal fuerte:** ABAC y RBAC para pertinencia y roles; XACML para combinación; DMN para decisiones auditables; NIST para administración separada de enforcement.

**Evidencia local fuerte:** N-4 existe y sus ACL basales están comprobadas; registro humano LF existe pero rutas de IG siguen pendientes, sin competencia canónica de regla.

**Hipótesis no demostrada:** implementación de delegación en LF, recuento mínimo de autorizaciones por riesgo, estrategia de agregación de múltiples firmas y costo operativo.

**G3 aislado:** PASS previo 28/28 y 812/812; pruebas ACL post-DDL e integración independientes siguen pendientes.  
**G4:** COMPARATIVO DOCUMENTADO, **NO_VERIFICADO para autoridad real**.  
**G5:** **NO_RECLASSIFY**.

**Para revisión conjunta:** decisión 1: fuente real de competencia. Decisión 2: conformidades necesarias ante conflicto multidominio. Decisión 3: política de no-escalamiento para cambios ya autorizados. No ratificar C como implementación final hasta probar 1–3.
