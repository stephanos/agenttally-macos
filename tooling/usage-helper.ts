import { loadDailyUsageData } from "ccusage/data-loader";

type UsagePayload = {
  today: number;
  month: number;
};

function formatLocalDay(date: Date): string {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  return formatter.format(date);
}

async function main() {
  const since = process.argv[2];
  if (!since) {
    throw new Error("expected month start argument in YYYYMMDD format");
  }

  const dailyData = await loadDailyUsageData({ since });
  const today = formatLocalDay(new Date());

  const payload: UsagePayload = {
    today: dailyData.find((entry) => entry.date === today)?.totalCost ?? 0,
    month: dailyData.reduce((sum, entry) => sum + entry.totalCost, 0),
  };

  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`${message}\n`);
  process.exit(1);
});
