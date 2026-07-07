-- PropertyOS — 0006_analyzer_pro.sql
-- Adds a per-org plan flag (free/pro) and a table of saved analyses.

alter table organizations
  add column if not exists plan text not null default 'free'
  check (plan in ('free','pro'));

create table if not exists analyses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  created_by uuid references profiles(id),
  name text not null,
  address text,
  plan_name text,
  inputs jsonb not null default '{}',
  summary jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists analyses_org_idx on analyses (organization_id) where deleted_at is null;

alter table analyses enable row level security;
create policy "org access" on analyses for all
  using (organization_id in (select current_user_org_ids()))
  with check (organization_id in (select current_user_org_ids()));

create trigger trg_analyses_updated before update on analyses
  for each row execute function set_updated_at();
