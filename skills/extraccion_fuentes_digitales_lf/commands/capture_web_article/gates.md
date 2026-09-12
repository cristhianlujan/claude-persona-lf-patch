# gates

Owner: SKILL_EXTRACCION_FUENTES_DIGITALES_LF
Command: capture_web_article
Estado: CANDIDATO_READ_ONLY

GATE_00: validar operation_code en lf_operation_registry
GATE_01: validar actor_role contra roles_matrix.md
GATE_02: crear o simular run según modo
GATE_03: validar formato URL
GATE_04: resolver fuente en sbx_competitive_sources si aplica
GATE_05: obtener contenido o registrar bloqueo técnico
GATE_06: registrar url_solicitada, url_final y redirección
GATE_07: verificar duplicados contra url_hash
GATE_08: extraer evidencia literal sin inferir
GATE_09: validar evidencia mínima
GATE_10: validar log_key contra lf_log_config
GATE_11: escribir solo si modo sandbox lo permite
GATE_12: registrar lf_log_operativo
GATE_13: ejecutar readback obligatorio
GATE_14: preparar evidencia para revisión humana
GATE_15: emitir final_state y flow_terminated=true
