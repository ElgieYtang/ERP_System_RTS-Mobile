const db = require('../config/db');
const { TABLES } = require('../config/schema');
const { nextDocumentNumber } = require('../services/documentNumber');
const tp = require('../services/transactionPresenter');
const { loadQuotation, loadPurchaseOrder } = require('../services/presentedRecords');

exports.index = async (req, res) => {
  try {
    const [quotations] = await db.query(`SELECT * FROM ${TABLES.QUOTATION_MAIN} ORDER BY id DESC`);
    const [details] = await db.query(`SELECT * FROM ${TABLES.QUOTATION_DETAILS}`);

    const mapped = quotations.map((q) =>
      tp.quotation(q, details.filter((d) => d.quotation_id === q.id))
    );

    return res.json({ data: mapped });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.store = async (req, res) => {
  const { customerId, date, items } = req.body;
  if (!customerId || !Array.isArray(items) || items.length === 0) {
    return res.status(422).json({ message: 'Customer and items are required.' });
  }

  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [[customer]] = await conn.query('SELECT * FROM setup_customer WHERE id = ?', [customerId]);
    const [[latestRow]] = await conn.query(
      `SELECT quotation_no FROM ${TABLES.QUOTATION_MAIN} ORDER BY id DESC LIMIT 1`
    );
    const quotationNo = nextDocumentNumber('QTN-', latestRow?.quotation_no);

    let total = 0;
    const lines = [];
    for (const item of items) {
      const [[setupItem]] = await conn.query('SELECT * FROM setup_items WHERE id = ?', [item.productId]);
      const qty = parseFloat(item.quantity);
      const price = parseFloat(item.unitPrice);
      const amount = Math.round(qty * price * 100) / 100;
      total += amount;
      lines.push({ itemId: setupItem.id, itemName: setupItem.item_name, qty, price, amount });
    }

    const [result] = await conn.query(
      `INSERT INTO ${TABLES.QUOTATION_MAIN} 
      (customer_id, customer_name, quotation_no, quotation_date, quotation_total, prepared_by, status) 
      VALUES (?, ?, ?, ?, ?, ?, 'PENDING')`,
      [customer.id, customer.name, quotationNo, date || new Date().toISOString().split('T')[0], total, req.authUser?.id || 0]
    );

    const qtnId = result.insertId;
    for (const line of lines) {
      await conn.query(
        `INSERT INTO ${TABLES.QUOTATION_DETAILS} (quotation_id, item_id, item_name, qty, price, amount) VALUES (?, ?, ?, ?, ?, ?)`,
        [qtnId, line.itemId, line.itemName, line.qty, line.price, line.amount]
      );
    }

    await conn.commit();
    return res.status(201).json({
      message: 'Quotation created successfully.',
      data: { id: quotationNo, dbId: String(qtnId), total, status: 'pending' },
    });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: err.message });
  } finally {
    conn.release();
  }
};

exports.update = async (req, res) => {
  const { id } = req.params;
  const { status, date } = req.body;

  try {
    await db.query(
      `UPDATE ${TABLES.QUOTATION_MAIN} SET status = COALESCE(?, status), quotation_date = COALESCE(?, quotation_date) WHERE id = ? OR quotation_no = ?`,
      [status ? status.toUpperCase() : null, date || null, id, id]
    );
    const data = await loadQuotation(id);
    return res.json({ message: 'Quotation updated successfully.', data });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.cancel = async (req, res) => {
  const { id } = req.params;
  try {
    await db.query(
      `UPDATE ${TABLES.QUOTATION_MAIN} SET status = "CANCELLED" WHERE id = ? OR quotation_no = ?`,
      [id, id]
    );
    const data = await loadQuotation(id);
    return res.json({ message: 'Quotation cancelled successfully.', data });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.convertToPurchaseOrder = async (req, res) => {
  const { id } = req.params;
  const { supplierId } = req.body;

  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [[qtn]] = await conn.query(
      `SELECT * FROM ${TABLES.QUOTATION_MAIN} WHERE id = ? OR quotation_no = ?`,
      [id, id]
    );
    if (!qtn) return res.status(404).json({ message: 'Quotation not found.' });

    const [[supplier]] = await conn.query('SELECT * FROM setup_supplier WHERE id = ?', [supplierId]);
    const [[latestPo]] = await conn.query(`SELECT po_no FROM ${TABLES.PO_MAIN} ORDER BY id DESC LIMIT 1`);
    const poNo = nextDocumentNumber('PO-', latestPo?.po_no);

    const [poResult] = await conn.query(
      `INSERT INTO ${TABLES.PO_MAIN} (quotation_id, supplier_id, supplier_name, po_no, po_date, po_total, prepared_by, status) 
       VALUES (?, ?, ?, ?, NOW(), ?, ?, 'APPROVED')`,
      [qtn.id, supplier.id, supplier.name, poNo, qtn.quotation_total, req.authUser?.id || 0]
    );

    const poId = poResult.insertId;
    const [lines] = await conn.query(
      `SELECT * FROM ${TABLES.QUOTATION_DETAILS} WHERE quotation_id = ?`,
      [qtn.id]
    );

    for (const line of lines) {
      await conn.query(
        `INSERT INTO ${TABLES.PO_DETAILS} (po_id, item_id, item_name, qty, price, amount) VALUES (?, ?, ?, ?, ?, ?)`,
        [poId, line.item_id, line.item_name, line.qty, line.price, line.amount]
      );
    }

    await conn.query(
      'INSERT INTO supplier_ledger (supplier_id, po_id, debit, credit) VALUES (?, ?, ?, 0)',
      [supplier.id, poId, qtn.quotation_total]
    );

    await conn.commit();
    const data = await loadPurchaseOrder(poId);
    return res.status(201).json({
      message: 'Purchase Order created successfully.',
      data,
    });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: err.message });
  } finally {
    conn.release();
  }
};
