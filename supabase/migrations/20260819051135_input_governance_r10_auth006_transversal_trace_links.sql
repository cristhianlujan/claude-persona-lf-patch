with fully_transversal as (
  select r.id,r.codigo
  from lf_ops.reglas r
  join lf_ops.reglas_pantallas rp on rp.regla_id=r.id
  where r.es_transversal=true and r.codigo like 'B2B-RULE-%'
  group by r.id,r.codigo
  having array_agg(distinct rp.pantalla_id order by rp.pantalla_id)=array[43,44,45,46,47,48,49,50,51,52,53,54,55]::integer[]
)
insert into lf_ops.reglas_pantallas(regla_id,pantalla_id,nota)
select f.id,56,'Trazabilidad estructural de nueva pantalla: la regla transversal estaba enlazada sin excepción a todas las pantallas B2B 43–55 antes de crear B2B-AUTH-006; se extiende el mismo alcance a 56 sin duplicar ni modificar la regla.'
from fully_transversal f
where not exists(select 1 from lf_ops.reglas_pantallas rp where rp.regla_id=f.id and rp.pantalla_id=56);