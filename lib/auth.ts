import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function getUser() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return { supabase, user };
}

export async function requireUser() {
  const { supabase, user } = await getUser();
  if (!user) redirect("/login");
  return { supabase, user };
}

export async function requireOrg() {
  const { supabase, user } = await requireUser();
  const { data: membership } = await supabase
    .from("memberships")
    .select("organization_id, role, organizations(name)")
    .is("deleted_at", null)
    .limit(1)
    .maybeSingle();
  if (!membership) redirect("/onboarding");
  return {
    supabase,
    user,
    orgId: membership.organization_id as string,
    membership,
  };
}
