function statusToDb(status) {
  switch ((status || '').toLowerCase()) {
    case 'approved':
    case 'active':
      return 'ACTIVE';
    case 'inactive':
    case 'cancelled':
      return 'INACTIVE';
    case 'draft':
      return 'DRAFT';
    default:
      return 'PENDING';
  }
}

function statusToFrontend(status) {
  switch ((status || '').toUpperCase()) {
    case 'ACTIVE':
    case 'APPROVED':
      return 'approved';
    case 'INACTIVE':
    case 'CANCELLED':
      return 'inactive';
    case 'DRAFT':
      return 'draft';
    default:
      return 'pending';
  }
}

module.exports = { statusToDb, statusToFrontend };