// Google Cloud Billing Catalog, Standard edition Stockholm, EUR, checked 2026-10-21.
// SKUs: reads 3673-21F3-5D02, writes 4878-C834-5ED6, deletes DBD8-B515-47CE.
const pricing = {
  reads: {eur: 281 / 1e9, free: 50000},
  writes: {eur: 835 / 1e9, free: 20000},
  deletes: {eur: 96 / 1e9, free: 20000},
};
const quotaDate = new Intl.DateTimeFormat('en-CA', {timeZone: 'America/Los_Angeles', year: 'numeric', month: '2-digit', day: '2-digit'});
function estimateOperations(seriesByOperation, monthStartMillis) {
  const breakdown = {};
  let amountEur = 0;
  let samples = 0;
  for (const [operation, rate] of Object.entries(pricing)) {
    const days = new Map();
    for (const series of seriesByOperation[operation] || []) for (const point of series.points || []) {
      const time = Date.parse(point.interval?.endTime) - 1;
      const count = Number(point.value?.int64Value ?? point.value?.doubleValue);
      if (!Number.isFinite(time) || !Number.isFinite(count) || count < 0) continue;
      if (time >= monthStartMillis) samples++;
      const key = quotaDate.format(new Date(time));
      const day = days.get(key) || {before: 0, month: 0};
      day[time < monthStartMillis ? 'before' : 'month'] += count;
      days.set(key, day);
    }
    let billable = 0;
    for (const day of days.values()) billable += Math.max(0, day.before + day.month - rate.free) - Math.max(0, day.before - rate.free);
    const cost = billable * rate.eur;
    breakdown[operation] = {billable, amountEur: cost};
    amountEur += cost;
  }
  if (!samples) throw new Error('Monthly cost metric samples unavailable');
  return {amountEur, breakdown, currency: 'EUR', pricingChecked: '2026-10-21',
    scope: 'document_operations', startMillis: monthStartMillis};
}
module.exports = {estimateOperations};
