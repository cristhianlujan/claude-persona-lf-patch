-- Human Review Convergence v3: fail closed for SECURITY DEFINER materializer.
REVOKE ALL ON FUNCTION public.fn_lf_p0_materialize_convergent_review_v1(uuid,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_lf_p0_materialize_convergent_review_v1(uuid,uuid,text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_lf_p0_materialize_convergent_review_v1(uuid,uuid,text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_lf_p0_materialize_convergent_review_v1(uuid,uuid,text) TO service_role;