create table if not exists public.lf_error_knowledge (
 id uuid primary key default gen_random_uuid(),
 codigo text unique,
 categoria text not null,
 titulo text not null,
 descripcion text,
 causa_raiz text,
 patron text,
 prevencion text,
 validacion text,
 severidad text,
 frecuencia integer not null default 1,
 primera_vez timestamptz not null default now(),
 ultima_vez timestamptz not null default now(),
 lote_origen text,
 pr text,
 estado text not null default 'activo',
 evidencia text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.lf_prevention_rules (
 id uuid primary key default gen_random_uuid(),
 regla_codigo text unique,
 error_codigo text,
 regla text not null,
 justificacion text,
 prioridad integer default 100,
 activa boolean default true,
 created_at timestamptz default now()
);

create table if not exists public.lf_best_practices (
 id uuid primary key default gen_random_uuid(),
 categoria text,
 titulo text,
 practica text,
 evidencia text,
 created_at timestamptz default now()
);

create table if not exists public.lf_decision_log (
 id uuid primary key default gen_random_uuid(),
 adr text unique,
 titulo text,
 decision text,
 razon text,
 impacto text,
 estado text default 'vigente',
 created_at timestamptz default now()
);
