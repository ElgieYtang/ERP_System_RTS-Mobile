const db = require('../config/db');
const bcrypt = require('bcryptjs');
const setupPresenter = require('../services/setupPresenter');
const { quantitiesByItemId } = require('../services/inventoryStock');

const RESOURCE_TABLE_MAP = {
  companies: { table: 'setup_company', prefix: 'COM' },
  branches: { table: 'setup_branch', prefix: 'BR' },
  users: { table: 'setup_users', prefix: 'USR' },
  positions: { table: 'setup_position', prefix: 'POS' },
  projects: { table: 'setup_project', prefix: 'PRJ' },
  categories: { table: 'setup_category', prefix: 'CAT' },
  brands: { table: 'setup_brand', prefix: 'BRD' },
  models: { table: 'setup_model', prefix: 'MOD' },
  units: { table: 'setup_unit_measure', prefix: 'UNT' },
  items: { table: 'setup_items', prefix: 'ITM' },
  suppliers: { table: 'setup_supplier', prefix: 'SUP' },
  customers: { table: 'setup_customer', prefix: 'CUST' },
};

exports.index = async (req, res) => {
  const { resource } = req.params;
  const config = RESOURCE_TABLE_MAP[resource];
  if (!config) return res.status(404).json({ message: 'Setup resource not found.' });

  try {
    if (resource === 'items') {
      const [rows] = await db.query(
        `SELECT i.*, b.name AS brand_name, m.name AS model_name, u.name AS unit_name
         FROM setup_items i
         LEFT JOIN setup_brand b ON i.brand_id = b.id
         LEFT JOIN setup_model m ON i.model_id = m.id
         LEFT JOIN setup_unit_measure u ON i.unit_measure_id = u.id
         ORDER BY i.id ASC`
      );
      const stockByItemId = await quantitiesByItemId();
      return res.json({ data: setupPresenter.collection('items', rows, stockByItemId) });
    }

    const [rows] = await db.query(`SELECT * FROM ${config.table} ORDER BY id ASC`);
    return res.json({ data: setupPresenter.collection(resource, rows) });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.store = async (req, res) => {
  const { resource } = req.params;
  const config = RESOURCE_TABLE_MAP[resource];
  if (!config) return res.status(404).json({ message: 'Setup resource not found.' });

  const payload = { ...req.body, status: 'Active' };

  if (resource === 'users' && payload.password) {
    payload.password = bcrypt.hashSync(payload.password, 10);
  }

  try {
    const keys = Object.keys(payload);
    const values = Object.values(payload);
    const placeholders = keys.map(() => '?').join(', ');

    const [result] = await db.query(
      `INSERT INTO ${config.table} (${keys.join(', ')}) VALUES (${placeholders})`,
      values
    );

    return res.status(201).json({
      message: 'Record created successfully.',
      data: { id: result.insertId, ...payload },
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.update = async (req, res) => {
  const { resource, id } = req.params;
  const config = RESOURCE_TABLE_MAP[resource];
  if (!config) return res.status(404).json({ message: 'Setup resource not found.' });

  const payload = { ...req.body };
  if (resource === 'users' && payload.password) {
    payload.password = bcrypt.hashSync(payload.password, 10);
  } else if (resource === 'users') {
    delete payload.password;
  }

  try {
    const updates = Object.keys(payload).map((k) => `${k} = ?`).join(', ');
    const values = [...Object.values(payload), id];

    await db.query(`UPDATE ${config.table} SET ${updates} WHERE id = ?`, values);
    return res.json({ message: 'Record updated successfully.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.destroy = async (req, res) => {
  const { resource, id } = req.params;
  const config = RESOURCE_TABLE_MAP[resource];
  if (!config) return res.status(404).json({ message: 'Setup resource not found.' });

  try {
    await db.query(`UPDATE ${config.table} SET status = 'Inactive' WHERE id = ?`, [id]);
    return res.json({ message: 'Record deactivated successfully.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.showItemByBarcode = async (req, res) => {
  const { barcode } = req.params;
  try {
    const [rows] = await db.query(
      `SELECT i.*, b.name AS brand_name, u.name AS unit_name
       FROM setup_items i
       LEFT JOIN setup_brand b ON i.brand_id = b.id
       LEFT JOIN setup_unit_measure u ON i.unit_measure_id = u.id
       WHERE LOWER(TRIM(i.barcode)) = ? AND UPPER(TRIM(i.status)) = 'ACTIVE' LIMIT 1`,
      [barcode.trim().toLowerCase()]
    );

    if (rows.length === 0) {
      return res.status(404).json({ message: 'No item found for this barcode.' });
    }

    const item = rows[0];
    return res.json({
      data: {
        id: String(item.id),
        name: item.item_name,
        code: item.barcode,
        brand: item.brand_name || '',
        unit: item.unit_name || 'UNITS',
      },
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};