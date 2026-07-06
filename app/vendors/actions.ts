"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";

export async function createVendor(formData: FormData) {
  const { supabase, orgId } = await requireOrg();
  const payload = {
    organization_id: orgId,
    name: String(formData.get("name")),
    trade: String(formData.get("trade") || "").trim() || null,
    email: String(formData.get("email") || "").trim() || null,
    phone: String(formData.get("phone") || "").trim() || null,
  };
  const { error } = await supabase.from("vendors").insert(payload);
  if (error) redirect("/vendors/new?error=" + encodeURIComponent(error.message));
  revalidatePath("/vendors");
  redirect("/vendors");
}
