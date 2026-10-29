-- Disposable cluster only: committed roles for the non-superuser session-boundary test.
CREATE ROLE programacion_auditor NOLOGIN; CREATE ROLE service_role NOLOGIN;
CREATE ROLE authenticator LOGIN NOINHERIT; GRANT service_role TO authenticator;
CREATE ROLE lf_t_auditor_login LOGIN NOINHERIT; GRANT programacion_auditor TO lf_t_auditor_login WITH INHERIT FALSE, SET TRUE;
