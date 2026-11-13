# LF — cierre del ciclo de reglas | candidato fail-closed
## Estado y alcance
Código **determinista de planificación**, sin efecto: no ejecuta SQL, no crea RUN,
no invoca GPT/Claude, no valida JWT, no firma decisiones y no concede escrituras.
El despliegue/activación está **BLOQUEADO** hasta que un adaptador oficial con
recibo autenticado entregue los datos `trusted` (nunca desde prompts).

Ruta objetivo: ACT-0001 → perfil → RUN único → IG → propuesta juzgada →
decisión humana autenticada → operación hija oficial → Validator/readback →
promoción explícita y autenticada → VIGENTE → cierre.

| Caso | Operación/transportador | Autorización |
|---|---|---|
| Nueva | CREACION_REGLA_LF / RULE_CREATE_APPLY | pendiente opener |
| CANDIDATO | ACTUALIZACION_REGLA_LF / RULE_UPDATE_APPLY | escritor existente, DOCUMENTARY_ONLY |
| VIGENTE | ACTUALIZACION_DB_LF / LF Migration Merge Train | nunca reescribir con candidate writer |
| Promoción | PROMOCION_REGLA_LF, RPC existentes | falta binding de identidad B06/B08 y registro |
| Owner de `lf_activos` | ACTUALIZACION_DB_LF / Merge Train | preimagen SHA + owner LF verificado |
| Despacho native | Issue/OIDC/Edge existente | falta proveedor GPT_NATIVE independiente atestado |

Nunca se reutilizan RUN; el hash debe indicar dominio/preimagen, y la firma
humana ha de cubrir scope exacto (create/update, source, proposal y promotion).
Owner de proyecto LF y SALY NO es un rol `SUPER_ADMIN` genérico. Evitar
aparentar autoridad con `HUMAN:...` sin identidad verificada.

### Límites de prueba
`node --test sandbox/lf_contract_gate_test/input_governance_lifecycle/test_lifecycle_gate.mjs`
Prueba planificación en aislamiento; **no** acredita función Postgres, Edge,
modelo nativo, firma humana real, IAM, backup/PITR o E2E desplegado.

### Evidencia y bloqueos consultados
- EKB INPUT GOVERNANCE LF V1.4.
- Supabase: EJECUCION_PERFIL_LF READ_ONLY; RULE_CREATE_APPLY opener NULL;
  RULE_UPDATE_APPLY opener instalado, candidate-only.
- pg_get_functiondef: lf_rule_promotion_decide_v1 solo comprueba `HUMAN:...`;
  PROMOCION_REGLA_LF ausente de registry; promoción RPC service_role.
- EKB LF-PROFILE-GPT-NATIVE-DISPATCH-MISSING-001 ACTIVO.
- L21 02_matriz_bloqueos_produccion.md: B06_OWNER/B08_IDENTITY/B13_BACKUP/B14_RESTORE ABIERTO.
- Router al pedir ejecución de DB genérica: BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED.
- issue #3779: custodia SUPER_ADMIN sobre reglas NO implica firma semántica.
### Para habilitar el siguiente lote
1. Firmar binding LF/SALY (project_code, owner_profile_code, actor sub, scope) y probar JWT/issuer/aud/JWKS + negativos.
2. Elegir y acreditar proveedor nativo invocable + juez independiente; jamás simular RAW.
3. Cerrar preflight de backup/PITR/restore y obtener paso Router de escritura de DB con scope exacto.
4. Instalar opener RULE_CREATE_APPLY, escritor autorizado de corrección VIGENTE y contrato/registro PROMOCION_REGLA_LF mediante un PR de **una sola migración** en Merge Train.
5. Vincular este gate como librería interna de Edge existente, no como nuevo dispatcher; E2E exact-run + readback. Mientras tanto, solo es candidato.
