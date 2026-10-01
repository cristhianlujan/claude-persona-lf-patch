-- Historical operational SQL used for snapshot #11.
-- This is evidence, not a migration. Do not replay blindly.
-- Observed main: 1f18636503cdaeda79a8df6cced0d0f2e5353c14

begin;

do $$
begin
  if (select count(*) from inventory.objects where object_ref like 'repo://%') <> 2328 then
    raise exception 'BLOCK_REPO_INVENTORY_CARDINALITY_CHANGED';
  end if;
  if (select count(*) from inventory.objects where object_ref like 'edge://%') <> 37 then
    raise exception 'BLOCK_EDGE_INVENTORY_CARDINALITY_CHANGED';
  end if;
end
$$;

with obs as (select clock_timestamp() as ts)
update inventory.objects o
set currentness='CURRENT',
    currentness_source='GITHUB_MAIN',
    observed_at=obs.ts,
    observed_main_sha='1f18636503cdaeda79a8df6cced0d0f2e5353c14',
    active=true,
    updated_at=now()
from obs
where o.object_ref like 'repo://%';

update inventory.objects set currentness='STALE',updated_at=now()
where object_id = any(array[3393,3397,3398,3399,3901,3900,3982,3983,3994,4000,3995,4004,4015,3879,3881,4024,4381,4382,4383,4385,4387,4393,4397,4407,4408,4410,4412,4416,4569,4570,4571,4572,4587,4592,4595,4598,4601,4602,4620,4892,4893,4916,4927,4935,4948,5110,5149,5173,5183,5189,5191,5190]::bigint[]);

update inventory.objects set currentness='MISSING',active=false,updated_at=now()
where object_id = any(array[3395,3396,3400,3898,3825,3862,3865,3869,3878,4796,5186,5187,5188]::bigint[]);

with obs as (select max(observed_at) ts from inventory.objects where object_ref like 'repo://%')
update inventory.objects o
set currentness='CURRENT',
    currentness_source='SUPABASE_EDGE_RUNTIME',
    observed_at=obs.ts,
    observed_main_sha='1f18636503cdaeda79a8df6cced0d0f2e5353c14',
    source_traceability_state='SOURCE_PRESENT',
    active=true,
    updated_at=now()
from obs
where o.object_ref like 'edge://%';

update inventory.objects set currentness='STALE',updated_at=now() where object_id=5751;

update inventory.objects set source_traceability_state='RUNTIME_WITHOUT_SOURCE',updated_at=now()
where object_id = any(array[5742,5743,5759,5753,5754,5751,5757,5766,5763,5762,5765,5756,5755,5760,5769,5776,5767,5768,5750,5778,5774]::bigint[]);

select inventory.fn_refresh_search_index_v1();

-- Snapshot #11 was inserted with these exact input hashes and counts.
commit;
