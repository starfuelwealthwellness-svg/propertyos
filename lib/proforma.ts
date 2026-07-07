// Shared pro-forma math. Mirrors the Analyzer's calculation so a saved
// deal's stored inputs recompute identically for reports.

export function computeProForma(inp: Record<string, unknown>) {
  const num = (v: unknown) => Number(v) || 0;
  const sqft = num(inp.sqft), buildPsf = num(inp.buildPsf), softPct = num(inp.softPct), landCost = num(inp.landCost);
  const hard = sqft * buildPsf;
  const soft = hard * (softPct / 100);
  const total = landCost + hard + soft;
  const finVal = num(inp.finVal) > 0 ? num(inp.finVal) : total;
  const instant = finVal - total;
  const down = total * (num(inp.downPct) / 100);
  const loan = total - down;
  const rMo = num(inp.rate) / 100 / 12;
  const nTot = num(inp.term) * 12;
  const factor = rMo === 0 ? (nTot > 0 ? 1 / nTot : 0) : (rMo * Math.pow(1 + rMo, nTot)) / (Math.pow(1 + rMo, nTot) - 1);
  const pi = loan > 0 ? loan * factor : 0;
  const debtYr = pi * 12;
  const rentMo = sqft * num(inp.rentPsf);
  const egi = rentMo * 12 * (1 - num(inp.vac) / 100);
  const noi = egi * (1 - num(inp.opex) / 100);
  const cfMo = (noi - debtYr) / 12;
  const cap = total > 0 ? noi / total : 0;
  const coc = down > 0 ? (noi - debtYr) / down : 0;
  const fv = finVal * Math.pow(1 + num(inp.appr) / 100, num(inp.hold));
  const made = Math.min(num(inp.hold) * 12, nTot);
  let bal = 0;
  if (loan > 0) {
    if (rMo === 0) bal = Math.max(0, loan * (1 - made / nTot));
    else { const a = Math.pow(1 + rMo, nTot), b = Math.pow(1 + rMo, made); bal = (loan * (a - b)) / (a - 1); }
  }
  const equity = fv - bal;
  let verdict = "Pencils";
  if (!(cfMo >= 0 && coc >= 0.05)) verdict = cfMo >= 0 ? "Tight but positive" : "Underwater";
  return { landCost, hard, soft, total, finVal, instant, down, loan, pi, rentMo, noi, cfMo, cap, coc, fv, equity, verdict, hold: num(inp.hold) };
}
