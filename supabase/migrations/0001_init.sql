create extension if not exists "pgcrypto";

create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- TENANCY & IDENTITY
create table organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  type text not null default 'landlord'
    check (type in ('landlord','community_group','coop','church','commercial','acquisition_team')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table profiles (
  id uuid primary key,
  full_name text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data->>'full_name');
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

create table memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  user_id uuid not null references profiles(id),
  role text not null
    check (role in ('owner','admin','property_manager','maintenance_coordinator','vendor','tenant','viewer')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (organization_id, user_id)
);
create index on memberships (user_id) where deleted_at is null;
create index on memberships (organization_id) where deleted_at is null;

-- Defined AFTER memberships exists (this was the fix)
create or replace function current_user_org_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select organization_id from memberships
  where user_id = auth.uid() and deleted_at is null;
$$;

-- PROPERTY DATA
create table properties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  name text not null,
  address_line1 text not null,
  address_line2 text,
  city text not null,
  state text not null,
  postal_code text not null,
  property_type text not null default 'multi_family'
    check (property_type in ('single_family','multi_family','commercial','mixed_use')),
  lat numeric(9,6),
  lng numeric(9,6),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index on properties (organization_id) where deleted_at is null;

create table units (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  property_id uuid not null references properties(id),
  unit_number text not null,
  bedrooms smallint,
  bathrooms numeric(3,1),
  square_feet integer,
  market_rent numeric(10,2),
  status text not null default 'vacant'
    check (status in ('vacant','occupied','maintenance','offline')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (property_id, unit_number)
);
create index on units (organization_id) where deleted_at is null;
create index on units (property_id) where deleted_at is null;

create table tenants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  full_name text not null,
  email text,
  phone text,
  portal_user_id uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index on tenants (organization_id) where deleted_at is null;

create table leases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  unit_id uuid not null references units(id),
  start_date date not null,
  end_date date,
  rent_amount numeric(10,2) not null,
  deposit_amount numeric(10,2),
  status text not null default 'active'
    check (status in ('draft','active','expired','terminated')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index on leases (organization_id) where deleted_at is null;
create index on leases (unit_id) where deleted_at is null;

create table lease_tenants (
  lease_id uuid not null references leases(id),
  tenant_id uuid not null references tenants(id),
  is_primary boolean not null default false,
  primary key (lease_id, tenant_id)
);

-- OPERATIONS
create table vendors (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  name text not null,
  trade text,
  email text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index on vendors (organization_id) where deleted_at is null;

create table maintenance_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  unit_id uuid not null references units(id),
  reported_by uuid references profiles(id),
  assigned_vendor uuid references vendors(id),
  title text not null,
  description text,
  priority text not null default 'normal'
    check (priority in ('low','normal','high','emergency')),
  status text not null default 'open'
    check (status in ('open','triaged','assigned','in_progress','resolved','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index on maintenance_requests (organization_id) where deleted_at is null;
create index on maintenance_requests (unit_id) where deleted_at is null;
create index on maintenance_requests (status) where deleted_at is null;

create table payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  lease_id uuid not null references leases(id),
  period_start date not null,
  amount_due numeric(10,2) not null,
  amount_paid numeric(10,2) not null default 0,
  status text not null default 'due'
    check (status in ('due','partial','paid','late','waived')),
  stripe_payment_intent text,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (lease_id, period_start)
);
create index on payments (organization_id) where deleted_at is null;
create index on payments (status) where deleted_at is null;

create table documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  owner_type text not null check (owner_type in ('property','unit','lease','tenant','maintenance')),
  owner_id uuid not null,
  storage_path text not null,
  file_name text not null,
  mime_type text,
  uploaded_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index on documents (organization_id, owner_type, owner_id) where deleted_at is null;

create table notifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  user_id uuid not null references profiles(id),
  kind text not null,
  payload jsonb not null default '{}',
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index on notifications (user_id) where read_at is null;

create table audit_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid,
  actor_id uuid references profiles(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  diff jsonb,
  ip_address inet,
  created_at timestamptz not null default now()
);
create index on audit_logs (organization_id, created_at desc);
create index on audit_logs (entity_type, entity_id);

-- updated_at triggers
do $$
declare t text;
begin
  foreach t in array array[
    'organizations','profiles','memberships','properties','units',
    'tenants','leases','vendors','maintenance_requests','payments'
  ] loop
    execute format(
      'create trigger trg_%1$s_updated before update on %1$s
       for each row execute function set_updated_at();', t);
  end loop;
end $$;