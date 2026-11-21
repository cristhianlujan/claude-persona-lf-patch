-- Decisión 2026-11-21 14:54 Lima. Solo nueva puerta y registro; paridad estructural LF/SALY sin tocar datos SALY.
BEGIN;
CREATE TABLE lf_ops.nucleo_deprecaciones (
 regla text NOT NULL,
 version integer NOT NULL,
 hash_version text NOT NULL CHECK (hash_version ~ '^[0-9a-f]{64}$'),
 autoridad text NOT NULL REFERENCES lf_ops.nucleo_autoridades(codigo),
 motivo text NOT NULL CHECK (length(btrim(motivo)) >= 10),
 publicada_desde timestamptz NOT NULL,
 vigente_hasta timestamptz NOT NULL CHECK (vigente_hasta >= publicada_desde),
 PRIMARY KEY(regla,version),
 FOREIGN KEY(regla,version) REFERENCES lf_ops.nucleo_regla_versiones(regla,version)
);
REVOKE ALL ON lf_ops.nucleo_deprecaciones FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON lf_ops.nucleo_deprecaciones TO supabase_read_only_user;
CREATE FUNCTION lf_ops.nucleo_regla_deprecar_v1(
 p_regla text,p_version integer,p_hash_version text,p_autoridad text,p_motivo text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO pg_catalog,lf_ops
AS $deprecar$
DECLARE
 v_estado text;
 v_version record;
 v_fecha timestamptz:=now();
 v_marca text:=coalesce(current_setting('lf.nucleo_publicando',true),'');
 v_n integer;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('nucleo_promover:' || p_regla,0));
 SELECT estado INTO v_estado FROM nucleo_reglas WHERE codigo=p_regla FOR UPDATE;
 IF v_estado IS DISTINCT FROM 'VIGENTE' THEN
   RAISE EXCEPTION 'NUCLEO_DEPRECAR_NO_VIGENTE: %',p_regla;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM nucleo_autoridades WHERE codigo=p_autoridad AND estado='VIGENTE') THEN
   RAISE EXCEPTION 'NUCLEO_DEPRECAR_AUTORIDAD_NO_VIGENTE: %',p_autoridad;
 END IF;
 IF length(btrim(coalesce(p_motivo,'')))<10 THEN
   RAISE EXCEPTION 'NUCLEO_DEPRECAR_SIN_MOTIVO';
 END IF;
 IF EXISTS(SELECT 1 FROM nucleo_regla_versiones WHERE regla=p_regla AND estado='CANDIDATA') THEN
   RAISE EXCEPTION 'NUCLEO_DEPRECAR_CANDIDATA_PENDIENTE: %',p_regla;
 END IF;
 IF EXISTS(SELECT 1 FROM nucleo_relaciones d JOIN nucleo_reglas r ON r.codigo=d.origen
   WHERE d.destino=p_regla AND d.tipo='DEPENDE' AND r.estado='VIGENTE') THEN
   RAISE EXCEPTION 'NUCLEO_DEPRECAR_DEPENDIENTE_VIGENTE: %',p_regla;
 END IF;
 SELECT * INTO v_version FROM nucleo_regla_versiones
 WHERE regla=p_regla AND estado='PUBLICADA' AND vigente_hasta IS NULL FOR UPDATE;
 IF NOT FOUND OR v_version.version IS DISTINCT FROM p_version
   OR v_version.hash IS DISTINCT FROM p_hash_version
   OR v_version.publicada_desde IS NULL OR v_version.publicada_desde>v_fecha
   OR (SELECT count(*) FROM nucleo_regla_versiones WHERE regla=p_regla AND estado='PUBLICADA' AND vigente_hasta IS NULL)<>1 THEN
   RAISE EXCEPTION 'NUCLEO_DEPRECAR_VERSION_OBSOLETA: % v%',p_regla,p_version;
 END IF;
 PERFORM set_config('lf.nucleo_publicando',p_regla||':'||p_version,true);
 UPDATE nucleo_regla_versiones SET vigente_hasta=v_fecha
 WHERE regla=p_regla AND version=p_version AND estado='PUBLICADA' AND vigente_hasta IS NULL;
 GET DIAGNOSTICS v_n=ROW_COUNT;
 PERFORM set_config('lf.nucleo_publicando',v_marca,true);
 IF v_n<>1 THEN RAISE EXCEPTION 'NUCLEO_DEPRECAR_CIERRE_INEXACTO'; END IF;
 UPDATE nucleo_reglas SET estado='DEPRECADA' WHERE codigo=p_regla AND estado='VIGENTE';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'NUCLEO_DEPRECAR_ESTADO_INEXACTO'; END IF;
 INSERT INTO nucleo_deprecaciones(regla,version,hash_version,autoridad,motivo,publicada_desde,vigente_hasta)
 VALUES(p_regla,p_version,v_version.hash,p_autoridad,btrim(p_motivo),v_version.publicada_desde,v_fecha);
 RETURN jsonb_build_object('regla',p_regla,'version',p_version,'estado','DEPRECADA',
 'hash_version',v_version.hash,'autoridad',p_autoridad,'motivo',btrim(p_motivo),'vigente_hasta',v_fecha);
END $deprecar$;
-- Solo el Train/propietario escribe, igual que el resto del núcleo. Sin grants nuevos de escritura.
REVOKE ALL ON FUNCTION lf_ops.nucleo_regla_deprecar_v1(text,integer,text,text,text) FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
INSERT INTO lf_ops.nucleo_contratos(puerta,version,funcion,descripcion,entrada,salida,estado)
VALUES('DEPRECACION',1,'nucleo_regla_deprecar_v1','Cierra una versión publicada y pasa exclusivamente de VIGENTE a DEPRECADA, con historial; no retira.',
 '{"regla":"text","version":"integer","hash_version":"sha256","autoridad":"vigente","motivo":"text >=10"}',
 '{"estado":"DEPRECADA","regla":"text","version":"integer","hash_version":"sha256","autoridad":"text","motivo":"text","vigente_hasta":"timestamptz"}','VIGENTE');

CREATE TABLE saly.nucleo_deprecaciones (
 regla text NOT NULL,
 version integer NOT NULL,
 hash_version text NOT NULL CHECK (hash_version ~ '^[0-9a-f]{64}$'),
 autoridad text NOT NULL REFERENCES saly.nucleo_autoridades(codigo),
 motivo text NOT NULL CHECK (length(btrim(motivo)) >= 10),
 publicada_desde timestamptz NOT NULL,
 vigente_hasta timestamptz NOT NULL CHECK (vigente_hasta >= publicada_desde),
 PRIMARY KEY(regla,version),
 FOREIGN KEY(regla,version) REFERENCES saly.nucleo_regla_versiones(regla,version)
);
REVOKE ALL ON saly.nucleo_deprecaciones FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON saly.nucleo_deprecaciones TO supabase_read_only_user;
CREATE FUNCTION saly.nucleo_regla_deprecar_v1(
 p_regla text,p_version integer,p_hash_version text,p_autoridad text,p_motivo text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO pg_catalog,saly
AS $deprecar$
DECLARE
 v_estado text;
 v_version record;
 v_fecha timestamptz:=now();
 v_marca text:=coalesce(current_setting('lf.nucleo_publicando',true),'');
 v_n integer;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('nucleo_promover:' || p_regla,0));
 SELECT estado INTO v_estado FROM nucleo_reglas WHERE codigo=p_regla FOR UPDATE;
 IF v_estado IS DISTINCT FROM 'VIGENTE' THEN
   RAISE EXCEPTION 'NUCLEO_DEPRECAR_NO_VIGENTE: %',p_regla;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM nucleo_autoridades WHERE codigo=p_autoridad AND estado='VIGENTE') THEN
   RAISE EXCEPTION 'NUCLEO_DEPRECAR_AUTORIDAD_NO_VIGENTE: %',p_autoridad;
 END IF;
 IF length(btrim(coalesce(p_motivo,'')))<10 THEN
   RAISE EXCEPTION 'NUCLEO_DEPRECAR_SIN_MOTIVO';
 END IF;
 IF EXISTS(SELECT 1 FROM nucleo_regla_versiones WHERE regla=p_regla AND estado='CANDIDATA') THEN
   RAISE EXCEPTION 'NUCLEO_DEPRECAR_CANDIDATA_PENDIENTE: %',p_regla;
 END IF;
 IF EXISTS(SELECT 1 FROM nucleo_relaciones d JOIN nucleo_reglas r ON r.codigo=d.origen
   WHERE d.destino=p_regla AND d.tipo='DEPENDE' AND r.estado='VIGENTE') THEN
   RAISE EXCEPTION 'NUCLEO_DEPRECAR_DEPENDIENTE_VIGENTE: %',p_regla;
 END IF;
 SELECT * INTO v_version FROM nucleo_regla_versiones
 WHERE regla=p_regla AND estado='PUBLICADA' AND vigente_hasta IS NULL FOR UPDATE;
 IF NOT FOUND OR v_version.version IS DISTINCT FROM p_version
   OR v_version.hash IS DISTINCT FROM p_hash_version
   OR v_version.publicada_desde IS NULL OR v_version.publicada_desde>v_fecha
   OR (SELECT count(*) FROM nucleo_regla_versiones WHERE regla=p_regla AND estado='PUBLICADA' AND vigente_hasta IS NULL)<>1 THEN
   RAISE EXCEPTION 'NUCLEO_DEPRECAR_VERSION_OBSOLETA: % v%',p_regla,p_version;
 END IF;
 PERFORM set_config('lf.nucleo_publicando',p_regla||':'||p_version,true);
 UPDATE nucleo_regla_versiones SET vigente_hasta=v_fecha
 WHERE regla=p_regla AND version=p_version AND estado='PUBLICADA' AND vigente_hasta IS NULL;
 GET DIAGNOSTICS v_n=ROW_COUNT;
 PERFORM set_config('lf.nucleo_publicando',v_marca,true);
 IF v_n<>1 THEN RAISE EXCEPTION 'NUCLEO_DEPRECAR_CIERRE_INEXACTO'; END IF;
 UPDATE nucleo_reglas SET estado='DEPRECADA' WHERE codigo=p_regla AND estado='VIGENTE';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'NUCLEO_DEPRECAR_ESTADO_INEXACTO'; END IF;
 INSERT INTO nucleo_deprecaciones(regla,version,hash_version,autoridad,motivo,publicada_desde,vigente_hasta)
 VALUES(p_regla,p_version,v_version.hash,p_autoridad,btrim(p_motivo),v_version.publicada_desde,v_fecha);
 RETURN jsonb_build_object('regla',p_regla,'version',p_version,'estado','DEPRECADA',
 'hash_version',v_version.hash,'autoridad',p_autoridad,'motivo',btrim(p_motivo),'vigente_hasta',v_fecha);
END $deprecar$;
-- Solo el Train/propietario escribe, igual que el resto del núcleo. Sin grants nuevos de escritura.
REVOKE ALL ON FUNCTION saly.nucleo_regla_deprecar_v1(text,integer,text,text,text) FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
INSERT INTO saly.nucleo_contratos(puerta,version,funcion,descripcion,entrada,salida,estado)
VALUES('DEPRECACION',1,'nucleo_regla_deprecar_v1','Cierra una versión publicada y pasa exclusivamente de VIGENTE a DEPRECADA, con historial; no retira.',
 '{"regla":"text","version":"integer","hash_version":"sha256","autoridad":"vigente","motivo":"text >=10"}',
 '{"estado":"DEPRECADA","regla":"text","version":"integer","hash_version":"sha256","autoridad":"text","motivo":"text","vigente_hasta":"timestamptz"}','VIGENTE');

INSERT INTO lf_ops.nucleo_errores(codigo,puerta,significado,accion) VALUES
('NUCLEO_DEPRECAR_AUTORIDAD_NO_VIGENTE','DEPRECACION','La autoridad indicada no está vigente','Verificar la autoridad correspondiente; no sustituirla.'),
('NUCLEO_DEPRECAR_CANDIDATA_PENDIENTE','DEPRECACION','La regla tiene una candidata pendiente','Resolver la candidata por la ruta autorizada antes de deprecar.'),
('NUCLEO_DEPRECAR_CIERRE_INEXACTO','DEPRECACION','No se cerró exactamente una versión','Abortar y verificar estado, versión y vigencia.'),
('NUCLEO_DEPRECAR_DEPENDIENTE_VIGENTE','DEPRECACION','Una regla vigente depende de esta regla','Evaluar dependencia y obtener autorización para resolverla.'),
('NUCLEO_DEPRECAR_ESTADO_INEXACTO','DEPRECACION','No se cambió exactamente una identidad vigente','Abortar y comprobar estado y concurrencia.'),
('NUCLEO_DEPRECAR_NO_VIGENTE','DEPRECACION','La identidad no está vigente','No deprecar candidatas, borradores, deprecadas o retiradas.'),
('NUCLEO_DEPRECAR_SIN_MOTIVO','DEPRECACION','El motivo no cumple la longitud mínima','Registrar un motivo concreto de la decisión autorizada.'),
('NUCLEO_DEPRECAR_VERSION_OBSOLETA','DEPRECACION','La versión/hash no coincide con la publicación abierta','Releer la publicación vigente y validar el hash antes de solicitar deprecación.');

INSERT INTO saly.nucleo_errores(codigo,puerta,significado,accion) VALUES
('NUCLEO_DEPRECAR_AUTORIDAD_NO_VIGENTE','DEPRECACION','La autoridad indicada no está vigente','Verificar la autoridad correspondiente; no sustituirla.'),
('NUCLEO_DEPRECAR_CANDIDATA_PENDIENTE','DEPRECACION','La regla tiene una candidata pendiente','Resolver la candidata por la ruta autorizada antes de deprecar.'),
('NUCLEO_DEPRECAR_CIERRE_INEXACTO','DEPRECACION','No se cerró exactamente una versión','Abortar y verificar estado, versión y vigencia.'),
('NUCLEO_DEPRECAR_DEPENDIENTE_VIGENTE','DEPRECACION','Una regla vigente depende de esta regla','Evaluar dependencia y obtener autorización para resolverla.'),
('NUCLEO_DEPRECAR_ESTADO_INEXACTO','DEPRECACION','No se cambió exactamente una identidad vigente','Abortar y comprobar estado y concurrencia.'),
('NUCLEO_DEPRECAR_NO_VIGENTE','DEPRECACION','La identidad no está vigente','No deprecar candidatas, borradores, deprecadas o retiradas.'),
('NUCLEO_DEPRECAR_SIN_MOTIVO','DEPRECACION','El motivo no cumple la longitud mínima','Registrar un motivo concreto de la decisión autorizada.'),
('NUCLEO_DEPRECAR_VERSION_OBSOLETA','DEPRECACION','La versión/hash no coincide con la publicación abierta','Releer la publicación vigente y validar el hash antes de solicitar deprecación.');

COMMIT;
