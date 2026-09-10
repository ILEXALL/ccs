const test = require('node:test');
const assert = require('node:assert/strict');
const {taskCatalog, generatePlan, datedPlan, activeWeek, COOLDOWN} = require('../lib/xp/weekly-plan');

test('two-year catalog has unique IDs, three languages and no enabled unimplemented tasks', () => {
  const items = taskCatalog();
  assert.equal(items.length, 24);
  assert.equal(new Set(items.map(item => item.id)).size, 24);
  for (const item of items) {
    assert.equal(item.available, false);
    for (const lang of ['en', 'ru', 'lv']) assert.ok(item.title[lang]);
    assert.equal(item.xp, [75, 100, 125][item.difficulty]);
    assert.ok(item.target > 0);
  }
});

test('104 weeks have unique combinations, three difficulties, 300 XP and four-week cooldown', () => {
  for (let seed = 0; seed < 100; seed++) {
    const plan = generatePlan(`test-${seed}`);
    assert.equal(plan.weeks.length, 104);
    const signatures = new Set(); const previous = new Map(); const counts = new Map();
    for (const week of plan.weeks) {
      assert.equal(week.tasks.length, 3);
      assert.deepEqual(week.tasks.map(task => task.difficulty), [0, 1, 2]);
      assert.equal(new Set(week.tasks.map(task => task.family)).size, 3);
      assert.equal(week.tasks.reduce((sum, task) => sum + task.xp, 0), 300);
      signatures.add(week.tasks.map(task => task.id).join('|'));
      for (const task of week.tasks) {
        assert.ok(week.week - (previous.get(task.id) ?? -COOLDOWN) >= COOLDOWN);
        previous.set(task.id, week.week);
        counts.set(task.id, (counts.get(task.id) || 0) + 1);
      }
    }
    assert.equal(signatures.size, 104);
    assert.equal([...counts.values()].reduce((a, b) => a + b), 312);
    assert.ok(Math.max(...counts.values()) - Math.min(...counts.values()) <= 3);
  }
});

test('refreshing is stable and changing seed changes the schedule', () => {
  assert.deepEqual(generatePlan('release-1'), generatePlan('release-1'));
  assert.notDeepEqual(generatePlan('release-1'), generatePlan('release-2'));
  assert.throws(() => generatePlan(''), /seed/);
});

test('calendar uses Monday dates through both DST changes and never wraps at week 105', () => {
  const plan = datedPlan('2026-09-14');
  assert.equal(plan.weeks[0].weekKey, '2026-09-14');
  assert.equal(plan.weeks[103].endWeekKey, '2028-09-11');
  for (let i = 0; i < 104; i++) {
    const week = plan.weeks[i];
    assert.equal(new Date(week.weekKey).getUTCDay(), 1);
    assert.equal(activeWeek(plan, week.weekKey).week, i + 1);
    if (i) assert.equal(plan.weeks[i - 1].endWeekKey, week.weekKey);
  }
  assert.equal(activeWeek(plan, '2026-09-07'), null);
  assert.equal(activeWeek(plan, '2028-09-11'), null);
  for (const invalid of ['2026-09-15', '2026-02-30', 'wrong', undefined]) {
    assert.throws(() => datedPlan(invalid), /Monday/);
  }
});
