-- PropertyOS — 0003_onboarding.sql
-- A transactional helper to create an organization AND make the
-- current user its owner, in one atomic step. SECURITY DEFINER so it
-- can insert both rows, but it ties the membership to auth.uid(), so a
-- user can only ever make THEMSELVES an owner of a NEW org.

create or replace function create_organization(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_slug text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  v_slug := lower(regexp_replace(p_name, '[^a-zA-Z0-9]+', '-', 'g'))
            || '-' || substr(gen_random_uuid()::text, 1, 8);

  insert into organizations (name, slug)
  values (p_name, v_slug)
  returning id into v_org_id;

  insert into memberships (organization_id, user_id, role)
  values (v_org_id, auth.uid(), 'owner');

  return v_org_id;
end $$;

grant execute on function create_organization(text) to authenticated;
