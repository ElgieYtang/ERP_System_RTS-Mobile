const db = require('../config/db');
const { TABLES } = require('../config/schema');

/**
 * Build outslip detail rows from a completed receiving (prices from PO lines).
 * Matches Laravel OutslipController::resolveLines.
 */
async function resolveLinesFromReceiving(receivingId, conn = db) {
  const query = conn.query ? conn.query.bind(conn) : db.query.bind(db);

  const [[rcv]] = await query(`SELECT * FROM ${TABLES.RECEIVING_MAIN} WHERE id = ?`, [receivingId]);
  if (!rcv) {
    throw new Error('Receiving not found.');
  }
  if (String(rcv.status || '').toUpperCase() !== 'COMPLETED') {
    throw new Error('Only completed receivings can create an outslip.');
  }

  const [rcvDetails] = await query(
    `SELECT * FROM ${TABLES.RECEIVING_DETAILS} WHERE receiving_id = ?`,
    [receivingId]
  );
  const [[po]] = await query(`SELECT * FROM ${TABLES.PO_MAIN} WHERE id = ?`, [rcv.po_id]);
  const [poDetails] = po
    ? await query(`SELECT * FROM ${TABLES.PO_DETAILS} WHERE po_id = ?`, [po.id])
    : [[]];

  const lines = [];
  for (const line of rcvDetails) {
    const poLine = poDetails.find((p) => p.item_id === line.item_id);
    const [[item]] = await query('SELECT item_name FROM setup_items WHERE id = ?', [line.item_id]);
    const qty = parseFloat(line.qty);
    const price = parseFloat(poLine?.price ?? 0);
    const amount = Math.round(qty * price * 100) / 100;

    lines.push({
      item_id: line.item_id,
      item_name: poLine?.item_name ?? item?.item_name ?? `Item ${line.item_id}`,
      qty,
      price,
      amount,
    });
  }

  return lines;
}

/** Fill missing names/prices on saved outslip_details (legacy rows). */
async function enrichOutslipDetailLines(outslipRow, details) {
  if (!details?.length || !outslipRow?.receiving_id) {
    return details;
  }

  const needsEnrich = details.some((d) => {
    const price = parseFloat(d.price || 0);
    const name = String(d.item_name || '');
    return price <= 0 || name.startsWith('Item #');
  });

  if (!needsEnrich) {
    return details;
  }

  let resolved;
  try {
    resolved = await resolveLinesFromReceiving(outslipRow.receiving_id);
  } catch {
    return details;
  }

  const byItemId = new Map(resolved.map((l) => [l.item_id, l]));
  const enriched = details.map((d) => {
    const src = byItemId.get(d.item_id);
    if (!src) return d;
    const qty = parseFloat(d.qty);
    const price = parseFloat(src.price);
    return {
      ...d,
      item_name: src.item_name,
      price,
      amount: Math.round(qty * price * 100) / 100,
    };
  });

  for (const row of enriched) {
    if (!row.id) continue;
    await db.query(
      `UPDATE ${TABLES.OUTSLIP_DETAILS} SET item_name = ?, price = ?, amount = ? WHERE id = ?`,
      [row.item_name, row.price, row.amount, row.id]
    );
  }

  return enriched;
}

/** Insert delivery_details from outslip when missing (e.g. wrong FK column was used). */
async function backfillDeliveryDetailsFromOutslip(drRow) {
  if (!drRow?.outslip_id) return [];

  const [[os]] = await db.query(`SELECT * FROM ${TABLES.OUTSLIP_MAIN} WHERE id = ?`, [drRow.outslip_id]);
  if (!os) return [];

  const [osLinesRaw] = await db.query(
    `SELECT * FROM ${TABLES.OUTSLIP_DETAILS} WHERE outslip_id = ?`,
    [os.id]
  );
  const osLines = await enrichOutslipDetailLines(os, osLinesRaw);
  if (!osLines.length) return [];

  let total = 0;
  for (const line of osLines) {
    const price = parseFloat(line.price || 0);
    const amount = Math.round(parseFloat(line.qty) * price * 100) / 100;
    total += amount;
    await db.query(
      `INSERT INTO ${TABLES.DELIVERY_DETAILS} (delivery_id, item_id, item_name, qty, price, amount)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [drRow.id, line.item_id, line.item_name, line.qty, price, amount]
    );
  }

  if (total > 0) {
    await db.query(`UPDATE ${TABLES.DELIVERY_MAIN} SET dr_total = ? WHERE id = ?`, [total, drRow.id]);
    drRow.dr_total = total;
  }

  const [inserted] = await db.query(
    `SELECT * FROM ${TABLES.DELIVERY_DETAILS} WHERE delivery_id = ?`,
    [drRow.id]
  );
  return inserted;
}

/** Backfill delivery line prices from the linked outslip (legacy DR rows). */
async function enrichDeliveryDetailLines(drRow, details) {
  if (!details?.length && drRow?.outslip_id) {
    details = await backfillDeliveryDetailsFromOutslip(drRow);
  }
  if (!details?.length) {
    return details ?? [];
  }

  const needsEnrich = details.some((d) => parseFloat(d.price || 0) <= 0);
  if (!needsEnrich) {
    return details;
  }

  const [[os]] = await db.query(`SELECT * FROM ${TABLES.OUTSLIP_MAIN} WHERE id = ?`, [drRow.outslip_id]);
  if (!os) return details;

  const [osLinesRaw] = await db.query(
    `SELECT * FROM ${TABLES.OUTSLIP_DETAILS} WHERE outslip_id = ?`,
    [os.id]
  );
  const osLines = await enrichOutslipDetailLines(os, osLinesRaw);
  const byItemId = new Map(osLines.map((l) => [l.item_id, l]));

  const enriched = details.map((d) => {
    const src = byItemId.get(d.item_id);
    if (!src) return d;
    const qty = parseFloat(d.qty);
    const price = parseFloat(src.price || 0);
    return {
      ...d,
      item_name: src.item_name || d.item_name,
      price,
      amount: Math.round(qty * price * 100) / 100,
    };
  });

  let total = 0;
  for (const row of enriched) {
    if (!row.id) continue;
    total += parseFloat(row.amount || 0);
    await db.query(
      `UPDATE ${TABLES.DELIVERY_DETAILS} SET item_name = ?, price = ?, amount = ? WHERE id = ?`,
      [row.item_name, row.price, row.amount, row.id]
    );
  }

  if (total > 0 && parseFloat(drRow.dr_total || 0) <= 0) {
    await db.query(`UPDATE ${TABLES.DELIVERY_MAIN} SET dr_total = ? WHERE id = ?`, [total, drRow.id]);
    drRow.dr_total = total;
  }

  return enriched;
}

module.exports = {
  resolveLinesFromReceiving,
  enrichOutslipDetailLines,
  enrichDeliveryDetailLines,
};
