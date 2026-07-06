import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import { createProperty } from "../actions";

export default async function NewPropertyPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  const { error } = await searchParams;
  const input =
    "w-full rounded-md bg-neutral-900 border border-neutral-800 px-3 py-2 text-sm outline-none focus:border-amber-500";

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-lg mx-auto px-6 py-8 space-y-6">
        <h1 className="text-xl font-semibold">Add property</h1>
        {error && (
          <p className="text-sm text-red-400 bg-red-950/40 border border-red-900 rounded-md p-3">
            {error}
          </p>
        )}
        <form action={createProperty} className="space-y-3">
          <input name="name" required placeholder="Property name" className={input} />
          <input name="address_line1" required placeholder="Street address" className={input} />
          <div className="grid grid-cols-2 gap-3">
            <input name="city" required placeholder="City" className={input} />
            <input name="state" required placeholder="State" className={input} />
          </div>
          <input name="postal_code" required placeholder="ZIP" className={input} />
          <select name="property_type" defaultValue="multi_family" className={input}>
            <option value="single_family">Single family</option>
            <option value="multi_family">Multi family</option>
            <option value="commercial">Commercial</option>
            <option value="mixed_use">Mixed use</option>
          </select>
          <button className="w-full rounded-md bg-amber-500 text-neutral-950 font-medium py-2 text-sm hover:bg-amber-400">
            Save property
          </button>
        </form>
      </main>
    </div>
  );
}
