"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";

export async function createTenant(formData: FormData) {
  const { supabase, orgId } = await requireOrg();
  const payload = {
    organization_id: orgId,
    full_name: String(formData.get("full_name")),
    email: String(formData.get("email") || "").trim() || null,
    phone: String(formData.get("phone") || "").trim() || null,
  };
  const { error } = await supabase.from("tenants").insert(payload);
  if (error) redirect("/tenants/new?error=" + encodeURIComponent(error.message));
  revalidatePath("/tenants");
  redirect("/tenants");
}
