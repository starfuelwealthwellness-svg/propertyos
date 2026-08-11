import { requireOrg } from "@/lib/auth";
import { notFound } from "next/navigation";

export async function requireAdmin() {
  // requireOrg already enforces a logged-in user with an org.
  const { supabase } = await requireOrg();
  const { data: { user } } = await supabase.auth.getUser();

  const admins = (process.env.ADMIN_EMAILS ?? "")
    .split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
  const email = (user?.email ?? "").toLowerCase();

  if (!email || !admins.includes(email)) notFound();
  return { email };
}
