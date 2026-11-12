-- LF01 SQL_SHA256 2b59f7f36438ab5b074cbeef9da5618618def09ea75e7c63f084968cff33e380
SELECT now() AS corte_utc,count(*) AS total,count(*) FILTER(WHERE estado='VIGENTE') AS vigentes,count(*) FILTER(WHERE estado='CANDIDATO') AS candidatos,count(DISTINCT categoria) AS categorias_exactas,count(DISTINCT upper(btrim(categoria))) AS categorias_casefold,count(*) FILTER(WHERE valor_config IS NULL OR valor_config='{}'::jsonb) AS config_vacia,count(*) FILTER(WHERE nullif(btrim(razon),'') IS NULL) AS razon_vacia,count(*) FILTER(WHERE nullif(btrim(origen),'') IS NULL) AS origen_vacio,count(*) FILTER(WHERE created_by IS NULL) AS created_by_nulo,count(*) FILTER(WHERE estado='VIGENTE' AND pendiente_decision IS TRUE) AS vigentes_pendientes,count(*) FILTER(WHERE estado='CANDIDATO' AND updated_at<now()-interval '30 days') AS candidatos_sin_editar_30d,count(*) FILTER(WHERE estado='VIGENTE' AND updated_at<now()-interval '90 days') AS vigentes_sin_editar_90d FROM lf_ops.reglas;

-- LF02 SQL_SHA256 38c9f089a45f3fb0f97c494290b45f5df1613a023b641d94df211e06027e3dec
SELECT categoria,count(*) AS reglas,count(*) FILTER(WHERE estado='VIGENTE') AS vigentes FROM lf_ops.reglas GROUP BY categoria ORDER BY lower(categoria),categoria;

-- LF03 SQL_SHA256 c1b2cb771430baf3c9624ec0d9e41d4d7d814cda7bfe48e3fa4a8692284b7cc4
SELECT categoria,count(*) AS reglas FROM lf_ops.reglas GROUP BY categoria HAVING count(*)=1 ORDER BY categoria;

-- LF04 SQL_SHA256 6f6d4b0c4501e815e52502c88eaf0185396bdd62ca69c218ed831327d3dd9ca1
SELECT upper(btrim(categoria)) AS normalizada,array_agg(DISTINCT categoria ORDER BY categoria) AS variantes,sum(n) AS total FROM (SELECT categoria,count(*) AS n FROM lf_ops.reglas GROUP BY categoria)t GROUP BY upper(btrim(categoria)) HAVING count(*)>1 ORDER BY normalizada;

-- LF05 SQL_SHA256 ef555391a78763c3ab159ad7253db3f311856fee08cb02959f723e9c0c1ec762
WITH pares(es,en) AS (VALUES ('accesibilidad','ACCESSIBILITY'),('seguridad','SECURITY'),('sesion','SESSION'),('observabilidad','OBSERVABILITY')) SELECT p.es,p.en,count(*) FILTER(WHERE r.categoria=p.es) AS reglas_es,count(*) FILTER(WHERE r.categoria=p.en) AS reglas_en FROM pares p LEFT JOIN lf_ops.reglas r ON r.categoria IN(p.es,p.en) GROUP BY p.es,p.en ORDER BY p.es;

-- LF06 SQL_SHA256 ee0c0c3c10218e335f4d958f0bc66358a7d46db4752cb136a20075be2fa0fcc1
SELECT categoria,count(*) AS reglas FROM lf_ops.reglas WHERE categoria IN('ataques','SECURITY','seguridad','autenticacion','AUTHORIZATION','rate_limiting','sesion','SESSION','PRIVACY','unicidad') GROUP BY categoria ORDER BY reglas DESC,categoria;

-- LF07 SQL_SHA256 efcd3fc9ae1d59c094156b4b56f6b93f02c43bd1081b811a00b8bd0ed6bde4bb
SELECT titulo,count(*) AS cantidad,array_agg(codigo ORDER BY codigo) AS codigos FROM lf_ops.reglas GROUP BY titulo HAVING count(*)>1 ORDER BY titulo;

-- LF08 SQL_SHA256 bbf8e02ee917efc4e3f26a0392b34cf6c7260418652e00edb20daf1aa025de1a
SELECT descripcion,count(*) AS cantidad,array_agg(codigo ORDER BY codigo) AS codigos FROM lf_ops.reglas GROUP BY descripcion HAVING count(*)>1 ORDER BY descripcion;
