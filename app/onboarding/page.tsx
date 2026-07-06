import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { createOrg } from "./actions";

export default async function OnboardingPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  await requireUser();
  const supabase = await createClient();
  const { data: existing } = await supabase
    .from("memberships")
    .select("organization_id")
    .is("deleted_at", null)
    .limit(1)
    .maybeSingle();
  if (existing) redirect("/dashboard");

  const { error } = await searchParams;
  const input =
    "w-full rounded-md bg-neutral-900 border border-neutral-800 px-3 py-2 text-sm outline-none focus:border-amber-500";

  return (
    <main className="min-h-screen flex items-center justify-center bg-neutral-950 text-neutral-100 p-6">
      <div className="w-full max-w-sm space-y-6">
        <div className="space-y-1">
          <h1 className="text-xl font-semibold">Create your organization</h1>
          <p className="text-sm text-neutral-400">
            This is your workspace. You can add properties, tenants, and your team inside it.
          </p>
        </div>
        {error && (
          <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">
            {error}
          </p>
        )}
        <form action={createOrg} className="space-y-3">
          <input name="name" required placeholder="Organization name" className={input} />
          <button className="w-full rounded-md bg-amber-500 text-neutral-950 font-medium py-2 text-sm hover:bg-amber-400">
            Create organization
          </button>
        </form>
      </div>
    </main>
  );
}
