insert into lf_ops.reglas_pantallas(regla_id,pantalla_id,nota)
select r.id,56,'Trazabilidad estructural del módulo B2B_AUTENTICACION: B2B-RULE-CONTEXT-001 estaba enlazada a todas las pantallas AUTH 51–55; B2B-AUTH-006 se incorpora al mismo alcance sin duplicar ni modificar la regla.'
from lf_ops.reglas r
where r.codigo='B2B-RULE-CONTEXT-001' and r.es_transversal=true
  and not exists(select 1 from lf_ops.reglas_pantallas rp where rp.regla_id=r.id and rp.pantalla_id=56);