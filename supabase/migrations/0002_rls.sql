-- ============================================================
-- PropertyOS — 0002_rls.sql
-- Row-Level Security: the load-bearing tenant-isolation layer.
-- Run this AFTER 0001_init.sql.
--
-- Pattern: every tenant-scoped table only exposes rows whose
-- organization_id is one the logged-in user belongs to. This is
-- enforced at the database, so a forgotten WHERE clause in app
-- code can never leak another org's data.
--
-- NOTE: the service_role key bypasses RLS entirely (by design),
-- so server-side privileged jobs (audit writes, Stripe webhooks)
-- still work. Never expose service_role to the browser.
-- ============================================================

-- ---- IDENTITY -------------------------------------------------
alter table profiles enable row level security;
create policy "own profile read"  on profiles for select using (id = auth.uid());
create policy "own profile write" on profiles for update using (id = auth.uid()) with check (id = auth.uid());

alter table organizations enable row level security;
-- Any authenticated user may create an org (onboarding); they then
-- self-insert an 'owner' membership (below) to gain access to it.
create policy "create org"  on organizations for insert with check (auth.uid() is not null);
create policy "read own orgs" on organizations for select using (id in (select current_user_org_ids()));
create policy "update own orgs" on organizations for update using (id in (select current_user_org_ids())) with check (id in (select current_user_org_ids()));

alter table memberships enable row level security;
-- Read memberships for orgs you belong to (so admins can see the team).
create policy "read memberships" on memberships for select using (organization_id in (select current_user_org_ids()));
-- During onboarding a user inserts their OWN owner membership.
-- Granting other users access (admin invites) is a server-side
-- (service_role) action and intentionally not allowed via this policy.
create policy "self join" on memberships for insert with check (user_id = auth.uid());

-- ---- TENANT-SCOPED TABLES ------------------------------------
-- Same shape for each: full access limited to the user's orgs.

alter table properties enable row level security;
create policy "org access" on properties for all
  using (organization_id in (select current_user_org_ids()))
  with check (organization_id in (select current_user_org_ids()));

alter table units enable row level security;
create policy "org access" on units for all
  using (organization_id in (select current_user_org_ids()))
  with check (organization_id in (select current_user_org_ids()));

alter table tenants enable row level security;
create policy "org access" on tenants for all
  using (organization_id in (select current_user_org_ids()))
  with check (organization_id in (select current_user_org_ids()));

alter table leases enable row level security;
create policy "org access" on leases for all
  using (organization_id in (select current_user_org_ids()))
  with check (organization_id in (select current_user_org_ids()));

alter table vendors enable row level security;
create policy "org access" on vendors for all
  using (organization_id in (select current_user_org_ids()))
  with check (organization_id in (select current_user_org_ids()));

alter table maintenance_requests enable row level security;
create policy "org access" on maintenance_requests for all
  using (organization_id in (select current_user_org_ids()))
  with check (organization_id in (select current_user_org_ids()));

alter table payments enable row level security;
create policy "org access" on payments for all
  using (organization_id in (select current_user_org_ids()))
  with check (organization_id in (select current_user_org_ids()));

alter table documents enable row level security;
create policy "org access" on documents for all
  using (organization_id in (select current_user_org_ids()))
  with check (organization_id in (select current_user_org_ids()));

-- lease_tenants has no organization_id; gate it through its lease.
alter table lease_tenants enable row level security;
create policy "via lease" on lease_tenants for all
  using (lease_id in (select id from leases where organization_id in (select current_user_org_ids())))
  with check (lease_id in (select id from leases where organization_id in (select current_user_org_ids())));

-- ---- USER-SCOPED & AUDIT -------------------------------------
alter table notifications enable row level security;
create policy "own notifications" on notifications for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Audit logs: readable by org members; writes happen server-side
-- via service_role (which bypasses RLS), so no insert policy here.
alter table audit_logs enable row level security;
create policy "read org audit" on audit_logs for select
  using (organization_id in (select current_user_org_ids()));
