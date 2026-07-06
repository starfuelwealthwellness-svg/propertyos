"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";

function emptyToNull(v: FormDataEntryValue | null) {
  const s = String(v ?? "").trim();
  return s === "" ? null : s;
}

export async function createLease(formData: FormData) {
  const { supabase } = await requireOrg();

  const unit_id = String(formData.get("unit_id") || "");
  const tenant_id = String(formData.get("tenant_id") || "");
  if (!unit_id || !tenant_id) {
    redirect("/leases/new?error=" + encodeURIComponent("Choose both a unit and a tenant"));
  }

  const rentStr = String(formData.get("rent_amount") || "").trim();
  const rent = rentStr === "" ? NaN : Number(rentStr);
  if (Number.isNaN(rent)) {
    redirect("/leases/new?error=" + encodeURIComponent("Enter a valid rent amount"));
  }

  const depositStr = String(formData.get("deposit_amount") || "").trim();
  const deposit = depositStr === "" ? null : Number(depositStr);

  const start = emptyToNull(formData.get("start_date"));
  if (!start) {
    redirect("/leases/new?error=" + encodeURIComponent("Enter a start date"));
  }
  const end = emptyToNull(formData.get("end_date"));

  const { error } = await supabase.rpc("create_lease", {
    p_unit_id: unit_id,
    p_tenant_id: tenant_id,
    p_rent: rent,
    p_deposit: deposit,
    p_start: start,
    p_end: end,
  });
  if (error) redirect("/leases/new?error=" + encodeURIComponent(error.message));

  revalidatePath("/leases");
  revalidatePath("/units");
  revalidatePath("/dashboard");
  redirect("/leases");
}
