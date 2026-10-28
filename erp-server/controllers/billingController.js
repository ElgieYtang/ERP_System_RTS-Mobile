const db = require('../config/db');
const { TABLES, billingPaymentStatus } = require('../config/schema');
const { nextDocumentNumber } = require('../services/documentNumber');
const tp = require('../services/transactionPresenter');
const { loadBilling } = require('../services/presentedRecords');

const { BILLING, DELIVERY_MAIN } = TABLES;

exports.index = async (req, res) => {
  try {
    const [billings] = await db.query(`SELECT * FROM ${BILLING} ORDER BY id DESC`);
    const [payments] = await db.query('SELECT * FROM billing_payments');
    const [deliveries] = await db.query(`SELECT id, dr_no FROM ${DELIVERY_MAIN}`);
    const deliveryById = new Map(deliveries.map((d) => [d.id, d]));

    const mapped = billings.map((b) => {
      const rowPayments = payments.filter((p) => p.billing_id === b.id);
      const delivery = deliveryById.get(b.delivery_id);
      const presented = tp.billing(b, rowPayments, delivery);
      return {
        ...presented,
        paymentStatus: billingPaymentStatus(b),
      };
    });

    return res.json({ data: mapped });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.store = async (req, res) => {
  const { deliveryId } = req.body;
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [[dr]] = await conn.query(`SELECT * FROM ${DELIVERY_MAIN} WHERE id = ?`, [deliveryId]);
    const [[latestBs]] = await conn.query(`SELECT billing_no FROM ${BILLING} ORDER BY id DESC LIMIT 1`);
    const bsNo = nextDocumentNumber('BS-', latestBs?.billing_no);

    const [result] = await conn.query(
      `INSERT INTO ${BILLING} (delivery_id, billing_no, billing_date, customer_id, customer_name, billing_total, paid_amount, status)
       VALUES (?, ?, NOW(), ?, ?, ?, 0, 'ACTIVE')`,
      [dr.id, bsNo, dr.customer_id, dr.customer_name, dr.dr_total || 0]
    );

    const bsId = result.insertId;
    await conn.query(
      'INSERT INTO customer_ledger (customer_id, outslip_id, debit, credit) VALUES (?, ?, ?, 0)',
      [dr.customer_id, dr.outslip_id, dr.dr_total || 0]
    );

    await conn.commit();
    return res.status(201).json({
      message: 'Billing statement created.',
      data: { id: bsNo, dbId: String(bsId), paymentStatus: 'unpaid' },
    });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: err.message });
  } finally {
    conn.release();
  }
};

exports.recordPayment = async (req, res) => {
  const { id } = req.params;
  const { amount, date, reference, remarks } = req.body;
  const paymentAmount = parseFloat(amount);

  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const [[row]] = await conn.query(`SELECT * FROM ${BILLING} WHERE id = ? OR billing_no = ?`, [id, id]);
    const [[latestPay]] = await conn.query('SELECT payment_no FROM billing_payments ORDER BY id DESC LIMIT 1');
    const payNo = nextDocumentNumber('PAY-', latestPay?.payment_no);

    await conn.query(
      `INSERT INTO billing_payments (billing_id, payment_no, payment_date, amount, reference, remarks)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [row.id, payNo, date || new Date().toISOString().split('T')[0], paymentAmount, reference || null, remarks || null]
    );

    const newPaid = parseFloat(row.paid_amount || 0) + paymentAmount;
    const isPaid = newPaid >= parseFloat(row.billing_total || 0);
    const status = isPaid ? 'PAID' : 'ACTIVE';

    await conn.query(`UPDATE ${BILLING} SET paid_amount = ?, status = ? WHERE id = ?`, [newPaid, status, row.id]);

    await conn.query(
      'INSERT INTO customer_ledger (customer_id, debit, credit) VALUES (?, 0, ?)',
      [row.customer_id, paymentAmount]
    );

    await conn.commit();
    const data = await loadBilling(row.id);
    return res.json({ message: 'Payment recorded successfully.', data });
  } catch (err) {
    await conn.rollback();
    return res.status(500).json({ message: err.message });
  } finally {
    conn.release();
  }
};
