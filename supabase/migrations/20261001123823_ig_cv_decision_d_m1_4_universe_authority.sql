-- D-M1.4: autoridad del universo de 47 familias de Input Governance.
-- Dirección de Cristhian Luján (evento #19374, 2026-09-30). Plan IG_CURATOR_VALIDATOR_REFACTOR_V2, unidad M1.A4.
-- Además deja en Git el estado VIGENTE de B2B-RULE-STORY-READINESS-001, que se cambió en la base el 2026-09-30 01:44 UTC sin migración (drift R16).

insert into transversal.decision_log(adr, titulo, decision, razon, impacto, estado)
values (
  'DEC-INPUT-GOV-D-M1.4',
  'D-M1.4: autoridad del universo de 47 familias de Input Governance',
  'La autoridad del universo de 47 familias de Input Governance es la regla B2B-RULE-STORY-READINESS-001 en estado VIGENTE (promovida desde CANDIDATO). El contrato INPUT_READINESS_CONTRACT (canonical_universe_rule) debe apuntar a esta decisión; ese ajuste se ejecuta en la unidad M1.A4 por migración en Git.',
  'Dirección de Cristhian Luján registrada en el evento #19374 (2026-09-30), respuesta a la acción A2 de la propuesta v2.1 (#19371). Sin esta decisión registrada, M1.A4 y el universo usado desde L5 quedan bloqueados.',
  'Desbloquea M1.A4 (PAULO-124). Reconciliación de drift: la regla ya estaba VIGENTE en la base sin migración; esta migración la deja en Git. Sin cambio de promotion ni production.',
  'vigente'
)
on conflict (adr) do update set titulo=excluded.titulo, decision=excluded.decision, razon=excluded.razon, impacto=excluded.impacto, estado='vigente';

update lf_ops.reglas set estado = 'VIGENTE'
 where codigo = 'B2B-RULE-STORY-READINESS-001' and estado is distinct from 'VIGENTE';
