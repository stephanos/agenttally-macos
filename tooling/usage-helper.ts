import { loadDailyUsageData } from "ccusage/data-loader";
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  writeFileSync,
} from "fs";
import os from "os";
import path from "path";

type AgentEntry = {
  name: string;
  found: boolean;
  today: number;
  month: number;
};
type UsagePayload = { agents: AgentEntry[] };

function formatLocalDay(date: Date): string {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  return formatter.format(date);
}

// ─── Claude Code ────────────────────────────────────────────────────────────

async function loadClaudeData(
  since: string,
  offline: boolean,
): Promise<AgentEntry> {
  const dailyData = await loadDailyUsageData({ since, offline });
  const today = formatLocalDay(new Date());

  return {
    name: "Claude Code",
    found: true,
    today: dailyData.find((entry) => entry.date === today)?.totalCost ?? 0,
    month: dailyData.reduce((sum, entry) => sum + entry.totalCost, 0),
  };
}

// ─── Codex ──────────────────────────────────────────────────────────────────

type ModelPricing = {
  input_cost_per_token: number;
  output_cost_per_token: number;
  cache_read_input_token_cost?: number;
};

const CODEX_MODEL_ALIASES: Record<string, string> = {
  "gpt-5-codex": "gpt-5",
  "gpt-5.3-codex": "gpt-5.2-codex",
};

const CODEX_PROVIDER_PREFIXES = [
  "openai/",
  "azure/openai/",
  "azure/",
  "openrouter/openai/",
];

// ─── Pricing cache ───────────────────────────────────────────────────────────

const LITELLM_URL =
  "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json";
const PRICING_CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const PRICING_CACHE_PATH = path.join(
  os.homedir(),
  ".cache",
  "agenttally",
  "codex-pricing.json",
);

type PricingCache = {
  fetchedAt: number;
  pricing: Record<string, ModelPricing>;
};

function parseLiteLLMEntry(data: unknown): ModelPricing | null {
  if (typeof data !== "object" || data == null) return null;
  const d = data as Record<string, unknown>;
  const input =
    typeof d.input_cost_per_token === "number" ? d.input_cost_per_token : null;
  const output =
    typeof d.output_cost_per_token === "number"
      ? d.output_cost_per_token
      : null;
  if (input == null || output == null) return null;
  return {
    input_cost_per_token: input,
    output_cost_per_token: output,
    cache_read_input_token_cost:
      typeof d.cache_read_input_token_cost === "number"
        ? d.cache_read_input_token_cost
        : undefined,
  };
}

async function loadCodexPricing(
  offline: boolean,
): Promise<Record<string, ModelPricing>> {
  try {
    const cached = JSON.parse(
      readFileSync(PRICING_CACHE_PATH, "utf8"),
    ) as PricingCache;
    if (Date.now() - cached.fetchedAt < PRICING_CACHE_TTL_MS) {
      return cached.pricing;
    }
  } catch {
    // cache miss or corrupt
  }

  if (offline)
    throw new Error(
      "Codex pricing unavailable: cache stale and in offline mode",
    );

  const response = await fetch(LITELLM_URL);
  if (!response.ok)
    throw new Error(`Failed to fetch Codex pricing: HTTP ${response.status}`);
  const raw = (await response.json()) as Record<string, unknown>;

  const pricing: Record<string, ModelPricing> = {};
  for (const [model, entry] of Object.entries(raw)) {
    const parsed = parseLiteLLMEntry(entry);
    if (parsed) pricing[model] = parsed;
  }

  mkdirSync(path.dirname(PRICING_CACHE_PATH), { recursive: true });
  writeFileSync(
    PRICING_CACHE_PATH,
    JSON.stringify({ fetchedAt: Date.now(), pricing }),
  );
  return pricing;
}

function lookupCodexPricing(
  modelName: string,
  pricing: Record<string, ModelPricing>,
): ModelPricing | null {
  // Build candidates: bare name + all provider-prefixed variants
  const candidates = [modelName];
  for (const prefix of CODEX_PROVIDER_PREFIXES) {
    if (modelName.startsWith(prefix))
      candidates.push(modelName.slice(prefix.length));
    else candidates.push(`${prefix}${modelName}`);
  }

  for (const candidate of candidates) {
    const direct = pricing[candidate];
    if (direct) return direct;
    const alias = CODEX_MODEL_ALIASES[candidate];
    if (alias && pricing[alias]) return pricing[alias]!;
  }

  // Fuzzy fallback: substring match
  const lower = modelName.toLowerCase();
  for (const [key, val] of Object.entries(pricing)) {
    if (key.toLowerCase().includes(lower) || lower.includes(key.toLowerCase()))
      return val;
  }

  return null;
}

type TokenUsage = {
  input_tokens: number;
  cached_input_tokens: number;
  output_tokens: number;
};

function calcCost(usage: TokenUsage, pricing: ModelPricing): number {
  const cachedInput = Math.min(usage.cached_input_tokens, usage.input_tokens);
  const nonCachedInput = usage.input_tokens - cachedInput;
  const cacheRate =
    pricing.cache_read_input_token_cost ?? pricing.input_cost_per_token;
  return (
    nonCachedInput * pricing.input_cost_per_token +
    cachedInput * cacheRate +
    usage.output_tokens * pricing.output_cost_per_token
  );
}

function subtractTokenUsage(
  total: TokenUsage,
  prev: TokenUsage | null,
): TokenUsage {
  if (!prev) return total;
  return {
    input_tokens: Math.max(0, total.input_tokens - prev.input_tokens),
    cached_input_tokens: Math.max(
      0,
      total.cached_input_tokens - prev.cached_input_tokens,
    ),
    output_tokens: Math.max(0, total.output_tokens - prev.output_tokens),
  };
}

function parseCodexSession(
  filePath: string,
  pricing: Record<string, ModelPricing>,
  costsByDate: Map<string, number>,
) {
  let content: string;
  try {
    content = readFileSync(filePath, "utf8");
  } catch {
    return;
  }

  let currentModel: string | null = null;
  let prevTotals: TokenUsage | null = null;

  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) continue;

    let entry: { timestamp?: string; type?: string; payload?: unknown };
    try {
      entry = JSON.parse(line) as typeof entry;
    } catch {
      continue;
    }

    if (entry.type === "turn_context") {
      const ctx = entry.payload as Record<string, unknown> | null;
      if (typeof ctx?.model === "string") currentModel = ctx.model;
      continue;
    }

    if (entry.type !== "event_msg") continue;
    const payload = entry.payload as Record<string, unknown> | null;
    if ((payload as Record<string, unknown> | null)?.type !== "token_count")
      continue;

    const info = (payload as Record<string, unknown>).info as Record<
      string,
      unknown
    > | null;
    const lastUsage = info?.last_token_usage as TokenUsage | null;
    const totalUsage = info?.total_token_usage as TokenUsage | null;

    let delta: TokenUsage | null = null;
    if (lastUsage?.input_tokens != null) {
      delta = lastUsage;
    } else if (totalUsage?.input_tokens != null) {
      delta = subtractTokenUsage(totalUsage, prevTotals);
    }
    if (totalUsage?.input_tokens != null) prevTotals = totalUsage;
    if (!delta) continue;

    const modelPricing = currentModel
      ? lookupCodexPricing(currentModel, pricing)
      : null;
    if (!modelPricing) continue;

    const cost = calcCost(delta, modelPricing);
    if (!entry.timestamp) continue;

    const date = formatLocalDay(new Date(entry.timestamp as string));
    costsByDate.set(date, (costsByDate.get(date) ?? 0) + cost);
  }
}

async function loadCodexData(
  since: string,
  offline: boolean,
): Promise<AgentEntry> {
  const codexHome =
    process.env["CODEX_HOME"] ?? path.join(os.homedir(), ".codex");
  const sessionsDir = path.join(codexHome, "sessions");
  if (!existsSync(sessionsDir)) {
    return { name: "Codex", found: false, today: 0, month: 0 };
  }

  const pricing = await loadCodexPricing(offline);

  // since is "YYYYMMDD" — derive the earliest date string "YYYY-MM-DD" for filtering
  const sinceDate = `${since.slice(0, 4)}-${since.slice(4, 6)}-${since.slice(6, 8)}`;
  const costsByDate = new Map<string, number>();

  for (const year of readdirSync(sessionsDir)) {
    for (const month of readdirSync(path.join(sessionsDir, year))) {
      for (const day of readdirSync(path.join(sessionsDir, year, month))) {
        const isoDate = `${year}-${month}-${day}`;
        if (isoDate < sinceDate) continue;

        const dayDir = path.join(sessionsDir, year, month, day);
        for (const file of readdirSync(dayDir)) {
          if (!file.endsWith(".jsonl")) continue;
          parseCodexSession(path.join(dayDir, file), pricing, costsByDate);
        }
      }
    }
  }

  const today = formatLocalDay(new Date());
  const todayCost = costsByDate.get(today) ?? 0;
  const monthCost = [...costsByDate.values()].reduce((sum, v) => sum + v, 0);

  return { name: "Codex", found: true, today: todayCost, month: monthCost };
}

// ─── Main ────────────────────────────────────────────────────────────────────

const AGENT_LOADERS = {
  claude: loadClaudeData,
  codex: loadCodexData,
} as const satisfies Record<
  string,
  (since: string, offline: boolean) => Promise<AgentEntry>
>;

type AgentID = keyof typeof AGENT_LOADERS;

const ALL_AGENTS = Object.keys(AGENT_LOADERS) as AgentID[];

function isAgentID(value: string): value is AgentID {
  return value in AGENT_LOADERS;
}

function parseRequestedAgents(args: string[]): AgentID[] {
  const requested = new Set<AgentID>();

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    let value: string | undefined;

    if (arg === "--agent") {
      value = args[++i];
    } else if (arg?.startsWith("--agent=")) {
      value = arg.slice("--agent=".length);
    } else if (arg?.startsWith("--agents=")) {
      value = arg.slice("--agents=".length);
    } else {
      continue;
    }

    if (!value) throw new Error("expected agent id after --agent");
    for (const rawAgent of value.split(",")) {
      const agent = rawAgent.trim();
      if (!isAgentID(agent)) {
        throw new Error(`unknown agent id: ${agent}`);
      }
      requested.add(agent);
    }
  }

  return requested.size > 0
    ? ALL_AGENTS.filter((agent) => requested.has(agent))
    : ALL_AGENTS;
}

async function main() {
  const since = process.argv[2];
  if (!since) {
    throw new Error("expected month start argument in YYYYMMDD format");
  }
  const offline = process.argv.includes("--offline");
  const requestedAgents = parseRequestedAgents(process.argv.slice(3));

  const agents = await Promise.all(
    requestedAgents.map((agent) => AGENT_LOADERS[agent](since, offline)),
  );

  const payload: UsagePayload = {
    agents,
  };

  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`${message}\n`);
  process.exit(1);
});
