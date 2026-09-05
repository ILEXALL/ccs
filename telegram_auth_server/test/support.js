const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');

// In-memory application-logic checks only: no SDK, credentials or network.
// This double does not verify Firestore rules or concurrent transaction retries.
function fixture(extra = {}) {
  let nextId = 0;
  const rows = new Map(Object.entries({
    'app_config/xp': { levels_enabled: true, xp_awards_enabled: true,
      enabledUserIds: ['tester'], weeklyLimit: 3000, timezone: 'Europe/Riga' },
    'users/tester': { name: 'Tester' }, ...extra,
  }));
  const snapshot = (key) => ({ id: key.split('/')[1], exists: rows.has(key),
    data: () => structuredClone(rows.get(key)) });
  const db = {
    collection(name) {
      const filters = [];
      let order;
      let count = Infinity;
      let afterId;
      const query = {
        doc(id = `generated-${++nextId}`) {
          const key = `${name}/${id}`;
          return { key, get: async () => snapshot(key),
            collection: (child) => db.collection(`${key}/${child}`) };
        },
        where(field, operator, value) {
          assert.equal(operator, '=='); filters.push([field, value]); return query;
        },
        orderBy(field, direction) { order = [field, direction]; return query; },
        limit(value) { count = value; return query; },
        startAfter(doc) { afterId = doc.id; return query; },
        async get() {
          const entries = [...rows].filter(([key, value]) => key.startsWith(`${name}/`) &&
            filters.every(([field, expected]) => value[field] === expected));
          entries.sort(([a, av], [b, bv]) => order
            ? ((av[order[0]] - bv[order[0]]) * (order[1] === 'desc' ? -1 : 1) || a.localeCompare(b))
            : a.localeCompare(b));
          const start = afterId === undefined ? 0
            : entries.findIndex(([key]) => key === `${name}/${afterId}`) + 1;
          return { docs: entries.slice(start, start + count).map(([key]) => snapshot(key)) };
        },
      };
      return query;
    },
    async runTransaction(callback) {
      const writes = [];
      const result = await callback({
        get: async (ref) => snapshot(ref.key),
        update(ref, data) {
          assert.equal(rows.has(ref.key), true);
          writes.push([ref.key, { ...rows.get(ref.key), ...data }]);
        },
        delete(ref) { writes.push([ref.key, undefined]); },
        create(ref, data) { assert.equal(rows.has(ref.key), false); writes.push([ref.key, data]); },
        set(ref, data, options) {
          writes.push([ref.key, options?.merge ? { ...rows.get(ref.key), ...data } : data]);
        },
      });
      for (const [key, value] of writes) {
        if (value === undefined) rows.delete(key);
        else rows.set(key, structuredClone(value));
      }
      return result;
    },
  };
  const firebase = { db, admin: {
    firestore: { FieldValue: { serverTimestamp: () => 'SERVER_TIMESTAMP' } },
    auth: () => ({ verifyIdToken: async (token) => ({ uid: token }) }),
  } };
  const modules = new Map();
  function load(relative) {
    const filename = path.resolve(__dirname, relative);
    if (modules.has(filename)) return modules.get(filename).exports;
    const localRequire = createRequire(filename);
    const module = { exports: {} };
    modules.set(filename, module);
    vm.runInNewContext(fs.readFileSync(filename, 'utf8'), {
      require: (id) => {
        if (id.endsWith('/firebase-admin')) return firebase;
        if (id.startsWith('.')) return load(localRequire.resolve(id));
        if (id === 'node:crypto') return localRequire(id);
        throw new Error(`Dependency not allowed in offline tests: ${id}`);
      },
      module, exports: module.exports, Date, console,
    }, { filename });
    return module.exports;
  }
  return { rows, load, awards: load('../lib/xp/xp-firestore.js') };
}
module.exports = { fixture };
