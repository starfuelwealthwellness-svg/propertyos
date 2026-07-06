-- PropertyOS — 0005_payments.sql
-- generate_current_rent: for every active lease that doesn't yet have a
-- payment row for the current month, create one (status 'due'). Idempotent
-- thanks to the NOT EXISTS guard + the unique(lease_id, period_start)
-- constraint. SECURITY INVOKER, so RLS scopes it to the caller's org.

create or replace function generate_current_rent()
returns integer
language plpgsql
as $$
declare
  v_period date := date_trunc('month', now())::date;
  v_count integer;
begin
  insert into payments (organization_id, lease_id, period_start, amount_due, status)
  select l.organization_id, l.id, v_period, l.rent_amount, 'due'
  from leases l
  where l.status = 'active'
    and l.deleted_at is null
    and not exists (
      select 1 from payments p
      where p.lease_id = l.id
        and p.period_start = v_period
        and p.deleted_at is null
    );
  get diagnostics v_count = row_count;
  return v_count;
end $$;

grant execute on function generate_current_rent() to authenticated;
