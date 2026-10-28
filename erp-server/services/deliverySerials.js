function decode(raw) {
  if (raw == null || String(raw).trim() === '') return [];
  const trimmed = String(raw).trim();
  if (trimmed.startsWith('[')) {
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        return parsed.map((v) => String(v).trim()).filter(Boolean);
      }
    } catch {
      // fall through
    }
  }
  return String(raw)
    .split(',')
    .map((p) => p.trim())
    .filter(Boolean);
}

function formatForPrint(raw) {
  return decode(raw).join(', ');
}

module.exports = { decode, formatForPrint };
