-- Temporary CI probe only. Never merge or apply. Both functions are new in exact-head diff.
CREATE FUNCTION lf_ops.zz_a4_positive_probe() RETURNS bigint LANGUAGE sql AS $f$
 SELECT count(*) FROM lf_ops.v_reglas_compat_v1
$f$;
CREATE FUNCTION lf_ops.zz_a4_negative_probe() RETURNS bigint LANGUAGE sql AS $f$
 SELECT count(*) FROM lf_ops.reglas
$f$;
