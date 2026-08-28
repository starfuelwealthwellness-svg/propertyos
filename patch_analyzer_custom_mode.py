#!/usr/bin/env python3
# Adds a "Tulsa catalog" / "Custom build" toggle to the Infill Build Analyzer,
# so subscribers outside Tulsa can analyze any lot + plan by entering their own
# square footage, beds, and units. Purely additive: the math, save flow,
# break-even solver, and Tulsa catalog all keep working exactly as before.
#
# Run from the PropertyOS project root:  python3 patch_analyzer_custom_mode.py

import re, sys, shutil, pathlib

PATH = pathlib.Path("app/analyzer/Analyzer.tsx")
if not PATH.exists():
    sys.exit("ERROR: app/analyzer/Analyzer.tsx not found. Run from the project root.")

src = PATH.read_text()
orig = src

def replace_once(old, new, label):
    global src
    if old not in src:
        sys.exit(f"ERROR: could not find the section to patch: {label}\n"
                 f"(The file may have changed since this script was written. "
                 f"Nothing was modified.)")
    if src.count(old) != 1:
        sys.exit(f"ERROR: expected exactly one match for: {label} (found {src.count(old)}). Aborting.")
    src = src.replace(old, new)

# 1) Add `mode` state right after the main form state hook.
replace_once(
    '  const [saveName, setSaveName] = useState("");',
    '  const [mode, setMode] = useState<"tulsa" | "custom">("tulsa");\n'
    '  const [saveName, setSaveName] = useState("");',
    "mode state",
)

# 2) Subtitle: reflect the active mode.
replace_once(
    '''          Pair a vacant Tulsa lot with a pre-approved T-Town HOME Catalog plan and see the build-to-own numbers in real time.
        </p>''',
    '''          {mode === "tulsa"
            ? "Pair a vacant Tulsa lot with a pre-approved T-Town HOME Catalog plan and see the build-to-own numbers in real time."
            : "Enter any lot and any plan's details and see the build-to-own numbers in real time — anywhere."}
        </p>
        <div className="mt-3 inline-flex rounded-lg border border-neutral-800 bg-neutral-900 p-1 text-sm">
          <button type="button" onClick={() => setMode("tulsa")}
            className={"px-3 py-1.5 rounded-md font-medium " + (mode === "tulsa" ? "bg-amber-500 text-neutral-950" : "text-neutral-400 hover:text-neutral-200")}>
            Tulsa catalog
          </button>
          <button type="button" onClick={() => setMode("custom")}
            className={"px-3 py-1.5 rounded-md font-medium " + (mode === "custom" ? "bg-amber-500 text-neutral-950" : "text-neutral-400 hover:text-neutral-200")}>
            Custom build
          </button>
        </div>''',
    "subtitle + toggle",
)

# 3) The catalog dropdown block -> show it only in Tulsa mode.
replace_once(
    '''          <div>
            <label className={label}>Catalog plan (T-Town HOME Catalog)</label>
            <select className={input} value={f.planIdx} onChange={(e) => setPlan(Number(e.target.value))}>
              {PLANS.map((p, i) => <option key={i} value={i}>{p.name} — {p.short}</option>)}
            </select>
            <div className="flex flex-wrap gap-2 mt-2">
              <span className="text-xs bg-neutral-800 border border-neutral-700 rounded px-2 py-0.5 text-neutral-300">{plan.mix}</span>
              <span className="text-xs bg-neutral-800 border border-neutral-700 rounded px-2 py-0.5 text-neutral-300">{plan.stories} stories</span>
              {plan.ami !== "\u2014" && <span className="text-xs bg-amber-500/15 border border-amber-500/40 rounded px-2 py-0.5 text-amber-300 font-medium">{plan.ami}</span>}
            </div>
          </div>''',
    '''          {mode === "tulsa" ? (
            <div>
              <label className={label}>Catalog plan (T-Town HOME Catalog)</label>
              <select className={input} value={f.planIdx} onChange={(e) => setPlan(Number(e.target.value))}>
                {PLANS.map((p, i) => <option key={i} value={i}>{p.name} \u2014 {p.short}</option>)}
              </select>
              <div className="flex flex-wrap gap-2 mt-2">
                <span className="text-xs bg-neutral-800 border border-neutral-700 rounded px-2 py-0.5 text-neutral-300">{plan.mix}</span>
                <span className="text-xs bg-neutral-800 border border-neutral-700 rounded px-2 py-0.5 text-neutral-300">{plan.stories} stories</span>
                {plan.ami !== "\u2014" && <span className="text-xs bg-amber-500/15 border border-amber-500/40 rounded px-2 py-0.5 text-amber-300 font-medium">{plan.ami}</span>}
              </div>
            </div>
          ) : (
            <div className="grid grid-cols-3 gap-3">
              <div><label className={label}>Beds</label><input className={input} type="number" value={f.beds} onChange={(e) => set("beds", e.target.value)} /></div>
              <div><label className={label}>Units</label><input className={input} type="number" value={f.units} onChange={(e) => set("units", e.target.value)} /></div>
              <div><label className={label}>Stories</label><input className={input} type="number" defaultValue={2} /></div>
            </div>
          )}''',
    "catalog dropdown (mode-gated)",
)

# 4) Footnote: source line depends on mode.
replace_once(
    '''            Plan specs are from the City of Tulsa T-Town HOME Catalog. Cost, rent, and financing figures are editable estimates for planning only \u2014 not financial advice.''',
    '''            {mode === "tulsa"
              ? "Plan specs are from the City of Tulsa T-Town HOME Catalog. "
              : "Custom mode: all specs are your own inputs. "}
            Cost, rent, and financing figures are editable estimates for planning only \u2014 not financial advice.''',
    "footnote",
)

# Safety: back up original, then write.
shutil.copy(PATH, PATH.with_suffix(".tsx.bak"))
PATH.write_text(src)
print("Patched app/analyzer/Analyzer.tsx")
print("Backup saved at app/analyzer/Analyzer.tsx.bak")
print("Changes:", src.count("mode ==="), "mode-aware branches added.")
