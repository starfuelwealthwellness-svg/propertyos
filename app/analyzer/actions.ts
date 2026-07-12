"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { requireOrg } from "@/lib/auth";
import { computeProForma } from "@/lib/proforma";

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

const ERR = (msg: string) => redirect("/analyzer/saved?error=" + encodeURIComponent(msg));

export async function sendToAcquisition(formData: FormData) {
  const dealId = String(formData.get("id"));
  const { supabase, orgId, user } = await requireOrg();

  const { data: org } = await supabase
    .from("organizations").select("plan").eq("id", orgId).maybeSingle();
  if ((org as any)?.plan !== "pro") ERR("Sending deals is a Pro feature.");
  if (!user.email) ERR("Your account has no email on file.");

  const { data: deal } = await supabase
    .from("analyses").select("*").eq("id", dealId).is("deleted_at", null).maybeSingle();
  if (!deal) ERR("Deal not found.");
  const d = deal as any;

  const base = process.env.ACQUISITION_ENGINE_URL;
  const secret = process.env.ACQUISITION_INGEST_SECRET;
  if (!base || !secret) ERR("Acquisition Engine isn't configured (missing URL or key).");

  const c = computeProForma(d.inputs || {});
  const payload = {
    source: "propertyos",
    source_ref: d.id,
    email: user.email,
    name: d.name,
    address: d.address || undefined,
    plan_name: d.plan_name || undefined,
    total_project_cost: Math.round(c.total),
    monthly_cash_flow: Math.round(c.cfMo),
    cap_rate: Number(c.cap.toFixed(4)),
    cash_on_cash: Number(c.coc.toFixed(4)),
    verdict: c.verdict,
    notes: "Imported from Starfuel PropertyOS Infill Build Analyzer",
  };

  let res: Response;
  try {
    res = await fetch(base + "/api/deals/ingest", {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-api-key": secret! },
      body: JSON.stringify(payload),
      cache: "no-store",
    });
  } catch {
    ERR("Could not reach the Acquisition Engine.");
    return;
  }

  if (res.status === 404) ERR("No Acquisition Engine account for " + user.email + ". Sign up there with the same email first.");
  if (res.status === 401) ERR("Acquisition Engine rejected the key — check the shared secret matches in both apps.");
  if (!res.ok) ERR("Send failed (HTTP " + res.status + ").");

  const bodyJson: any = await res.json().catch(() => ({}));
  await supabase.from("analyses").update({
    sent_to_acquisition_at: new Date().toISOString(),
    acquisition_deal_id: bodyJson?.dealId ?? null,
  }).eq("id", dealId);

  revalidatePath("/analyzer/saved");
  redirect("/analyzer/saved?sent=" + (bodyJson?.deduped ? "already" : "1"));
}
