-- PropertyOS — 0009_entitlements.sql
-- Cross-app entitlement support: match by email, dual-source Pro.

-- 1) Store email on profiles so entitlements can be matched by email.
alter table profiles add column if not exists email text;
create index if not exists profiles_email_idx on profiles (email);

-- Backfill existing emails from auth.users (SQL editor runs as postgres).
update profiles p set email = u.email
from auth.users u where u.id = p.id and p.email is null;

-- Capture email on new signups.
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, new.raw_user_meta_data->>'full_name', new.email);
  return new;
end $$;

-- 2) Dual-source Pro: direct (own Stripe) OR executive (Acquisition Engine perk).
alter table organizations
  add column if not exists pro_direct boolean not null default false,
  add column if not exists pro_executive boolean not null default false;

-- Existing 'pro' orgs were directly paid.
update organizations set pro_direct = true where plan = 'pro' and pro_direct = false;

-- Derive plan from the two sources on every write.
create or replace function derive_org_plan()
returns trigger language plpgsql as $$
begin
  new.plan := case when (new.pro_direct or new.pro_executive) then 'pro' else 'free' end;
  return new;
end $$;

drop trigger if exists trg_org_plan on organizations;
create trigger trg_org_plan before insert or update on organizations
  for each row execute function derive_org_plan();
