# LF — Lote 14 | Capa envolvente de calidad para promoción (PG18 sandbox)

**Estado:** SANDBOX_VERIFIED / **NO-GO y UNVERIFIED para producción**.
**Ejecución de pruebas:** [GitHub Actions 43291127976](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43291127976), commit bajo prueba `91c0ae3988083cb1f397d0997c79889c77af760b`.
**Lote de referencia:** L13 `d1e62d0ca8f1b45273cf1c4827a700f83a1c0761`; L11B copiado con blob Git idéntico.
**Fuente de gobernanza:** EKB `INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4`, de estado CANDIDATO VERIFICADO PARCIALMENTE; los contratos live no se sustituyen por este candidato.

## Objetivo y contrato

```text
Fuente LF: lf_ops.reglas CANDIDATO      Fuente SALY (solo sintética): vigente=false
               │                                        │
               └────────── project_source_adapters ─────┘
                                      │
       sesión PostgreSQL autenticada: session_user; GUC solo comprobación de igualdad
                                      │
              quality_prepare_new(project,code,family)
                 ├─ valida perfil propietario (SUPER_ADMIN bloqueado)
                 ├─ valida familia del proyecto y mapeo aprobado
                 ├─ reviewed_at = reloj del servidor (no caller)
                 └─ next_review_at = reviewed_at + intervalo del proyecto
                                      │
                         EN_REVISION / no activo
                                      │
                   quality_apply_envelope(project,code,...)
                    ├─ ticket temporal autorizado y transaccional
                    ├─ LF: invoca apply congelado SIN modificarlo
                    ├─ SALY: adaptador mecánico SINTÉTICO
                    ├─ trigger impide activar fuente sin metadata+ticket
                    ├─ readback fuente activa y VIGENTE calidad
                    └─ READY solo cuando el gate devuelve APPLIED y RETURN READY
```

Cualquier fallo se trata como bloqueo y el SQL de prueba se ejecuta con rollback. El fixture L11B utiliza una cadena que **imita** el texto de procedencia oficial; es evidencia mecánica exclusivamente, **NO autorización nativa auténtica** de IG/Router/Step70/owner.

## Archivos añadidos (nunca migraciones)

| Archivo | Finalidad |
|---|---|
| `05_quality_wrapper_identity_and_prepare.sql` | Roles reales de PG, registro de adaptadores por proyecto, tabla de tickets, identidad `session_user`, `quality_prepare_new`; prohíbe fecha de revisión enviada por caller |
| `06_quality_wrapper_correction_guard.sql` | Sucesora explícita EN_REVISION; trigger de activación con metadatos; trigger de inmutabilidad de contenidos VIGENTE |
| `07_quality_wrapper_apply_and_acl.sql` | Wrapper común para LF/SALY; apply LF congelado; saly fixture; revocaciones GRANT y RLS; search_path confiable de detectores L13 |
| `test_pg18_lote14_quality_wrapper.py` | 18 casos reales: positivos, negativos por roles, cadena mecánica L11B y readback |
| `test_pg18_lote11b_mechanical_positive.py` | Copia exacta del fixture L11B existente en la rama de trabajo paralelo; misma firma Git |
| `.github/workflows/l14-quality-wrapper-pg18.yml` | PG18 nuevo y desechable, 28 pruebas L13 + inventario completo de scripts `test_pg18_*` |

El mapeo LF preserva las 15 familias propuestas del L13; solo `SECURITY` (LF) y `MOTOR_DISPONIBLE` (SALY) se marcaron `APPROVED` **dentro del fixture sintético** para ejercer las funciones. No es aprobación oficial de esas familias.

## Resultados reproducidos desde runner

| Paquete | Total | Aprobados | Estado de alcance |
|---|---:|---:|---|
| L13 PostgreSQL 18.6 | 28 | **28** | SANDBOX_VERIFIED |
| Todos los `test_pg18_*` inventariados | 15 scripts | **15** | SANDBOX_VERIFIED |
| Controles específicos L14 | 18 | **18** | SANDBOX_VERIFIED |
| Producción | 0 | 0 | **NOT_TESTED / NO-GO** |

Los scripts legados ejecutaron una base propia limpia; se corrigió la colisión de nombres de DB sin modificar los scripts históricos. Un primer CI falló por search_path y colisión; esas causas fueron corregidas solo en capa/calidad y el CI final cerró en success.

### Negativos pareados

| Negativo | Respuesta PostgreSQL real | Contraparte positiva |
|---|---|---|
| Sin familia | `23514 BLOCK_QUALITY_FAMILY_REQUIRED` | Familia LF existente + mapeo válido: `QUALITY_PREPARED` |
| Familia perteneciente al otro proyecto | `23514 BLOCK_QUALITY_FAMILY_PROJECT_MISMATCH` | LF `IDENTIDAD_SEGURIDAD` / SALY `MOTOR_DISPONIBLE` |
| GUC falsificado por reader | `42501 BLOCK_QUALITY_GUC_IDENTITY_MISMATCH` | Identidad derivada de `session_user=lf_owner_role` |
| DML directo sin GRANT | `42501 permission denied for table rules` | Escritura encapsulada `SECURITY DEFINER` bajo perfil dueño |
| SUPER_ADMIN | `42501 BLOCK_SUPER_ADMIN_APPROVAL` | Solo perfil del owner de proyecto |
| VIGENTE directa sin metadata | `23514 BLOCK_QUALITY_ACTIVE_METADATA_MISSING` | Metadatos asignados antes de promoción |
| VIGENTE directa sin ticket | `42501 BLOCK_QUALITY_NO_ACTIVATION_TICKET` | Wrapper autoriza ticket transaccional |
| Corrección sin sucesora | `23514 BLOCK_QUALITY_EXPLICIT_SUCCESSOR_REQUIRED` | Sucesora con nuevo código y EN_REVISION; original intacta |
| Fecha de revisión arbitraria | `23514 BLOCK_QUALITY_CALLER_REVIEW_TIME_FORBIDDEN` | Fecha generada por reloj PG |
| Cambio directo del contenido VIGENTE | `23514 BLOCK_QUALITY_ACTIVE_RULE_IN_PLACE_MUTATION` | Enmienda explícita en nueva sucesora |

### Caducidad y corrección

`list_review_due` permanece `STABLE` y se reutiliza sin modificación semántica: una regla vencida genera `PROPONER_REVISION` pero no cambia estado. Las correcciones usan `quality_propose_correction` y una sucesora con nuevo código `EN_REVISION`, sin modificar el texto de la vigente original. No se declara que exista aprobación del contenido semántico de esa sucesora.

### Cadena mecánica LF L11B

**CANDIDATO → familia → reviewed_at/next_review_at → captura L7/L8 fixture → owner fixture → apply congelado APPLIED → VIGENTE en fuente → VIGENTE en modelo de calidad → readback READY**, todo dentro de una transacción con `ROLLBACK` verificado. La identidad PG de prueba del owner es `lf_owner_role`; el dato de procedencia que hace positivo L11B es **sintético y no acredita una aprobación real**.

### MD5 inmutables (verificados dentro de PG18 antes y después)

| Función gate | MD5 exacto |
|---|---|
| `apply` | `86b0494984edf95cf0f9c0a0df67000b` |
| `capture_record` | `89cbfac4162dbc9f8ecca59f2c3ab4c3` |
| `citation_verify` | `773a62783baa5edbe967200cac66b8c3` |
| `l8_guard` | `522d12f0843be1da3c785cef3c0bf3fc` |

`01_execution_evidence.json` conserva los **18 resultados individuales**, el SHA-256 de su salida original `17ad9957f0647f12e0fac8143adebe5ebaab4659014fe3484cd39cfcbe6ad7d3` y los SHA-256 de cada uno de los 15 logs de regresión. `02_source_sha_readback.json` registra SHA-256 UTF-8 y Git blob SHA de cada archivo, con comparación estricta del diff desde L13.

## Bloqueos antes de producción

- **No usar directamente `session_user` como autenticación de producto.** Se probaron roles reales PostgreSQL en sandbox, pero falta integrar la identidad de producto autenticada y la autorización de perfil desde una fuente server-side confiable, incluyendo conexiones pooled y acceso privilegiado.
- **El GUC es falsificable como texto** por un usuario; el wrapper solo lo usa para detectar discrepancias con `session_user`; no funciona como prueba autónoma de identidad.
- **El fixture L11B es sintético**: no acredita Router, IG real, perfil dueño nativo, juez independiente ni autorización de escritura oficial.
- **No hay migración gobernada**, autorización de rollout, enlace oficial de SALY ni pruebas con reglas de producción. Las familias LF y sus owners siguen pendientes de decisión semántica.
- **No hay independencia de modelo Claude acreditada**: esta corrida fue producida/revisada en ChatGPT GPT-6.

**Resultado:** ejecución mecánica **SANDBOX_VERIFIED**; adopción y promoción a sistemas oficiales **NO-GO/UNVERIFIED**. Avance del alcance L14 en sandbox **100%**, avance a producción **0%**. No se modificó el SQL de ningún gate; no se ejecutó DDL/DML en Supabase vivo, merge ni RUN de producto.
