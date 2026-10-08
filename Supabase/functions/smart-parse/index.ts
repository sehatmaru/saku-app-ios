// Smart Tracker: turns one sentence the on-device rules could not read into draft transactions.
// Only the sentence, wallet names, category names and today's date arrive here: no balances, no
// account numbers, nothing is stored or logged. The model key lives only in this function's secrets
// (ANTHROPIC_API_KEY); the provider must not retain or train on the request (zero-retention terms).
import { createClient } from "jsr:@supabase/supabase-js@2";

const MODEL = Deno.env.get("SMART_PARSE_MODEL") ?? "claude-haiku-4-5-20251001";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  // signed-in users only
  const auth = req.headers.get("Authorization") ?? "";
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
  });
  const { data: user } = await supabase.auth.getUser();
  if (!user?.user) return new Response("unauthorized", { status: 401 });

  const { text, wallets, categories, today } = await req.json();
  if (typeof text !== "string" || text.length === 0 || text.length > 600) {
    return new Response(JSON.stringify({ drafts: [] }), { headers: { "content-type": "application/json" } });
  }

  const system = `You turn a short Indonesian or English sentence about money into draft transactions.
Reply with JSON only: {"drafts":[{"kind":"expense|income|transfer|cardPayment","amount":number,"title":string,
"wallet":string|null,"toWallet":string|null,"category":string|null,"daysAgo":number}]}.
Rules: amounts are in rupiah (25rb=25000, 2,5jt=2500000, goceng=5000, ceban=10000, gocap=50000, cepek=100000).
"wallet" is the wallet money leaves (or arrives in for income) and "toWallet" the destination of a transfer; both must be copied
exactly from the wallet list or be null. "category" must be copied exactly from the category list or be null.
Top ups between wallets, deposits to investment wallets and card bill payments are never expenses.
Never invent an amount: if there is none, return {"drafts":[]}. today is ${today}. Wallets: ${JSON.stringify(wallets)}.
Categories: ${JSON.stringify(categories)}.`;

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({ model: MODEL, max_tokens: 600, system, messages: [{ role: "user", content: text }] }),
  });
  if (!response.ok) return new Response(JSON.stringify({ drafts: [] }), { status: 502, headers: { "content-type": "application/json" } });

  const body = await response.json();
  const raw: string = body?.content?.[0]?.text ?? "{}";
  let drafts: unknown[] = [];
  try {
    drafts = JSON.parse(raw.slice(raw.indexOf("{"), raw.lastIndexOf("}") + 1)).drafts ?? [];
  } catch (_) { /* unreadable reply: no drafts */ }
  return new Response(JSON.stringify({ drafts }), { headers: { "content-type": "application/json" } });
});
