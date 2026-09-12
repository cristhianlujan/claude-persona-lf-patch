insert into lf_ops.reglas_pantallas(regla_id,pantalla_id,nota)
select r.id,56,'Trazabilidad estructural: B2B-RULE-DESIGN-001 es transversal y ya aplica al shell B2B; enlace requerido para resolver design_system_id de B2B-AUTH-006 sin duplicar la regla.'
from lf_ops.reglas r
where r.codigo='B2B-RULE-DESIGN-001'
  and r.es_transversal=true
  and not exists(select 1 from lf_ops.reglas_pantallas rp where rp.regla_id=r.id and rp.pantalla_id=56);