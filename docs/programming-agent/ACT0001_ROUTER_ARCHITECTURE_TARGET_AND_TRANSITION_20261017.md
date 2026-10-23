# ACT-0001 — Arquitectura objetivo y transición gobernada (RFC)

**Ámbito:** Libertad Financiera, ACT-0001 y consumidores registrados. **Estado:** arquitectura propuesta/aprobada como dirección; reconciliación inicial con fuentes canónicas, **NO** implementación, certificación C2/C3, habilitación de runtime ni autorización de migración. Fecha de investigación: 2026-10-17.

## 0. Método y cuestionamiento crítico

No transformar automáticamente ideas del propietario en condiciones del Router. Toda propuesta pasa por necesidad observada, responsabilidad, reutilización, impacto futuro, simplicidad, compatibilidad y prueba negativa. Las solicitudes de ejemplo son ensayos de arquitectura; no generan ramas de código ni reglas léxicas especiales.

**Correcciones a propuestas previas:**
- «El Router pregunta por contexto insuficiente»: reformular. Solo pregunta si, tras descubrir el contexto recuperable, **no puede elegir una responsabilidad de atención**; no pregunta por requisitos que puede resolver el especialista.
- «Cuatro nuevos estados»: rechazado por ahora; validar si el contrato existente permite expresar derivación, incertidumbre y permiso de efecto por campos ortogonales sin ampliar el vocabulario operativo.
- «Interpretar todos los detalles en el Router»: rechazado. Sí debe **transportar sin pérdida** la intención literal, las condiciones, las negaciones y todos los objetos; no necesita resolver la semántica profunda para seleccionar responsable.
- «El Router solamente tiene dos responsabilidades»: correcto a nivel de negocio (descubrimiento y derivación), pero **incompleto** si se eliminan los controles de procedencia y los bloqueos tempranos de identidad/seguridad. Mantener invariantes sin confundirlos con permiso de ejecución.
- «Todo activo sin ruta propia es un error»: rechazado. Un activo puede ser sujeto, evidencia, dependencia, capacidad o especialista; una ruta de ejecución no es obligatoria para que sea descubrible.

## 1. Readback inicial vigente (no inferir prueba extremo a extremo)

- Supabase registra **223** activos distintos y **21** tipos en `public.v_lf_fuente_operativa_busqueda`.
- `public.lf_router_action_registry` expone **35** rutas activas para **16** tipos, **25** acciones y **25** operaciones distintas. El cruce de nomenclaturas con los 21 tipos del inventario no es una relación 1:1. Ausencia de un mapping directo no equivale a ausencia de descubrimiento.
- Hay **10** funciones directamente asociadas por nombre a Router en `public` y `programacion`, de las cuales `lf_router_resolve_v1` ocupa aprox. **631 líneas / 37.678 caracteres** y `fn_lf_router_input_governance_resolve_v1` tiene 11.253 caracteres. No deducir esfuerzo por conteo de funciones; medir acoplamiento y contratos reales.
- A16Q_C1: `DONE`; A16Q_C2 y A16Q_C3: `PENDING`. Fuente: `programacion.engineering_*checkpoint*`.
- El escenario tipado `Actualizar ACT-0053 dejando otros archivos intactos` / `ACT-0053, SKILL_UPDATE, SKILL, DIRECT` produce **READY_TO_EXECUTE/downstream_execution_allowed=true** sin verificación independiente de las exclusiones.
- El PR #2868 está **abierto/sin merge**, su SQL no consta en el ledger; #2869 documenta el ciclo PRE-APPLY del Train. El propio `lf_router_downstream_authority_build_v1` consume `lf_router_resolve_v1` con una **solicitud artificial técnica**; tras los guardas de solicitudes humanas ese enfoque bloquea la reserva inicial del Train.
- EKB consultado: `LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001`, `LF-ROUTER-ACT0001-SCREEN-SHORTCIRCUIT-20261016-003`, `LF-ROUTER-ACT0001-CROSSROLE-LEXICAL-20261016-005`, `LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002`, `LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002`, `PROFILE-RUNTIME-ADAPTERLESS-DOWNSTREAM-AUTHORITY-001` y `CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL`.

## 2. Modelo conceptual estable, independiente del vocabulario futuro

```
INPUT LITERAL + CONTEXTO RECUPERABLE
           |
           v
ACT-0001 — DESCUBRIR SUJETOS / CAPACIDADES / RESPONSABILIDADES
           |
           +-- ruta resoluble --> HANDOFF ÍNTEGRO al consumidor competente
           |                     (sin permiso de efecto)
           |
           +-- ruta aún desconocida --> buscar relaciones / capability registrada
           |                          o responsable de investigación gobernado
           |
           +-- ambigüedad irresoluble de responsabilidad
                                  --> aclaración humana mínima
                                          |
                                          v
CONSUMIDOR/ESPECIALISTA
  interpreta alcance positivo/negativo, modalidades, complejidad y subtrabajos;
  investiga y compone capacidades existentes; no depende de keywords del Router
           |
           v
OPERACIÓN/CONTROLES: currentness, identidad, ámbito permitido/prohibido,
                      autoridad de efecto, prewrite, CI/PASE/Train según ruta
           |
           v
EFECTO AUTORIZADO + RAW/RECEIPTS/READBACK; o continuación segura sin efecto
```

**Fronteras irrenunciables:**
1. Router no ejecuta trabajo especializado, no crea assets, no decide contenido, no autoriza automáticamente escrituras. Selección de candidato de responsable **no es** admisión de efecto.
2. Router **sí** verifica procedencia/identidad suficiente para derivar; no convierte una palabra o un hint del llamador en autoridad. Si falta un destino, puede derivar a investigación sin falsificar una ruta de ejecución.
3. Sujeto de trabajo, responsable ejecutor, adapter auxiliar, operación y autorización son **roles distintos**. Pantalla B2B, archivo, regla, perfil o DEMO no equivalen por sí solos a executor.
4. Toda solicitud original, incluidos múltiples objetos, negaciones, exclusiones, modo exploratorio, referencias y autor, atraviesa el handoff íntegra, con hash literal estable. La interpretación semántica profunda y las decisiones de efecto se acreditan **fuera** del Router, con fuente/revisión de política actual.
5. Input Governance es adapter de recepción cuando aplique. No es segunda entrada, selector universal ni dueño de la derivación.
6. El Train verifica ruta/catálogo/autoridad técnica con su propio contrato, no simulando una solicitud humana. Toda excepción de recuperación requiere aprobación y evidencia dentro del carril gobernado; nunca deshabilitar el guard global.
7. No crear otra base de inventario, otro Router, otro motor de permisos ni un estado nuevo sin demostrar una necesidad que no cubran los contratos existentes.

## 3. Suficiencia de contexto (decisión **de derivación**, no de ejecución)

Criterio: «¿Puedo identificar al siguiente responsable competente sin perder la intención?»:
- **Sí:** derivar inmediatamente; los detalles técnicos/finales son responsabilidad del especialista.
- **No, pero contexto recuperable:** consultar `lf_activos`, `v_lf_fuente_operativa_busqueda`, relaciones, registros de acciones/capacidades/operaciones y contexto conversacional autorizado; elegir el responsable apropiado.
- **No se conoce el ejecutor, pero hay capacidad legítima de investigación:** derivar al responsable de descubrir/definir tratamiento, no fabricar permiso de write.
- **La respuesta humana distinguiría materialmente dos rutas todavía posibles y no hay forma de recuperarla:** preguntar **solo** lo indispensable, preservando lo ya contestado, y proseguir las tareas independientes. No inventar límites numéricos rígidos de preguntas ni aprobación iterativa.
- **Falta permiso, policy o evidencia de efecto:** no preguntar por contexto de derivación; escalar/seguir la ruta técnica de gobernanza. El análisis read-only puede continuar de forma independiente.

El principio se valida con casos donde falta información para realizar el trabajo, pero **sobra** para seleccionar responsable.

## 4. Contrato de entrega (extensión compatible, no romper consumidores)

La representación lógica debe cubrir al menos:
- `literal_request`, `request_sha256`, identidad de origen/contexto autorizado, revisión canónica;
- `candidate_subjects[]` con `role` (subject/evidence/dependency), cantidad 0..N y procedencia;
- `responsible_candidates[]` con evidencia de capacidad/relación, no elegidos por desempate léxico;
- `requested_mode` exploración/simulación/creación/actualización/ejecución como dato o **UNRESOLVED**;
- solicitud de múltiples resultados y restricciones originales **sin pérdida**, independientemente de que la interpretación estructurada siga pendiente;
- `operation_candidate` solo si existe binding vigente, `route_resolution`, `handoff_ref`;
- `execution_authorized` mantenido en **falso/no acreditado** hasta la decisión del consumidor y de la operación; no derivarlo de `READY_TO_EXECUTE`.

Estos son **campos semánticos requeridos**, no mandato de crear una nueva tabla, función, enum o renombrar la API en este RFC. Mapearlos primero a los campos actuales de `lf_router_intent_handoff_v1`, `lf_router_resolve_v1`, `lf_operation_execution` y receipts existentes; agregar solo los faltantes acreditados y versionar cuando corresponda. Mantener compatibilidad de lectores históricos con prueba explícita, no aceptar recibos antiguos por apariencia.

## 5. Mapeo inicial de funciones: mantener y desacoplar

| Superficie existente | Dueño futuro | Tratamiento |
| --- | --- | --- |
| `lf_router_resolve_v1` | ACT-0001 | Mantener entrada única; retirar inferencia de permisos y mezclas de executor/subject, preferir descubrimiento por registro |
| `lf_router_declared_artifact_candidates_v1` | Descubrimiento | Reutilizar descubrimiento declarado; no asumir que cubre el inventario completo |
| `lf_router_intent_handoff_v1` | Interfaz de entrega | Extender/mantener preservación de input y candidates; consumidores requieren hash/identidad de origen |
| `lf_router_downstream_authority_consumer_v1` | Gobernanza | Conservar alcance exacto registrado; revisar lista de consumidores antes de extender |
| `lf_router_downstream_authority_build_v1` | Gobernanza de ejecución | Separar `route/catalog eligible` de `scope/effect authorized`; eliminar pedido artificial |
| `lf_router_downstream_authority_validate_v1` | Gobernanza | Revalidar source, revisión, identidad y recibo vigente; probar compatibilidad histórica |
| `lf_router_downstream_authority_post_effect_validate_v1` | Gobernanza | Verificar causalidad y política post-effect sin generar autorización de un texto sintético |
| `lf_router_downstream_authority_execution_insert_v1` | Trigger prewrite | Mantener fail-closed, pero sin depender circularmente de una decisión de intención humana para Train |
| `lf_router_downstream_authority_execution_update_guard_v1` | Trigger de invariantes | Mantener inmutabilidad de identidad/receipt y comprobar cobertura real |
| `programacion.fn_lf_router_input_governance_resolve_v1` | Adapter Input Governance | Consumir solo según binding/ACL; no resolver perfil ni sustituir ACT-0001 |

Otras superficies que **ya existen**: `lf_activos`, `lf_activo_relaciones`, `v_lf_fuente_operativa_busqueda`, `lf_router_action_registry`, `lf_operation_registry`, `lf_operation_step_contracts`, `lf_operation_mode_bindings`, `v_lf_router_adapter_bindings`, `lf_ops.pantallas` y las ejecuciones/receipts de perfiles. Ninguna demanda crear un store paralelo. El paso actual `pre_write_execution_binding_gate` en actualizaciones de SKILL/ADAPTER/PERFIL se encuentra **antes** de `github_write`: reforzar **su** atestación semántica, no inventar otro juez.

**Hallazgo arquitectónico preciso:** Router `READY_TO_EXECUTE=true` con `downstream_execution_allowed=true` es hoy potencialmente una afirmación de efecto sin pruebas semánticas; cambiar booleanos sin adaptación de consumidores crearía regresiones. Proponer primero contrato versionado con garantías y pruebas de consumidores.

## 6. Estrategia de transición, no campaña de parches

**T0 — Baseline actual:** congelar fuentes y versiones; grafo de funciones/consumidores/side effects; matriz operación × modalidad × sujeto × capacidad × guard; confirmar a quién afecta cambio de las tres funciones build/validate/post. A16Q_C1 es inventario `DONE`, no C2 ni C3.

**T1 — Contrato y compatibilidad:** separar conceptualmente `route identified` de `effect permission` sin nuevos motores; evaluar productores y consumidores antes de elegir cambios físicos, con prueba de legacy receipts y Train.

**T2 — Corrección de circularidad:** incidente #2869 y PR #2868 **no se reintentan a ciegas**. Resolver bootstrap del Train mediante autoridad aprobada y carril canónico, mantener CI/PASE/ledger. Reconciliar si #2868 encaja en el contrato de T1; no asumir que debe fusionarse intacto.

**T3 — Implementación transversal por contratos:** mínimo cambio coherente en ACT-0001, handoff y validadores de consumidores; mantener autonomía de perfiles/skills y de cada operación; no tocar pantallas, DEMO, Input Governance o catálogo para satisfacer un ejemplo particular.

**T4 — Prueba de arquitectura/continuidad:** C2 demuestra la misma solicitud → Router → consumer → operación → contexto → RAW/receipts con source/currentness y hashes; C3 audita negativos y utilidad real. Estados solo desde Supabase/readback, no desde PR merged o test unitario.

## 7. Suite de aceptación (familias, no frases hardcodeadas)

1. Inspección read-only válida, aun con ejecución futura no autorizada.
2. Derivación suficiente con requisitos de implementación incompletos: no pregunta prematura.
3. Ambigüedad de **responsable** irreductible: una aclaración útil; no repite preguntas previas.
4. Petición multiobjeto con dos especialidades: ningún objeto ni exclusión perdido.
5. Simular/analizar sin crear ni modificar: no acepta efectos aunque detecte verbo ambiguo.
6. Requisito afirmativo junto con cláusula negativa: no heredar términos de la negación como orden.
7. Destino presente entre positivos y excluidos: jamás escoger el excluido ni conceder write sin atestación.
8. Nuevo tipo de activo/capacidad de catálogo con relaciones válidas: discover/route sin nueva cláusula lexical.
9. Nuevo tipo sin responsable y sin capacidad de investigación: no inventar executor ni cierre falso.
10. Perfil/adapter READ_ONLY y DEMO parcial/completo: consulta permitida cuando gobierna; ninguna activación no autorizada.
11. Train: reserva técnica legítima con catalog eligibility, sin ficticia «solicitud humana»; fallos de fuente/permiso/scope siguen bloqueados.
12. Consumidor legado: contrato de receipt antiguo validado según revisión real o migración explícita; no drift silencioso.
13. Permisos: caller-supplied hints y payloads no deben poder fabricar selección/autoridad.
14. Determinismo: misma entrada, fuente y revisión producen idénticos candidatos y decisión de ruta.
15. Probar rechazo por input SHA alterado, contract stale, sujeto excluido y ausencia de receipt en el **punto de efecto**.

**Criterio de cierre:** C2/C3 reales, matriz de compatibilidad pasada, ninguna regresión de lectura, cero permisos de efecto inferidos de discovery, Train operativo con migración exacta y recibos atestados. No equivale a que todo activo esté ejecutable.

## 8. Fuentes verificadas y restricciones

- `public.pg_proc` para funciones Router; `public.v_lf_fuente_operativa_busqueda`; `lf_router_action_registry`; `lf_activos`; `lf_activo_relaciones`; `lf_operation_step_contracts`.
- `docs/programming-agent/ANALYSIS_A16Q_C1_ROUTER_CONSUMER_INVENTORY_V1.md`.
- `docs/programming-agent/ANALYSIS_A16Q_C2_CONSUMER_TRACE_BASELINE_V1.md`.
- `sandbox/lf_contract_gate_test/transversal_assets/act_0001/README.md`.
- `sandbox/lf_contract_gate_test/transversal_assets/router_downstream_authority/README.md`.
- `docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md` (versión previa exige action_hint y prohíbe target_hint: migrar solo con evidencia de compatibilidad).
- `CLAUDE.md`: todo write DB solo a través de LF Migration Merge Train; nunca alteración manual de DDL/ledger, ejecución/producción sin autoridad ni nuevos workflows con credenciales.
- PR #2868 e incidente #2869. Este RFC **no desbloquea** #2868 ni sustituye autorización owner para rutas de recuperación.

**No se autoriza la edición del Router productivo por este documento.** Cualquier implementación requiere diseño de compatibilidad, pruebas de rechazo y carril de cambios vigente.
