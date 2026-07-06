"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";

export async function createMaintenanceRequest(formData: FormData) {
  const { supabase, orgId, user } = await requireOrg();
  const unit_id = String(formData.get("unit_id") || "");
  if (!unit_id) {
    redirect("/maintenance/new?error=" + encodeURIComponent("Please choose a unit"));
  }
  const payload = {
    organization_id: orgId,
    unit_id,
    reported_by: user.id,
    title: String(formData.get("title")),
    description: String(formData.get("description") || "").trim() || null,
    priority: String(formData.get("priority") || "normal"),
  };
  const { error } = await supabase.from("maintenance_requests").insert(payload);
  if (error) redirect("/maintenance/new?error=" + encodeURIComponent(error.message));
  revalidatePath("/maintenance");
  revalidatePath("/dashboard");
  redirect("/maintenance");
}

export async function updateMaintenanceStatus(formData: FormData) {
  const { supabase } = await requireOrg();
  const id = String(formData.get("id"));
  const status = String(formData.get("status"));
  const { error } = await supabase
    .from("maintenance_requests")
    .update({ status })
    .eq("id", id);
  if (error) redirect("/maintenance/" + id + "?error=" + encodeURIComponent(error.message));
  revalidatePath("/maintenance/" + id);
  revalidatePath("/maintenance");
  revalidatePath("/dashboard");
  redirect("/maintenance/" + id);
}

export async function assignVendor(formData: FormData) {
  const { supabase } = await requireOrg();
  const id = String(formData.get("id"));
  const vendor_id = String(formData.get("vendor_id") || "").trim() || null;

  const update: { assigned_vendor: string | null; status?: string } = {
    assigned_vendor: vendor_id,
  };

  // If we just assigned a vendor and the ticket is still early-stage,
  // nudge it forward to 'assigned'.
  if (vendor_id) {
    const { data: cur } = await supabase
      .from("maintenance_requests")
      .select("status")
      .eq("id", id)
      .maybeSingle();
    if (cur && (cur.status === "open" || cur.status === "triaged")) {
      update.status = "assigned";
    }
  }

  const { error } = await supabase
    .from("maintenance_requests")
    .update(update)
    .eq("id", id);
  if (error) redirect("/maintenance/" + id + "?error=" + encodeURIComponent(error.message));
  revalidatePath("/maintenance/" + id);
  revalidatePath("/maintenance");
  revalidatePath("/dashboard");
  redirect("/maintenance/" + id);
}

export async function deleteRequest(formData: FormData) {
  const { supabase } = await requireOrg();
  const id = String(formData.get("id"));
  const { error } = await supabase
    .from("maintenance_requests")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", id);
  if (error) redirect("/maintenance/" + id + "?error=" + encodeURIComponent(error.message));
  revalidatePath("/maintenance");
  revalidatePath("/dashboard");
  redirect("/maintenance");
}
