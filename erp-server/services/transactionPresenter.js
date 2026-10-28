const moment = require('moment-timezone');
const { decode: decodeSerials, formatForPrint } = require('./deliverySerials');

function formatDate(d) {
  if (!d) return '';
  return moment(d).format('YYYY-MM-DD');
}

function formatDisplayDate(d) {
  if (!d) return '';
  return moment(d).format('MMMM D, YYYY');
}

function statusToFrontend(status) {
  const s = String(status || '').toUpperCase();
  if (s === 'ACTIVE' || s === 'APPROVED' || s === 'COMPLETED') return 'approved';
  if (s === 'INACTIVE' || s === 'CANCELLED') return 'cancelled';
  if (s === 'REJECTED') return 'rejected';
  if (s === 'DRAFT') return 'draft';
  return 'pending';
}

function poStatusToFrontend(status) {
  const s = String(status || '').toUpperCase();
  if (s === 'ACTIVE' || s === 'APPROVED') return 'approved';
  if (s === 'INACTIVE' || s === 'CANCELLED') return 'cancelled';
  if (s === 'COMPLETED' || s === 'FULLY_RECEIVED') return 'fully_received';
  if (s === 'PARTIAL') return 'partial';
  return 'pending';
}

function outslipStatusToFrontend(status) {
  const s = String(status || '').toUpperCase();
  if (s === 'DRAFT') return 'draft';
  if (s === 'APPROVED') return 'approved';
  if (s === 'FOR_DISPATCH' || s === 'RELEASED') return 'for_dispatch';
  if (s === 'CANCELLED' || s === 'INACTIVE') return 'cancelled';
  return 'pending';
}

function deliveryStatusToFrontend(status) {
  const s = String(status || '').toUpperCase();
  if (s === 'OUT FOR DELIVERY' || s === 'OUT_FOR_DELIVERY') return 'out_for_delivery';
  if (s === 'DELIVERED') return 'delivered';
  if (s === 'INACTIVE' || s === 'CANCELLED') return 'cancelled';
  return 'active';
}

function mapLineItems(lines, mapper) {
  return lines.map(mapper);
}

function quotation(q, details) {
  const items = mapLineItems(details, (line) => ({
    productId: String(line.item_id),
    productName: line.item_name,
    quantity: parseFloat(line.qty),
    unitPrice: parseFloat(line.price),
    amount: parseFloat(line.amount),
  }));

  return {
    id: q.quotation_no || `QTN-${String(q.id).padStart(5, '0')}`,
    dbId: String(q.id),
    customerId: String(q.customer_id ?? ''),
    customerName: q.customer_name,
    date: formatDate(q.quotation_date),
    displayDate: formatDisplayDate(q.quotation_date),
    total: parseFloat(q.quotation_total || 0),
    status: statusToFrontend(q.status),
    preparedBy: String(q.prepared_by ?? ''),
    approvedBy: String(q.approved_by ?? ''),
    items,
  };
}

function purchaseOrder(po, details, quotationRow) {
  const quotationNo = quotationRow?.quotation_no;
  return {
    id: po.po_no || `PO-${String(po.id).padStart(5, '0')}`,
    dbId: String(po.id),
    referenceQuotationId: quotationNo ?? (po.quotation_id ? String(po.quotation_id) : null),
    referenceQuotationNo: quotationNo ?? null,
    supplierId: String(po.supplier_id ?? ''),
    supplierName: po.supplier_name,
    date: formatDate(po.po_date),
    displayDate: formatDisplayDate(po.po_date),
    total: parseFloat(po.po_total || 0),
    status: poStatusToFrontend(po.status),
    preparedBy: String(po.prepared_by ?? ''),
    approvedBy: String(po.approved_by ?? ''),
    items: mapLineItems(details, (line) => ({
      productId: String(line.item_id),
      productName: line.item_name,
      quantity: parseFloat(line.qty),
      unitPrice: parseFloat(line.price),
      amount: parseFloat(line.amount),
      unit: 'UNITS',
    })),
  };
}

function receiving(rcv, details, po, poDetails, setupItemsById) {
  const isCompleted = String(rcv.status || '').toUpperCase() === 'COMPLETED';
  const poLines = poDetails || [];

  const items = mapLineItems(details, (line) => {
    const poLine = poLines.find((p) => p.item_id === line.item_id);
    const setup = setupItemsById?.get(line.item_id);
    const itemName = poLine?.item_name || setup?.item_name || `Item ${line.item_id}`;
    const ordered = parseFloat(poLine?.qty ?? line.qty);

    return {
      productId: String(line.item_id),
      productName: itemName,
      quantity: parseFloat(line.qty),
      unitPrice: parseFloat(poLine?.price ?? 0),
      ordered,
      received: isCompleted ? ordered : 0,
      remaining: isCompleted ? 0 : ordered,
    };
  });

  return {
    id: rcv.receiving_no || `RCV-${String(rcv.id).padStart(5, '0')}`,
    dbId: String(rcv.id),
    purchaseOrderId: po?.po_no ?? String(rcv.po_id),
    purchaseOrderDbId: String(rcv.po_id),
    supplierId: String(po?.supplier_id ?? ''),
    supplierName: po?.supplier_name ?? '',
    customerId: rcv.customer_id ? String(rcv.customer_id) : '',
    customerName: rcv.customer_name ?? '',
    branchId: String(rcv.branch_id ?? ''),
    date: formatDate(rcv.receiving_date),
    displayDate: formatDisplayDate(rcv.receiving_date),
    remarks: rcv.remarks,
    status: isCompleted ? 'completed' : 'pending',
    items,
  };
}

function outslip(os, details, gatePass, receivingRow) {
  const receivingNo = receivingRow?.receiving_no;
  const items = mapLineItems(details, (line) => {
    const qty = parseFloat(line.qty);
    const unitPrice = parseFloat(line.price || 0);
    const amount =
      parseFloat(line.amount || 0) || Math.round(qty * unitPrice * 100) / 100;
    return {
      productId: String(line.item_id),
      productName: line.item_name,
      quantity: qty,
      unitPrice,
      amount,
      unit: 'PC/S',
    };
  });
  const total =
    items.reduce((sum, line) => sum + line.amount, 0) ||
    parseFloat(os.outslip_total || os.total || 0);
  return {
    id: os.outslip_no || `OS-${String(os.id).padStart(5, '0')}`,
    dbId: String(os.id),
    customerId: String(os.customer_id ?? ''),
    customerName: os.customer_name,
    receivingId: receivingNo ?? (os.receiving_id ? String(os.receiving_id) : null),
    referenceReceivingDbId: os.receiving_id ? String(os.receiving_id) : null,
    referenceReceivingNo: receivingNo ?? null,
    branchId: String(os.branch_id ?? ''),
    date: formatDate(os.outslip_date),
    displayDate: formatDisplayDate(os.outslip_date),
    status: outslipStatusToFrontend(os.status),
    total,
    gatePass: gatePass ? gatePassRow(gatePass) : null,
    items,
  };
}

function gatePassRow(gp) {
  return {
    id: String(gp.id),
    gatePassNo: gp.gate_pass_no,
    outslipId: String(gp.outslip_id),
    vehicleNo: gp.vehicle_no ?? '',
    driverName: gp.driver_name ?? '',
    plateNo: gp.plate_no ?? '',
    destination: gp.destination ?? '',
    remarks: gp.remarks ?? '',
    status: String(gp.status || 'PENDING').toLowerCase(),
    exitAt: gp.exit_at ? moment(gp.exit_at).format('YYYY-MM-DD HH:mm:ss') : null,
    displayExitAt: gp.exit_at ? moment(gp.exit_at).format('MMMM D, YYYY h:mm A') : null,
    displayTimeOut: gp.exit_at ? moment(gp.exit_at).format('hh:mm A') : null,
  };
}

function deliveryReceipt(dr, details, outslipRow, setupItemsById) {
  const items = mapLineItems(details, (line) => {
    const setup = setupItemsById?.get(line.item_id);
    const serials = decodeSerials(line.serial_no);
    const qty = parseFloat(line.qty);
    const unitPrice = parseFloat(line.price || 0);
    const amount =
      parseFloat(line.amount || 0) || Math.round(qty * unitPrice * 100) / 100;
    return {
      productId: String(line.item_id),
      productName: line.item_name,
      barcode: setup?.barcode ?? '',
      quantity: qty,
      unitPrice,
      amount,
      serialNumbers: serials,
      brandSerial: formatForPrint(line.serial_no),
    };
  });
  const lineTotal = items.reduce((sum, line) => sum + line.amount, 0);
  const total = parseFloat(dr.dr_total || 0) || lineTotal;
  return {
    id: dr.dr_no || `DR-${String(dr.id).padStart(5, '0')}`,
    dbId: String(dr.id),
    customerId: String(dr.customer_id ?? ''),
    customerName: dr.customer_name,
    referenceOutslipId: outslipRow?.outslip_no ?? (dr.outslip_id ? String(dr.outslip_id) : null),
    referenceOutslipDbId: String(dr.outslip_id),
    date: formatDate(dr.dr_date),
    displayDate: formatDisplayDate(dr.dr_date),
    total,
    status: deliveryStatusToFrontend(dr.status),
    items,
  };
}

function billing(row, payments, delivery) {
  const total = parseFloat(row.billing_total || 0);
  const paid = parseFloat(row.paid_amount || 0);
  const balanceDue = Math.max(0, total - paid);
  let paymentStatus = 'unpaid';
  if (balanceDue <= 0 && total > 0) paymentStatus = 'paid';
  else if (paid > 0) paymentStatus = 'partially_paid';

  return {
    id: row.billing_no || `BS-${String(row.id).padStart(5, '0')}`,
    dbId: String(row.id),
    customerId: String(row.customer_id ?? ''),
    customerName: row.customer_name,
    referenceDrId: delivery?.dr_no ?? (row.delivery_id ? String(row.delivery_id) : null),
    referenceDrDbId: String(row.delivery_id),
    billingDate: formatDate(row.billing_date),
    displayDate: formatDisplayDate(row.billing_date),
    amount: total,
    paidAmount: paid,
    balanceDue,
    paymentStatus,
    status: String(row.status || '').toUpperCase() === 'INACTIVE' ? 'inactive' : 'active',
    payments: payments.map((p) => ({
      id: p.payment_no || `PAY-${String(p.id).padStart(5, '0')}`,
      date: formatDate(p.payment_date),
      amount: parseFloat(p.amount),
      reference: p.reference,
      remarks: p.remarks,
    })),
  };
}

module.exports = {
  quotation,
  purchaseOrder,
  receiving,
  outslip,
  gatePassRow,
  deliveryReceipt,
  billing,
  formatDisplayDate,
  formatDate,
};
