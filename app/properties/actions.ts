"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";

export async function createProperty(formData: FormData) {
  const { supabase, orgId } = await requireOrg();
  const payload = {
    organization_id: orgId,
    name: String(formData.get("name")),
    address_line1: String(formData.get("address_line1")),
    city: String(formData.get("city")),
    state: String(formData.get("state")),
    postal_code: String(formData.get("postal_code")),
    property_type: String(formData.get("property_type") || "multi_family"),
  };
  const { error } = await supabase.from("properties").insert(payload);
  if (error) redirect("/properties/new?error=" + encodeURIComponent(error.message));
  revalidatePath("/properties");
  redirect("/properties");
}
