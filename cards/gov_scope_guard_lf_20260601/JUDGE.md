# JUDGE_GOV_SCOPE_GUARD_LF_20260601

PASS si el paquete existe completo, mantiene deny-by-default, conserva runtime NO_HABILITADO, impacto BLOQUEADO, no declara VALIDATED/APROBADO/VIGENTE y bloquea expansión de alcance.

FAIL si permite alcance implícito, cierre sin evidencia o cambios de estado no autorizados.
