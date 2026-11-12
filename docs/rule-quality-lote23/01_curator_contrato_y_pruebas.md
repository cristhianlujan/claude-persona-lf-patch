# Lote 23 — Curator mínimo gobernado, contrato sandbox PG18

**Tipo:** IMPLEMENTACIÓN EXPERIMENTAL EN PG18 AISLADO. **Producción: NO-GO / UNVERIFIED**. El Curator de este lote es **SQL determinista**, escrito/evaluado por GPT-6 (mismo modelo, no independiente); NO es el Curator real de Input Governance ni acredita un modelo separado, Step70 u OIDC.

## Fuentes leídas antes de implementar
- EKB INPUT GOVERNANCE LF V1.4: ruta USUARIO → ACT-0001 → PERFIL → RUN → PASOS → IG (si aplica) → VALIDACIÓN → JUEZ → REGISTRO → CIERRE; estado CANDIDATO VERIFICADO PARCIALMENTE.
- L13: `rule_quality_l13.projects/actors/families/category_family_map/rules` (diseño PG18). Dueño de proyecto y de familia distinto de `SUPER_ADMIN`.
- L14: `quality_apply_envelope` (tiene preflight y crea `activation_tickets` **antes** de invocar el gate congelado). L17: `l17_assert_request_current_user_v2`, `l17_verify_signed_claim_v2` y roles `SET LOCAL ROLE` con HMAC fixture (no Supabase Auth real).
- L18: A_NEW/B_CORRECTED/C_SALY_NEW, 12 etapas; Step70 y cierre nativos NO_PROBADO.
- L20: fuente/status sincronizados solo PG18, experimentos sujetos a rollback, sin migración productiva; L22 es documental de requisitos ledger.
- Base exacta Git SHA `48f1e316d81c83ca2f880372a3a050b456c6b3ab`.

## Diseño sin modificar funciones gates ni L14
```text
CANDIDATO LF / SALY
    ↓
L13 QUALITY_PREPARED / EN_REVISION
    ↓
L17 actor firmado + owner de familia/proyecto
    ↓
l23_curator_evaluate_v1()
    ├─ FAMILIA / MAPA aprobado por proyecto
    ├─ MISMO CODIGO o descripción+config exacta contra VIGENTE
    ├─ VALOR_CONFIG con clave común y valor distinto → revisión humana
    └─ HMAC SHA256 de dictamen + SHA256 de estado de candidato / VIGENTE
    ↓
ACEPTAR / DEVOLVER_CON_MOTIVO / ESCALAR_A_HUMANO
    ↓
L14 quality_apply_envelope_v2() NO MODIFICADO
    ↓
INSERT activation_ticket(ARMED)
    ↓
trg_l23_curator_before_activation (trigger nuevo)
    ├─ falta ACEPTAR → BLOCK_L23_CURATOR_NOT_ACCEPTED
    ├─ identidad/owner no coincide → BLOCK
    ├─ HMAC manipulado → BLOCK_L23_CURATOR_SEAL_INVALID
    ├─ candidato, familia o universo VIGENTE alterados → BLOCK_L23_CURATOR_SNAPSHOT_STALE
    └─ ACEPTAR verificado → permite el ticket
    ↓
GATE LF congelado / SALY fixture (SIN EDITAR)
    ↓
READBACK y ROLLBACK de escenarios PG18
```

## Contrato de veredicto
- `verdict`: `ACEPTAR`, `DEVOLVER_CON_MOTIVO`, `ESCALAR_A_HUMANO`. No hay cuarto estado implícito de "aprobado por silencio".
- `reason_code`, `reason_text`, `evidence`: familia, categoría, regla duplicada/conflictiva, recuentos, identidad fixture, huella de candidato.
- `candidate_fingerprint_sha256`: digest del candidato, datos fuente, mapas, owner, corrección y conjuntos VIGENTE (fuente y calidad). Se vuelve a calcular **antes del armado del ticket**.
- `seal_hmac_sha256`: sello de registro calculado con clave efímera privada PG18 de L17. No se comparte al cliente. La clave de fixture nunca equivale a credencial productiva.
- La tabla `l23_curator_verdicts` no tiene grants de lectura o DML a roles tenants. El escritor interno determina el actor desde el claim verificado; ningún parámetro decide arbitrariamente `ACEPTAR`.

**Límite semántico:** comparación determinista por categoría/familia, código/descripcion y claves JSON de `valor_config`. Pueden existir conflictos sin clave común, colisiones de significado y excepciones de producto. `ACEPTAR` en sandbox indica ausencia de esos bloqueos **detectables**, no revisión semántica completa ni aprobación humana.

## Pruebas requeridas
| ID | Tipo | Condición de aceptación |
|---|---|---|
| A_NEW | Positivo | LF nueva → Curator ACEPTAR → L14 apply LF APPLIED + READY, ROLLBACK |
| B_CORRECTED | Positivo | LF con sucesora explícita → Curator ACEPTAR → gate LF + READY, ROLLBACK |
| C_SALY_NEW | Positivo | SALY nueva → Curator ACEPTAR → apply sintético SALY READY, ROLLBACK |
| N1 | Negativo | Dictamen ausente bloquea antes del gate |
| N2 | Negativo | Duplicado exacto `VIGENTE` → DEVOLVER_CON_MOTIVO |
| N3 | Negativo | Clave valor_config contradictoria → ESCALAR_A_HUMANO |
| N4 | Negativo | Familia inexistente bloqueada por el contrato L13 |
| N5 | Negativo | Owner de familia equivocado → DEVOLVER_CON_MOTIVO |
| N6 | Negativo | Dictamen manipulado queda bloqueado por HMAC |
| N7 | Negativo | DML directo a dictámenes desde rol owner → 42501 |
| N8 | Negativo | Candidato cambiado después de aceptación → stale SHA, bloqueo |

**Estado de las pruebas:** se determinará mediante GitHub Actions real; este documento describe contrato, no afirma PASS.

## Invariantes / riesgos
- **Gates congelados PG18** (MD5 a comparar antes/después): apply `86b0494984edf95cf0f9c0a0df67000b`, capture_record `89cbfac4162dbc9f8ecca59f2c3ab4c3`, citation_verify `773a62783baa5edbe967200cac66b8c3`, L8 `522d12f0843be1da3c785cef3c0bf3fc`.
- `d7fe763c...` corresponde a `lf_rule_promotion_apply_v1` legada en el Supabase vivo, distinto del artefacto congelado PG18; **no es una discrepancia de MD5**.
- No se altera `01..14` SQL, gates, migraciones, `main`, Supabase ni scripts existentes. Se agrega exclusivamente `15_l23_curator_stage_pg18.sql`, script/test CI y documentación.
- La seguridad de ticket pre-gate opera en banco PG18; se requiere verificación del Curator real, de actores reales y de consumidores en producción antes de cualquier adopción.
