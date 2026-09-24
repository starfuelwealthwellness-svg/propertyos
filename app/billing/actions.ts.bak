"use server";

import { redirect } from "next/navigation";
import { requireOrg } from "@/lib/auth";
import { stripe } from "@/lib/stripe";

export async function startProCheckout() {
  const { supabase, orgId, user } = await requireOrg();
  const { data: org } = await supabase
    .from("organizations").select("plan, stripe_customer_id").eq("id", orgId).maybeSingle();
  const o = org as any;
  if (o?.plan === "pro") redirect("/billing");

  const appUrl = process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3004";
  let url: string | null = null;
  try {
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: process.env.STRIPE_PRO_PRICE_ID!, quantity: 1 }],
      customer: o?.stripe_customer_id || undefined,
      customer_email: o?.stripe_customer_id ? undefined : (user.email || undefined),
      metadata: { organization_id: orgId },
      subscription_data: { metadata: { organization_id: orgId } },
      success_url: appUrl + "/billing?upgraded=1",
      cancel_url: appUrl + "/billing?canceled=1",
    });
    url = session.url;
  } catch (e: any) {
    redirect("/billing?error=" + encodeURIComponent(e?.message ?? "Stripe error"));
  }
  redirect(url!);
}

export async function openBillingPortal() {
  const { supabase, orgId } = await requireOrg();
  const { data: org } = await supabase
    .from("organizations").select("stripe_customer_id").eq("id", orgId).maybeSingle();
  const customer = (org as any)?.stripe_customer_id;
  if (!customer) redirect("/billing?error=" + encodeURIComponent("No billing account yet."));

  const appUrl = process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3004";
  let url: string | null = null;
  try {
    const portal = await stripe.billingPortal.sessions.create({ customer, return_url: appUrl + "/billing" });
    url = portal.url;
  } catch (e: any) {
    redirect("/billing?error=" + encodeURIComponent(e?.message ?? "Stripe error"));
  }
  redirect(url!);
}
