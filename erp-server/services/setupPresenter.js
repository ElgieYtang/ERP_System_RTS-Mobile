/** Matches Laravel `SetupPresenter` — camelCase fields expected by the Flutter app. */
const { statusLabel } = require('./inventoryStock');

/** Same as Laravel `SetupStatus::toFrontend`. */
function setupStatusToFrontend(status) {
  return String(status || '').toUpperCase() === 'INACTIVE' ? 'Inactive' : 'Active';
}

function customer(row) {
  return {
    id: String(row.id),
    code: `CUS-${String(row.id).padStart(3, '0')}`,
    name: row.name,
    address: row.address,
    tin: row.tin_no,
    tinNo: row.tin_no,
    terms: row.terms != null ? String(row.terms) : '',
    termsType: row.terms_type || 'IN DAYS',
    status: setupStatusToFrontend(row.status),
  };
}

function supplier(row) {
  return {
    id: String(row.id),
    code: `SUP-${String(row.id).padStart(3, '0')}`,
    name: row.name,
    address: row.address,
    tinNo: row.tin_no,
    contact: row.contact_person,
    contactPerson: row.contact_person,
    phone: row.contact_person_no,
    status: setupStatusToFrontend(row.status),
  };
}

function item(row, stockByItemId) {
  const stock = stockByItemId?.get(row.id) ?? 0;
  return {
    id: String(row.id),
    code: `ITM-${String(row.id).padStart(4, '0')}`,
    brandId: String(row.brand_id ?? ''),
    brand: row.brand_name ?? '',
    modelId: String(row.model_id ?? ''),
    model: row.model_name ?? '',
    name: row.item_name,
    barcode: row.barcode ?? '',
    unitId: String(row.unit_measure_id ?? ''),
    unit: row.unit_name ?? '',
    stock,
    stockStatus: statusLabel(stock),
    status: setupStatusToFrontend(row.status),
  };
}

function present(resource, row, stockByItemId = null) {
  switch (resource) {
    case 'customers':
      return customer(row);
    case 'suppliers':
      return supplier(row);
    case 'items':
      return item(row, stockByItemId);
    default:
      return row;
  }
}

function collection(resource, rows, stockByItemId = null) {
  return rows.map((row) => present(resource, row, stockByItemId));
}

module.exports = {
  present,
  collection,
  customer,
  supplier,
  item,
  setupStatusToFrontend,
};
