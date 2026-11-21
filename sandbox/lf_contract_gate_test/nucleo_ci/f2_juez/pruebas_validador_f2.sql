-- SQL auxiliar ejecutado en PG17.6 READ ONLY. No es función productiva.
BEGIN READ ONLY;
WITH casos(id,grupo,a,b,residual,dictamen,espera) AS (VALUES
('C01','publico','[2,0,5]'::jsonb,'[2,0,5]'::jsonb,false,'EQUIVALENTE',true),
('C02','publico','[false,true,false,false]','[false,true,false,false]',false,'EQUIVALENTE',true),
('C03','publico','[false,true,false,false]','[false,true,true,false]',false,'EQUIVALENTE',false),
('C04','publico','[false,true,false,false]','[true,false,true,true]',false,'EQUIVALENTE',false),
('C05','publico','["BLOQUEAR","NO_APLICA"]','["PERMITIR","NO_APLICA"]',false,'EQUIVALENTE',false),
('C06','publico','[false,true,false,false]','[false,true,false,false]',true,'EQUIVALENTE',false),
('C07','publico','[false,true,false,false]','[false,true,false,false]',true,'PARCIAL',true),
('C08','publico','[2,0,5]','[2,0,8]',false,'EQUIVALENTE',false),
('C09','holdout','[false,true,false,false]','[false,true,false,false]',false,'EQUIVALENTE',true),
('C10','holdout','[false,false,true,true]','[false,true,true,true]',false,'EQUIVALENTE',false),
('C11','holdout','[2,0,5]','[2,0,5]',true,'PARCIAL',true),
('C12','holdout','["BLOQUEAR","NO_APLICA"]','["PERMITIR","NO_APLICA"]',false,'CONFLICTO',true)),
instancias(i) AS (VALUES ('lf_ops'),('saly')),
base AS (SELECT i,c.*,encode(sha256(convert_to(jsonb_build_array(i,id,a,b,residual)::text,'UTF8')),'hex') h FROM casos c CROSS JOIN instancias),
rub AS (SELECT jsonb_object_agg(k,jsonb_build_object('puntaje',1,'observacion','FIXTURE SINTETICA')) p, array_agg(k) keys FROM unnest(ARRAY['CAL_ACCIONABLE','CAL_ALCANCE','CAL_CLARIDAD','COH_EFECTO','COH_TEXTO_CONDICION','SEM_NO_CONTRADICE','SEM_NO_DUPLICA']) k),
payload AS (SELECT base.*,rub.*,h recibido,'fixture-productor' productor,'fixture-revisor' revisor,false es_productor,1 llamadas,'fixture://local/no-real' evidencia,2 version_recibida FROM base CROSS JOIN rub),
neg AS (SELECT i, 'N'||k id,'integridad' grupo,a,b,residual,dictamen,false espera,h,
CASE WHEN k=1 THEN repeat('0',64) ELSE recibido END recibido,
productor,CASE WHEN k=2 THEN productor ELSE revisor END revisor,
k=3 es_productor,CASE WHEN k=4 THEN 0 ELSE llamadas END llamadas,
CASE WHEN k=5 THEN '' ELSE evidencia END evidencia,
CASE WHEN k=6 THEN 1 ELSE version_recibida END version_recibida,
CASE WHEN k=7 THEN p-'SEM_NO_DUPLICA' WHEN k=8 THEN jsonb_set(p,'{COH_EFECTO,puntaje}','2') WHEN k=9 THEN jsonb_set(jsonb_set(p,'{COH_EFECTO,puntaje}','0'),'{COH_EFECTO,observacion}','""') ELSE p END p,keys
FROM payload CROSS JOIN generate_series(1,9) k WHERE payload.id='C01'),
unido AS (SELECT i,id,grupo,a,b,residual,dictamen,espera,h,recibido,productor,revisor,es_productor,llamadas,evidencia,version_recibida,p,keys FROM payload UNION ALL SELECT * FROM neg),
validado AS (SELECT *,coalesce(recibido=h AND productor<>revisor AND NOT es_productor AND llamadas>=1 AND length(evidencia)>0 AND version_recibida=2 AND p ?& keys AND NOT EXISTS (SELECT FROM unnest(keys) k WHERE jsonb_typeof(p->k->'puntaje') IS DISTINCT FROM 'number' OR (p->k->>'puntaje')::numeric NOT BETWEEN 0 AND 1 OR ((p->k->>'puntaje')::numeric<1 AND length(btrim(coalesce(p->k->>'observacion','')))<10)) AND CASE dictamen WHEN 'EQUIVALENTE' THEN a=b AND NOT residual WHEN 'PARCIAL' THEN a=b AND residual WHEN 'CONFLICTO' THEN a<>b AND a @> '["BLOQUEAR"]' AND b @> '["PERMITIR"]' ELSE false END,false) acepta FROM unido)
SELECT current_setting('server_version') pg,current_setting('transaction_read_only') read_only,i,count(*) total,count(*) FILTER(WHERE acepta=espera) ok,count(*) FILTER(WHERE espera AND acepta) positivos_aceptados,count(*) FILTER(WHERE NOT espera AND NOT acepta) negativos_rechazados,count(*) FILTER(WHERE grupo='holdout' AND acepta=espera) holdout_ok,jsonb_agg(id ORDER BY id) FILTER(WHERE acepta<>espera) fallas FROM validado GROUP BY i ORDER BY i;
ROLLBACK;
