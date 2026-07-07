import Link from "next/link";
import { signOut } from "@/app/login/actions";

export default function AppHeader({ orgName }: { orgName: string }) {
  return (
    <header className="border-b border-neutral-800 bg-neutral-950">
      <div className="max-w-6xl mx-auto px-6 py-3 flex items-center justify-between">
        <div className="flex items-center gap-5">
          <span className="font-semibold text-amber-400">PropertyOS</span>
          <nav className="flex gap-4 text-sm text-neutral-300">
            <Link href="/dashboard" className="hover:text-white">Dashboard</Link>
            <Link href="/properties" className="hover:text-white">Properties</Link>
            <Link href="/units" className="hover:text-white">Units</Link>
            <Link href="/tenants" className="hover:text-white">Tenants</Link>
            <Link href="/leases" className="hover:text-white">Leases</Link>
            <Link href="/payments" className="hover:text-white">Payments</Link>
            <Link href="/maintenance" className="hover:text-white">Maintenance</Link>
            <Link href="/vendors" className="hover:text-white">Vendors</Link>
            <Link href="/analyzer" className="hover:text-white text-amber-300">Analyzer</Link>
          </nav>
        </div>
        <div className="flex items-center gap-3 text-sm">
          <span className="text-neutral-400">{orgName}</span>
          <form action={signOut}>
            <button className="text-neutral-400 hover:text-white">Sign out</button>
          </form>
        </div>
      </div>
    </header>
  );
}
