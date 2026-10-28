const db = require('../config/db');
const { TABLES } = require('../config/schema');

exports.customerLedger = async (req, res) => {
  return exports.soa(req, res);
};

exports.soa = async (req, res) => {
  const { customerId, from, to } = req.query;
  try {
    const [[customer]] = await db.query('SELECT * FROM setup_customer WHERE id = ?', [customerId]);
    if (!customer) return res.status(404).json({ message: 'Customer not found.' });

    let billQuery = `SELECT * FROM ${TABLES.BILLING} WHERE customer_id = ?`;
    const params = [customerId];
    if (from) { billQuery += ' AND billing_date >= ?'; params.push(from); }
    if (to) { billQuery += ' AND billing_date <= ?'; params.push(to); }
    const [bills] = await db.query(billQuery, params);

    const billIds = bills.map((b) => b.id);
    let payments = [];
    if (billIds.length > 0) {
      const [payRows] = await db.query(
        `SELECT * FROM billing_payments WHERE billing_id IN (?)`,
        [billIds]
      );
      payments = payRows;
    }

    const rows = [];
    let totalDebit = 0;
    let totalCredit = 0;

    for (const b of bills) {
      const amt = parseFloat(b.billing_total || 0);
      totalDebit += amt;
      rows.push({
        date: b.billing_date,
        displayDate: b.billing_date,
        ref: b.billing_no,
        description: `Billing statement ${b.billing_no}`,
        debit: amt,
        credit: 0,
      });
    }

    for (const p of payments) {
      const amt = parseFloat(p.amount || 0);
      totalCredit += amt;
      rows.push({
        date: p.payment_date,
        displayDate: p.payment_date,
        ref: p.payment_no || p.reference,
        description: p.remarks || 'Customer Payment',
        debit: 0,
        credit: amt,
      });
    }

    return res.json({
      data: {
        customerId: String(customer.id),
        customerName: customer.name,
        customerAddress: customer.address,
        rows,
        totals: {
          totalDebit,
          totalCredit,
          outstanding: totalDebit - totalCredit,
        },
      },
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.supplierLedger = async (req, res) => {
  const { supplierId, from, to } = req.query;
  try {
    const [[supplier]] = await db.query('SELECT * FROM setup_supplier WHERE id = ?', [supplierId]);
    if (!supplier) return res.status(404).json({ message: 'Supplier not found.' });

    let poQuery = `SELECT * FROM ${TABLES.PO_MAIN} WHERE supplier_id = ?`;
    const params = [supplierId];
    if (from) { poQuery += ' AND po_date >= ?'; params.push(from); }
    if (to) { poQuery += ' AND po_date <= ?'; params.push(to); }
    const [pos] = await db.query(poQuery, params);

    const [ledgerCredits] = await db.query(
      'SELECT * FROM supplier_ledger WHERE supplier_id = ? AND credit > 0',
      [supplierId]
    );

    const rows = [];
    let totalDebit = 0;
    let totalCredit = 0;

    for (const po of pos) {
      const amt = parseFloat(po.po_total || 0);
      totalDebit += amt;
      rows.push({
        date: po.po_date,
        ref: po.po_no,
        description: 'Purchase Order',
        debit: amt,
        credit: 0,
      });
    }

    for (const cred of ledgerCredits) {
      const amt = parseFloat(cred.credit || 0);
      totalCredit += amt;
      rows.push({
        date: cred.created_at,
        ref: `PAY-${cred.id}`,
        description: 'Supplier payment',
        debit: 0,
        credit: amt,
      });
    }

    return res.json({
      data: {
        supplierId: String(supplier.id),
        supplierName: supplier.name,
        rows,
        totals: {
          totalDebit,
          totalCredit,
          outstanding: totalDebit - totalCredit,
        },
      },
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.inventory = async (req, res) => {
  const { branchId, q } = req.query;
  try {
    let stockQuery = `
      SELECT item_id, SUM(\`in\`) as qty_in, SUM(\`out\`) as qty_out
      FROM ${TABLES.INVENTORY}
      WHERE item_id > 0
    `;
    const params = [];
    if (branchId) {
      stockQuery += ' AND branch_id = ?';
      params.push(branchId);
    }
    stockQuery += ' GROUP BY item_id';

    const [stockRows] = await db.query(stockQuery, params);
    const itemIds = stockRows.map((r) => r.item_id);

    let items = [];
    if (itemIds.length > 0) {
      const [itemRecords] = await db.query(
        `SELECT i.*, b.name AS brand, u.name AS unit
         FROM setup_items i
         LEFT JOIN setup_brand b ON i.brand_id = b.id
         LEFT JOIN setup_unit_measure u ON i.unit_measure_id = u.id
         WHERE i.id IN (?)`,
        [itemIds]
      );
      items = itemRecords;
    }

    const itemMap = new Map(items.map((i) => [i.id, i]));

    let stock = stockRows.map((r) => {
      const item = itemMap.get(r.item_id);
      const qty = parseFloat(r.qty_in || 0) - parseFloat(r.qty_out || 0);
      return {
        itemId: String(r.item_id),
        itemCode: `ITM-${String(r.item_id).padStart(5, '0')}`,
        itemName: item?.item_name || `Item ${r.item_id}`,
        brand: item?.brand || '',
        unit: item?.unit || 'UNITS',
        quantity: qty,
        status: qty <= 0 ? 'Out of Stock' : qty <= 5 ? 'Low Stock' : 'In Stock',
      };
    });

    if (q) {
      const query = q.toLowerCase();
      stock = stock.filter(
        (s) =>
          s.itemName.toLowerCase().includes(query) ||
          s.itemCode.toLowerCase().includes(query) ||
          s.brand.toLowerCase().includes(query)
      );
    }

    return res.json({
      data: {
        summary: {
          itemCount: stock.length,
          totalQuantity: stock.reduce((sum, s) => sum + s.quantity, 0),
          lowStock: stock.filter((s) => s.status === 'Low Stock').length,
          outOfStock: stock.filter((s) => s.status === 'Out of Stock').length,
        },
        stock,
      },
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};