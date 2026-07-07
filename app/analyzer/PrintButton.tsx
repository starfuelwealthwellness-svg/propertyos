"use client";

export default function PrintButton() {
  return (
    <button
      onClick={() => window.print()}
      className="rounded-md bg-amber-500 text-neutral-950 text-sm font-semibold px-4 py-2 hover:bg-amber-400"
    >
      Download / Print PDF
    </button>
  );
}
