-- PropertyOS — 0004_leases.sql
-- create_lease: atomically create a lease, link a tenant via the
-- lease_tenants join table, and flip the unit to 'occupied'.
-- SECURITY INVOKER (default): RLS still applies, so a user can only
-- ever do this within their own org. The whole function is one
-- transaction, so all three writes succeed together or not at all.

create or replace function create_lease(
  p_unit_id uuid,
  p_tenant_id uuid,
  p_rent numeric,
  p_deposit numeric,
  p_start date,
  p_end date
)
returns uuid
language plpgsql
as $$
declare
  v_org uuid;
  v_tenant_org uuid;
  v_lease_id uuid;
begin
  -- RLS makes these selects return NULL if the rows aren't in the
  -- caller's org, which doubles as an ownership check.
  select organization_id into v_org
  from units where id = p_unit_id and deleted_at is null;
  if v_org is null then
    raise exception 'Unit not found or not accessible';
  end if;

  select organization_id into v_tenant_org
  from tenants where id = p_tenant_id and deleted_at is null;
  if v_tenant_org is null or v_tenant_org <> v_org then
    raise exception 'Tenant not found in the same organization';
  end if;

  insert into leases (organization_id, unit_id, start_date, end_date, rent_amount, deposit_amount, status)
  values (v_org, p_unit_id, p_start, p_end, p_rent, p_deposit, 'active')
  returning id into v_lease_id;

  insert into lease_tenants (lease_id, tenant_id, is_primary)
  values (v_lease_id, p_tenant_id, true);

  update units set status = 'occupied' where id = p_unit_id;

  return v_lease_id;
end $$;

grant execute on function create_lease(uuid, uuid, numeric, numeric, date, date) to authenticated;
