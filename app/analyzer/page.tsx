import { requireOrg } from "@/lib/auth";
import AppHeader from "@/app/_components/AppHeader";
import Analyzer from "./Analyzer";

export default async function AnalyzerPage() {
  const { membership } = await requireOrg();
  const orgName = (membership as any).organizations?.name ?? "Your organization";
  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100">
      <AppHeader orgName={orgName} />
      <main className="max-w-5xl mx-auto px-6 py-8">
        <Analyzer />
      </main>
    </div>
  );
}
