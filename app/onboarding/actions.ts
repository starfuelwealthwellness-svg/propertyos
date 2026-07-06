"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function createOrg(formData: FormData) {
  const name = String(formData.get("name") || "").trim();
  if (!name) redirect("/onboarding?error=" + encodeURIComponent("Name is required"));
  const supabase = await createClient();
  const { error } = await supabase.rpc("create_organization", { p_name: name });
  if (error) redirect("/onboarding?error=" + encodeURIComponent(error.message));
  redirect("/dashboard");
}
