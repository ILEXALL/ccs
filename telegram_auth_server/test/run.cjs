const { spawnSync } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');
const readline = require('node:readline/promises');

const suites = {
  xp: { name: 'XP', files: ['xp.test.js', 'xp-matrix.test.js'],
    gaps: ['Правила Firebase, одновременные запросы, интерфейс и доставка пушей'] },
  profiles: { name: 'Profiles', files: ['workflows.test.js'], pattern: '\\[profiles\\]',
    gaps: ['Редактирование профиля, сохранение гаража, загрузка фото и правила приватности'] },
  spots: { name: 'Spots', files: ['workflows.test.js'], pattern: '\\[spots\\]',
    gaps: ['Создание, загрузка фото, фильтры, удаление и блокировка модерации через Firebase'] },
  moderation: { name: 'Moderation', files: ['workflows.test.js'], pattern: '\\[moderation\\]',
    gaps: ['Одобрение и отклонение спотов, одновременная работа модераторов'] },
  chats: { name: 'Chats', files: ['workflows.test.js'], pattern: '\\[chats\\]',
    gaps: ['Отправка и получение сообщений, вложения, обновления и пуши'] },
  access: { name: 'Access', files: ['workflows.test.js'], pattern: '\\[access\\]',
    gaps: ['Настоящий вход, истечение токенов и правила Firebase'] },
  notifications: { name: 'Notifications', files: ['xp.test.js'], pattern: 'notification',
    gaps: ['Доставка пушей на телефон, локализация и уведомления вне XP'] },
};

async function main() {
  let [selection, ...flags] = process.argv.slice(2);
  if (selection === '--list') {
    console.log('all: All available checks (partial app coverage)');
    for (const [id, suite] of Object.entries(suites)) console.log(`${id}: ${suite.name} (partial)`);
    console.log('emulator: Правила Firebase и модерация (локальная база)');
    return;
  }
  if (!selection && process.stdin.isTTY) {
    const ids = ['all', ...Object.keys(suites), 'emulator'];
    console.log('CCS checks / Проверки CCS');
    ids.forEach((id, i) => console.log(`${i + 1}. ${id === 'all' ? 'Все быстрые проверки' : id === 'emulator' ? 'Firebase Emulator: права и модерация' : suites[id].name}`));
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    try { selection = ids[Number(await rl.question('Номер раздела: ')) - 1]; }
    finally { rl.close(); }
  }
  if (selection === 'emulator') {
    if (flags.length) { console.error('Emulator mode does not accept extra arguments.'); process.exitCode = 2; return; }
    const result = spawnSync(process.execPath, [path.join(__dirname, 'emulator.cjs')], { stdio: 'inherit' });
    if (result.error) console.error(result.error.message);
    process.exitCode = result.status ?? 1;
    return;
  }
  const reportIndex = flags.indexOf('--report');
  const reportPath = reportIndex === -1 ? null : flags[reportIndex + 1];
  if (!selection || (selection !== 'all' && !suites[selection]) ||
      (flags.length && !(flags.length === 2 && reportIndex === 0 && reportPath))) {
    console.error(`Usage: node test/run.cjs all|${Object.keys(suites).join('|')} [--report path.json]`);
    process.exitCode = 2; return;
  }
  const chosen = selection === 'all' ? Object.values(suites) : [suites[selection]];
  const files = [...new Set(chosen.flatMap((s) => s.files))].map((f) => path.join(__dirname, f));
  const args = ['--test', '--test-isolation=none', '--test-reporter=tap'];
  if (selection !== 'all' && suites[selection].pattern) args.push(`--test-name-pattern=${suites[selection].pattern}`);
  const result = spawnSync(process.execPath, [...args, ...files], { encoding: 'utf8', timeout: 120000, maxBuffer: 8 * 1024 * 1024 });
  const output = result.stdout || '';
  const count = (name) => Number(output.match(new RegExp(`^# ${name} (\\d+)`, 'm'))?.[1] || 0);
  const passed = count('pass');
  const failed = count('fail');
  const ok = result.status === 0 && passed > 0 && failed === 0;
  const report = { selection, checkedAt: new Date().toISOString(),
    status: ok ? 'passed' : 'failed', coverage: 'partial', passed, failed,
    skipped: count('skipped'), untested: chosen.flatMap((s) => s.gaps),
    environment: 'offline doubles; no production access',
    error: result.error?.message || null, output, stderr: result.stderr || '' };
  console.log(`Раздел: ${selection}. Успешно: ${passed}. Ошибок: ${failed}.`);
  console.log('Покрытие частичное. Ещё не проверено:');
  report.untested.forEach((gap) => console.log(`- ${gap}`));
  if (!ok) console.error(output, report.stderr, report.error || '');
  if (reportPath) {
    fs.writeFileSync(path.resolve(reportPath), JSON.stringify(report, null, 2));
    console.log(`Отчёт: ${path.resolve(reportPath)}`);
  }
  process.exitCode = ok ? 0 : 1;
}
main().catch((error) => { console.error(error.message); process.exitCode = 1; });
