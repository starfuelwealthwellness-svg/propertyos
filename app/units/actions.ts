"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";

function numOrNull(v: FormDataEntryValue | null) {
  const s = String(v ?? "").trim();
  if (s === "") return null;
  const n = Number(s);
  return Number.isNaN(n) ? null : n;
}

export async function createUnit(formData: FormData) {
  const { supabase, orgId } = await requireOrg();

  const property_id = String(formData.get("property_id") || "");
  if (!property_id) {
    redirect("/units/new?error=" + encodeURIComponent("Please choose a property"));
  }

  const payload = {
    organization_id: orgId,
    property_id,
    unit_number: String(formData.get("unit_number")),
    bedrooms: numOrNull(formData.get("bedrooms")),
    bathrooms: numOrNull(formData.get("bathrooms")),
    square_feet: numOrNull(formData.get("square_feet")),
    market_rent: numOrNull(formData.get("market_rent")),
    status: String(formData.get("status") || "vacant"),
  };

  const { error } = await supabase.from("units").insert(payload);
  if (error) redirect("/units/new?error=" + encodeURIComponent(error.message));

  revalidatePath("/units");
  redirect("/units");
}
