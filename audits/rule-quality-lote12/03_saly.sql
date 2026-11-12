-- SALY01 SQL_SHA256 5edfa5f4b9b0fe0d7cf3f4b09a1da3e6db1d05483548f257fa44366a40f08893
SELECT now() AS corte_utc,count(*) AS total,count(*) FILTER(WHERE vigente) AS vigente_true,count(*) FILTER(WHERE NOT vigente) AS vigente_false,count(DISTINCT categoria) AS categorias_exactas,count(DISTINCT upper(btrim(categoria))) AS categorias_casefold,count(*) FILTER(WHERE valor_config IS NULL OR valor_config='{}'::jsonb) AS config_vacia,count(*) FILTER(WHERE nullif(btrim(razon),'') IS NULL) AS razon_vacia,count(*) FILTER(WHERE nullif(btrim(fuente),'') IS NULL) AS fuente_vacia,count(*) FILTER(WHERE decision_id IS NULL) AS decision_id_nulo,count(*) FILTER(WHERE metadata IS NULL OR metadata='{}'::jsonb) AS metadata_vacia,count(*) FILTER(WHERE updated_at<now()-interval '30 days') AS sin_editar_30d,count(*) FILTER(WHERE updated_at<now()-interval '90 days') AS sin_editar_90d FROM saly.reglas;

-- SALY02 SQL_SHA256 0bf30f1025a79adebc67953c418a068a642af6b815231b3d8ffc44aba2f47613
SELECT categoria,count(*) AS reglas,count(*) FILTER(WHERE vigente) AS vigentes FROM saly.reglas GROUP BY categoria ORDER BY categoria;

-- SALY03 SQL_SHA256 a04bc286f2cabd861b774820c26b70fa06b56f91906aa47b0317cba98ccce080
SELECT estado,vigente,count(*) AS reglas FROM saly.reglas GROUP BY estado,vigente ORDER BY estado,vigente;

-- SALY04 SQL_SHA256 a68d6ac12109b038bc3d85455d06d4a0748bad2194dc4637e2dcb0cc6cc0a986
WITH flags AS (SELECT codigo,categoria,regla,valor_config,(coalesce(regla,'') ~* '(debe|deber[aá]|obligator|prohib|no puede|no se|solo|solamente|únicamente|unicamente|requiere|requerid|permitid|deneg|bloque|valid|mínim|minim|máxim|maxim|si |cuando|antes de|despu[eé]s|hasta|al menos|cada |expir|l[ií]mit|[0-9]+)') AS control_texto,exists(SELECT 1 FROM jsonb_object_keys(coalesce(valor_config,'{}'::jsonb)) k(key) WHERE k.key !~* '^(source_|owner_|decision|version|reconciled|implementation_status|screen_id$|pantalla_id$|relation_key$|reference|evidence|registry)') AS config_operativa FROM saly.reglas) SELECT codigo,categoria,regla,valor_config FROM flags WHERE NOT control_texto AND NOT config_operativa ORDER BY codigo;

-- SALY05 SQL_SHA256 4e4d0a6f23b82b949bbccbe57e7bb5161dfc890f9f99bdb38a139a331bd16c68
WITH p AS (SELECT r.codigo,r.categoria,k.key,k.value FROM saly.reglas r CROSS JOIN LATERAL jsonb_each(coalesce(r.valor_config,'{}'::jsonb)) k WHERE jsonb_typeof(k.value) IN ('number','boolean','string') AND k.key ~* '(max|min|limite|limit|timeout|expir|sesion|session|reenv|intento|ventana|cooldown|retry|threshold|ttl|duracion|ratio|pct|percent|monto|amount)' AND k.key !~* '(_id$|^source_|decision|version|policy_id|rule_id|message_id|screen_id|error_id)') SELECT a.codigo AS regla_a,b.codigo AS regla_b,a.categoria,a.key AS parametro,a.value AS valor_a,b.value AS valor_b FROM p a JOIN p b ON a.codigo<b.codigo AND a.categoria=b.categoria AND a.key=b.key AND a.value<>b.value ORDER BY regla_a,regla_b;

-- SALY06 SQL_SHA256 4f3b40c5887aad44dbca14f0f40ec8cbb9cd660997a09394c39624bae852ad88
WITH k AS (SELECT r.codigo,r.categoria,r.regla,k.key AS parametro,k.value AS valor_config,regexp_match(lower(r.regla),replace(lower(k.key),'_','[_[:space:]]+') || '[[:space:]]*(?:=|:|de|es)[[:space:]]*([0-9]+([.,][0-9]+)?)') AS texto_match FROM saly.reglas r CROSS JOIN LATERAL jsonb_each(coalesce(r.valor_config,'{}'::jsonb)) k WHERE jsonb_typeof(k.value)='number' AND k.key !~* '(_id$|decision|version|source_)') SELECT codigo,categoria,parametro,valor_config,texto_match[1] AS valor_descripcion FROM k WHERE texto_match IS NOT NULL AND replace(texto_match[1],',','.')::numeric <> (valor_config #>> '{}')::numeric ORDER BY codigo,parametro;

-- SALY07 SQL_SHA256 b9af3e8aec30a25d6a8383c8dd622158e58fcda19d2daf25aa7b40625abff35c
SELECT count(*) AS total,count(*) FILTER(WHERE metadata::text ~* '"depends_on_rules"[[:space:]]*:') AS metadata_depends_on_rules,count(*) FILTER(WHERE valor_config::text ~* '"depends_on_rules"[[:space:]]*:') AS config_depends_on_rules FROM saly.reglas;

-- SALY08 SQL_SHA256 f5bffa65597d0439223c265ab9f8e579611e915e21362dc7c4c2a8e75367285e
SELECT coalesce(metadata->>'version','<SIN_VERSION>') AS version,count(*) AS reglas FROM saly.reglas GROUP BY 1 ORDER BY 1;

-- SALY09 SQL_SHA256 80d5da13ac4fec011b5dbb3a4a8368813e3063babc845e50ac44ecd2d856c681
SELECT titulo,count(*) AS cantidad,array_agg(codigo ORDER BY codigo) AS codigos FROM saly.reglas GROUP BY titulo HAVING count(*)>1 ORDER BY titulo;

-- SALY10 SQL_SHA256 f79e20bc0813f94e9357a486721aa2786431cde04304adfad3f8de8326d2eedf
SELECT regla,count(*) AS cantidad,array_agg(codigo ORDER BY codigo) AS codigos FROM saly.reglas GROUP BY regla HAVING count(*)>1 ORDER BY regla;

-- SCHEMA01 SQL_SHA256 68211062c06ba680b5ba36c8e5dd7e566171de3d16f514a68614644eb3afc580
SELECT table_schema,table_name,column_name,data_type FROM information_schema.columns WHERE table_schema IN('lf_ops','saly') AND table_name='reglas' ORDER BY table_schema,ordinal_position;
