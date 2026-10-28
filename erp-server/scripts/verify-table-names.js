/**
 * Fails if controllers/middleware use deprecated Laravel-wrong table names.
 * Run: npm run verify-tables
 */
const fs = require('fs');
const path = require('path');
const { LEGACY_TABLE_NAMES } = require('../config/schema');

const roots = [
  path.join(__dirname, '..', 'controllers'),
  path.join(__dirname, '..', 'middleware'),
];

const offenders = [];

for (const root of roots) {
  for (const file of fs.readdirSync(root)) {
    if (!file.endsWith('.js')) continue;
    const full = path.join(root, file);
    const text = fs.readFileSync(full, 'utf8');
    for (const legacy of LEGACY_TABLE_NAMES) {
      const re = new RegExp(`\\b${legacy}\\b`, 'g');
      if (re.test(text)) {
        offenders.push(`${path.relative(path.join(__dirname, '..'), full)} uses legacy table name "${legacy}"`);
      }
    }
  }
}

if (offenders.length > 0) {
  console.error('Table name verification failed:\n' + offenders.join('\n'));
  process.exit(1);
}

console.log('Table name verification OK (no legacy names in controllers/middleware).');
