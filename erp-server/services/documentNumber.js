// Mirrors DocumentNumber::next($prefix, $latest)
function nextDocumentNumber(prefix, latest) {
  if (!latest) return `${prefix}00001`;
  const numPart = latest.replace(prefix, '');
  const parsed = parseInt(numPart, 10);
  if (isNaN(parsed)) return `${prefix}00001`;
  return `${prefix}${String(parsed + 1).padStart(5, '0')}`;
}

module.exports = { nextDocumentNumber };