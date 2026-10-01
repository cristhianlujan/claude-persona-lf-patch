-- DEC-INPUT-GOV-IMPL-DEPENDENCY-001: la implementación pendiente de plataforma no bloquea la preparación de la historia.
-- Aprobada por Cristhian Luján el 2026-10-01 (plan IG_CURATOR_VALIDATOR_REFACTOR_V2; se implementa en M1.5 y M3.4).

insert into transversal.decision_log(adr, titulo, decision, razon, impacto, estado)
values (
  'DEC-INPUT-GOV-IMPL-DEPENDENCY-001',
  'Implementación pendiente de plataforma no bloquea la preparación de la historia',
  'Cuando una familia tiene la definición canónica completa y lo único que falta es la implementación de una capacidad o proveedor de plataforma (implementation_pending, runtime_provider_pending o ningún proveedor runtime-ready), Input Governance marca implementation_ready_status = READY_WITH_DEPENDENCY con referencia rastreable al trabajo de plataforma del que depende, en lugar de NOT_READY. qa_ready_status y production_ready_status siguen BLOCKED hasta que esa dependencia esté resuelta. No aplica cuando falta definición, hay una decisión pendiente en la regla o el contrato está incompleto.',
  'Aprobada por Cristhian Luján el 2026-10-01. Simulación con ROLLBACK sobre el clasificador real (13 pantallas x 47 familias): 60 celdas bloqueadas solo por implementación pendiente de plataforma (45,7% a 55,8% listas); 89 si se combina con reglas transversales por alcance y promoción de reglas.',
  'Se implementa en IG_CURATOR_VALIDATOR_REFACTOR_V2: M1.5 (contrato de incertidumbre tipada, nuevo estado) y M3.4 (estado de ejecución), con R16 y R17. Hasta entonces el clasificador vigente no cambia. Sin cambio de promotion ni production.',
  'vigente'
)
on conflict (adr) do update set titulo=excluded.titulo, decision=excluded.decision, razon=excluded.razon, impacto=excluded.impacto, estado='vigente';
