"use server";

import { requireAdmin } from "@/lib/admin";
import { createAdminClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";

async function ownerOrgIdsForEmail(email: string): Promise<string[]> {
  const admin = createAdminClient();
  const { data: profs } = await admin.from("profiles").select("id").eq("email", email);
  const ids = (profs ?? []).map((p: any) => p.id);
  if (ids.length === 0) return [];
  const { data: mems } = await admin
    .from("memberships").select("organization_id")
    .in("user_id", ids).eq("role", "owner").is("deleted_at", null);
  return Array.from(new Set((mems ?? []).map((m: any) => m.organization_id)));
}

export async function grantComp(formData: FormData) {
  await requireAdmin();
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const days = Math.max(1, Number(formData.get("days") ?? 90) || 90);
  if (!email) redirect("/admin");

  const orgIds = await ownerOrgIdsForEmail(email);
  if (orgIds.length === 0) redirect("/admin?msg=noaccount&email=" + encodeURIComponent(email));

  const expires = new Date(Date.now() + days * 86400000).toISOString();
  const admin = createAdminClient();
  await admin.from("organizations")
    .update({ pro_comp: true, pro_comp_expires_at: expires })
    .in("id", orgIds);

  redirect("/admin?msg=granted&email=" + encodeURIComponent(email) + "&days=" + days);
}

export async function revokeComp(formData: FormData) {
  await requireAdmin();
  const orgId = String(formData.get("orgId") ?? "");
  if (!orgId) redirect("/admin");
  const admin = createAdminClient();
  await admin.from("organizations")
    .update({ pro_comp: false, pro_comp_expires_at: null })
    .eq("id", orgId);
  redirect("/admin?msg=revoked");
}
