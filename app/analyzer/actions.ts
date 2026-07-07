"use server";

import { requireOrg } from "@/lib/auth";

type SaveInput = {
  name: string; address: string; planName: string; inputs: unknown; summary: unknown;
};

export async function saveAnalysis(data: SaveInput) {
  const { supabase, orgId, user } = await requireOrg();

  const { data: org } = await supabase
    .from("organizations").select("plan").eq("id", orgId).maybeSingle();
  if ((org as any)?.plan !== "pro") {
    return { ok: false as const, error: "Saving deals is a Pro feature." };
  }

  const { error } = await supabase.from("analyses").insert({
    organization_id: orgId,
    created_by: user.id,
    name: (data.name || "Untitled deal").slice(0, 120),
    address: data.address || null,
    plan_name: data.planName || null,
    inputs: data.inputs ?? {},
    summary: data.summary ?? {},
  });
  if (error) return { ok: false as const, error: error.message };
  return { ok: true as const };
}
