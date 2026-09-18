const crypto = require('node:crypto');

const VERSION = 'ccs-weekly-v1';
const WEEKS = 104;
const COOLDOWN = 4;
const amounts = [75, 100, 125];
// These are planning definitions, not evidence of completion. No client event
// or mutable profile counter may be used to award these rewards.
const definitions = [
  [0, 'visits', 'visit-two', 'Visit two different spots', 'Посетить два разных спота', 'Apmeklēt divas dažādas vietas', 'verified_visits', 2],
  [0, 'visits', 'visit-new', 'Visit a spot you have not visited before', 'Посетить спот, где ещё не был', 'Apmeklēt vēl neapmeklētu vietu', 'first_visits', 1],
  [0, 'content', 'photo-help', 'Add an accepted photo to another author\'s spot', 'Добавить одобренное фото к чужому споту', 'Pievienot apstiprinātu foto cita autora vietai', 'accepted_photo_contributions', 1],
  [0, 'content', 'spot-detail', 'Publish an approved spot with a description and photo', 'Опубликовать одобренный спот с описанием и фото', 'Publicēt apstiprinātu vietu ar aprakstu un foto', 'new_complete_spots', 1],
  [0, 'community', 'meet-visit', 'Attend a meet hosted by another user', 'Посетить мит другого организатора', 'Apmeklēt cita rīkotu tikšanos', 'verified_meet_visits', 1],
  [0, 'community', 'help-answer', 'Have an answer marked helpful by a topic author', 'Получить отметку полезного ответа от автора темы', 'Saņemt tēmas autora atzīmi par noderīgu atbildi', 'accepted_helpful_answers', 1],
  [0, 'explore', 'two-categories', 'Visit spots in two different categories', 'Посетить споты двух разных категорий', 'Apmeklēt vietas divās dažādās kategorijās', 'visited_categories', 2],
  [0, 'explore', 'weekend-visit', 'Visit a spot on the weekend', 'Посетить спот в выходные', 'Apmeklēt vietu nedēļas nogalē', 'weekend_visits', 1],
  [1, 'visits', 'visit-four', 'Visit four different spots', 'Посетить четыре разных спота', 'Apmeklēt četras dažādas vietas', 'verified_visits', 4],
  [1, 'visits', 'visit-two-days', 'Visit different spots on two days', 'Посетить разные споты в два разных дня', 'Apmeklēt dažādas vietas divās dienās', 'distinct_visit_days', 2],
  [1, 'content', 'photo-two', 'Add accepted photos to two other authors\' spots', 'Добавить одобренные фото к двум чужим спотам', 'Pievienot apstiprinātus foto divām citu autoru vietām', 'accepted_photo_contributions', 2],
  [1, 'content', 'spot-gallery', 'Publish an approved spot with three different photos', 'Опубликовать одобренный спот с тремя разными фото', 'Publicēt apstiprinātu vietu ar trim dažādiem foto', 'new_gallery_spots', 1],
  [1, 'community', 'meet-and-spot', 'Attend a meet and visit a permanent spot', 'Посетить мит и постоянный спот', 'Apmeklēt tikšanos un pastāvīgu vietu', 'meet_and_permanent_visit', 2],
  [1, 'community', 'help-two-authors', 'Help two different topic authors with accepted answers', 'Помочь двум авторам тем: они отметили твои ответы полезными', 'Palīdzēt diviem tēmu autoriem ar atzītām atbildēm', 'helped_topic_authors', 2],
  [1, 'explore', 'new-two', 'Visit two spots you have never visited', 'Посетить два спота, где ещё не был', 'Apmeklēt divas vēl neapmeklētas vietas', 'first_visits', 2],
  [1, 'explore', 'weekday-weekend', 'Visit different spots on a weekday and on the weekend', 'Посетить разные споты в будний и выходной день', 'Apmeklēt dažādas vietas darbdienā un nedēļas nogalē', 'weekday_and_weekend_visits', 2],
  [2, 'visits', 'visit-seven', 'Visit seven different spots', 'Посетить семь разных спотов', 'Apmeklēt septiņas dažādas vietas', 'verified_visits', 7],
  [2, 'visits', 'visit-three-days', 'Visit different spots on three days', 'Посетить разные споты в три разных дня', 'Apmeklēt dažādas vietas trijās dienās', 'distinct_visit_days', 3],
  [2, 'content', 'photo-three', 'Add accepted photos to three other authors\' spots', 'Добавить одобренные фото к трём чужим спотам', 'Pievienot apstiprinātus foto trim citu autoru vietām', 'accepted_photo_contributions', 3],
  [2, 'content', 'publish-and-visit', 'Publish a complete approved spot and visit two other spots', 'Опубликовать полный одобренный спот и посетить два чужих', 'Publicēt pilnīgu apstiprinātu vietu un apmeklēt divas citas', 'publish_and_two_visits', 3],
  [2, 'community', 'meet-and-new-two', 'Attend a meet and visit two new permanent spots', 'Посетить мит и два новых для себя постоянных спота', 'Apmeklēt tikšanos un divas sev jaunas pastāvīgas vietas', 'meet_and_two_first_visits', 3],
  [2, 'community', 'help-three-authors', 'Help three different topic authors with accepted answers', 'Помочь трём авторам тем: они отметили твои ответы полезными', 'Palīdzēt trim tēmu autoriem ar atzītām atbildēm', 'helped_topic_authors', 3],
  [2, 'explore', 'three-categories', 'Visit spots in three different categories', 'Посетить споты трёх разных категорий', 'Apmeklēt vietas trijās dažādās kategorijās', 'visited_categories', 3],
  [2, 'explore', 'new-three-days', 'Visit a new spot on each of three different days', 'Посетить новый для себя спот в каждый из трёх разных дней', 'Apmeklēt sev jaunu vietu katrā no trim dažādām dienām', 'first_visit_days', 3],
];

function taskCatalog() {
  return definitions.map(([difficulty, family, id, en, ru, lv, metric, target]) => ({
    id, difficulty, family, xp: amounts[difficulty], title: {en, ru, lv}, metric, target,
    // Fail closed until a reviewed server-side evidence adapter is implemented.
    available: false,
  }));
}

function randomScore(seed, value) {
  return crypto.createHash('sha256').update(`${VERSION}|${seed}|${value}`).digest().readUInt32BE(0) / 0x100000000;
}

function generatePlan(seed = VERSION) {
  if (typeof seed !== 'string' || !seed.trim() || seed.length > 128) throw new Error('Invalid plan seed');
  const pools = amounts.map((_, difficulty) => taskCatalog().filter(item => item.difficulty === difficulty));
  const combinations = [];
  for (const a of pools[0]) for (const b of pools[1]) for (const c of pools[2]) {
    if (new Set([a.family, b.family, c.family]).size === 3) combinations.push([a, b, c]);
  }
  const used = new Set();
  const counts = new Map();
  const last = new Map();
  const weeks = [];
  for (let week = 0; week < WEEKS; week++) {
    let best; let bestScore = Infinity;
    for (const tasks of combinations) {
      const signature = tasks.map(task => task.id).join('|');
      if (used.has(signature) || tasks.some(task => week - (last.get(task.id) ?? -COOLDOWN) < COOLDOWN)) continue;
      const score = tasks.reduce((sum, task) => sum + Math.pow((counts.get(task.id) || 0) + 1, 2), 0)
        + randomScore(seed, `${week}|${signature}`);
      if (score < bestScore) { best = tasks; bestScore = score; }
    }
    if (!best) throw new Error(`No valid tasks for week ${week + 1}`);
    used.add(best.map(task => task.id).join('|'));
    for (const task of best) {
      counts.set(task.id, (counts.get(task.id) || 0) + 1);
      last.set(task.id, week);
    }
    weeks.push({week: week + 1, tasks: best.map(task => ({...task})), totalXp: 300});
  }
  return {version: VERSION, seed, weeks};
}

function mondayDate(weekKey) {
  if (typeof weekKey !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(weekKey)) throw new Error('Expected Monday YYYY-MM-DD');
  const date = new Date(`${weekKey}T00:00:00Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== weekKey || date.getUTCDay() !== 1) {
    throw new Error('Expected Monday YYYY-MM-DD');
  }
  return date;
}

function datedPlan(startWeek, seed) {
  const start = mondayDate(startWeek);
  const plan = generatePlan(seed);
  return {...plan, startWeek, timeZone: 'Europe/Riga', weeks: plan.weeks.map(week => ({
    ...week,
    weekKey: new Date(start.getTime() + (week.week - 1) * 7 * 86400000).toISOString().slice(0, 10),
    endWeekKey: new Date(start.getTime() + week.week * 7 * 86400000).toISOString().slice(0, 10),
  }))};
}

// A plan is never silently recycled after its 104th week.
function activeWeek(plan, weekKey) {
  mondayDate(weekKey);
  return plan.weeks.find(week => week.weekKey === weekKey) || null;
}

module.exports = {VERSION, WEEKS, COOLDOWN, taskCatalog, generatePlan, datedPlan, activeWeek};
