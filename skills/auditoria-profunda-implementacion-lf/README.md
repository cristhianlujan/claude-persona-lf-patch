# Auditoría profunda de implementación LF — candidato

El entrypoint es [SKILL.md](SKILL.md). El paquete incluye contrato, schemas,
reglas, taxonomía, EKB, fixtures, jueces, suite y piloto real sin efectos.
Registro de catálogo, instalación y activación no se aplican en este PR.

Los reportes nuevos usan el [contrato V2](contracts/reporting_and_contract_depth_v2.md).
El [piloto ampliado](reports/perfil_ig_perfil_v2.md) muestra once pasos, todos los
saltos, SQL medido, muestreo y revisión de contenido por contrato.
La [matriz HTML](reports/perfil_ig_perfil_v2.html) permite abrir cada celda y filtrar
por nota. Verde/amarillo/rojo/gris incluyen texto, fuente y corrección propuesta.
Los formatos se ajustan a cada uno de los diez tipos, sin puntuar cantidad de palabras.
La lectura de una corrida existente no es E2E nuevo: FLOW_NOT_ACCREDITED.
Los V1 preservados documentan el baseline; no se certifican retroactivamente.

La [prueba de uso con contexto nuevo](reports/forward_v2/report.md) descubre
omisiones no señaladas en el fixture, conserva un texto breve preciso como
aceptable y califica como débil el handoff largo ambiguo. Sus 32 controles son
locales y no representan un E2E LF. La [suite V2](reports/test_results_v2.json)
incluye esa reproducción como regresión; CI ejecuta todos los test_*.py del paquete.
