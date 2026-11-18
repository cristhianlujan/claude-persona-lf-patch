# PR-G — Registro simplificado de decisión del dueño (sin firma adicional)

**Estado:** Migración acotada en PR-G; no aplica AUTH-020 ni modifica el finalizador V2.

## Autoridad y decisión fuente

- Declaración del dueño de 2026-11-18 02:43 America/Lima: «Hay que modificar esa instruccion de la firma del dueno, que solo guarde un usuario y listo. No compliquemos mas el proceso».
- **Un solo usuario:** nombre canónico `Cristhian Luján` (se acepta alias textual `Cristhian Lujan` y se normaliza al nombre canónico existente). No se crea usuario, rol ni `owner_sub` nuevo.
- **Input nuevo:** `p_decision={"usuario":"Cristhian Lujan","veredicto":"APROBAR"}` o `RECHAZAR`. El veredicto sigue siendo explícito; la identidad no se autentica solo por el campo.
- Datos del parche, `source_sha256`, `proposal_sha256`, productor y clasificación vienen del RUN, Step50 y snapshot canónico; no se envían como declaración manual adicional.
- El registrador genera internamente `decision_record` de 6 claves **para conservar el contrato del child_guard**: `codigo_regla`, `propuesta_sha256`, `veredicto`, `decisor`, `fecha`, `frase_literal`. `frase_literal='OWNER_USERNAME_ONLY_NO_SIGNED_PHRASE'` es un marcador técnico, **no** una frase ni firma pronunciada por el dueño. `fecha` proviene de `clock_timestamp()`. SHA256 sobre JSONB es integridad, **no firma criptográfica**.
- `identity_mode='USERNAME_ONLY_UNVERIFIED'` comunica expresamente que **no está acreditada la identidad física**. `public.lf_ig_project_owner_v2` conserva su identidad documental antigua, como origen canónico de nombre y UUID temporal.

## Matriz MD5 pre/post del despliegue (SELECT y proyección sobre definición exacta)

| Objeto | Antes | Después esperado | Cambio |
|---|---|---|---|
| `pg_get_functiondef(public.lf_ig_rule_owner_decide_v2)` | `2d6f2592e8f7e002ab29f212bcca0663` | `e9bd839b8978a3f7872dd82a104ce99c` | 13 sustituciones controladas, sin alterar gates de RUN/Step70/Step50 |
| `lf_ig_owner_decision_v2_identity_mode_check` | `f2e2c80a1d8e7d85ac15b7238df02a2b` | `e1c17dcff3b03c5a9623e77aa1674cae` | Cambia literal permitido de `UNVERIFIED_CHAT_DECLARATION` a `USERNAME_ONLY_UNVERIFIED` |
| Columna `identity_mode` | `text NOT NULL DEFAULT UNVERIFIED_CHAT_DECLARATION` | `text NOT NULL DEFAULT USERNAME_ONLY_UNVERIFIED` | Solo DEFAULT; misma columna y nulabilidad |
| `decisor` + CHECK | `bd57f7a70e4779163461484d692ae643` | Igual | Solo dueño canónico |
| `proponente` + CHECK | `313efdc822c8bcfecba76310176b1a83` | Igual | No se permite autoaprobación documental del productor |
| `owner_sub` | UUID no nulo documental | Igual | No es un `sub` autenticado; no inventar identificación |
| `literal_phrase` + CHECK | `9db076b5f5b46d68b2235e41498d1e67` | Igual | Marcador técnico generado por el registrador, no aportado por usuario |
| `decision_record_sha256` + CHECK | `28638de4e0f6e30f28561d73cae2eb87` | Igual | Hash de integridad con SHA, no firma |
| `source_sha256` + CHECK | `f0a4aae0afae7feba813f189f7f13264` | Igual | Misma obligatoriedad de snapshot |
| `proposal_sha256` + CHECK | `92de2be0f97f372720dbb7b84112d791` | Igual | Mismo SHA del parche |
| `lf_ig_rule_finalize_v2` | `9d1a771fe5dd8b466b76071b582f19fa` | Igual | El gate FUNCTIONAL sigue intacto |
| `lf_ig_rule_child_guard_v2` | `ce5d02fc728ec18fc0ab1963364c392c` | Igual | Conserva six-field downstream, SHA y separación |
| `lf_ig_rule_cycle_once_v3` | `1c5ba0c02d2a24f6a0fd7bdfbacd5f6b` | Igual | Conserva ruta nativa |
| `lf_ig_project_owner_v2` | Nombre/UUID/mode `UNVERIFIED_CHAT_DECLARATION` | Igual | No se crea ni promueve usuario |

**Control de permisos ya verificado:** `EXECUTE` de `lf_ig_rule_owner_decide_v2` solo para `postgres` y `service_role`; `anon` y `authenticated` sin permiso. El nuevo nombre ingresado **no demuestra autoría real** de quien invoca el servicio privilegiado.

## ¿La evidencia técnica del Train puede ser recibo de impacto FUNCTIONAL?

| Evidencia | Estado / límite |
|---|---|
| Train: PG17 BEGIN/ROLLBACK, hashes, verificación independiente de base, CI y tests negativos | Demuestra comportamiento SQL acotado en ambiente de prueba; **no equivale automáticamente** a impacto independiente completo de cambio funcional |
| AUTH-020: riesgo de seguridad y consumidor de recuperación | Requiere evidencia del flujo de login/soporte, revocación de clave previa, caducidad, reinicio IDV, no sesión antes de nueva contraseña, correo actualizado atómicamente, MFA normal y control de permiso 38 |
| `lf_ig_rule_finalize_v2` | `change_kind=FUNCTIONAL` sigue bloqueado incondicionalmente con `LF_IG_VIGENTE_FUNCTIONAL_IMPACT_RECEIPT_MISSING` |
| Requisito que sí necesita una nueva decisión del dueño | **Determinar expresamente si la evidencia técnica del Train será suficiente como evaluación independiente de impacto de reglas funcionales y qué checks, hashes y aceptación verificable deben habilitar ese gate.** PR-G no lo decide ni lo implementa |
| Autorización de AUTH-020 | NO-GO, fuera de PR-G |

## Prueba gobernada

Runner temporal real PostgreSQL17: crea solo una **simulación inequívocamente etiquetada** de RUN/Step50/Step70, invoca el **registrador V2 real en camino RECHAZAR**, comprueba decisión temporal con usuario canónico y parche/hash, rechaza otro usuario, y ejecuta ROLLBACK completo. Nueva conexión comprueba 0 decisiones, función y constraint originales restaurados, tres reglas AUTH de fixture intactas. La evidencia de fixture **no** es recibo semántico real ni decisión del dueño persistida.

**Fuera de alcance:** cambios de AUTH-018/019/020, permisos, políticas, `lf_ig_rule_change_v2` y `lf_ig_rule_finalize_v2`; no se toca PR-E #4080, que permanece DRAFT.
