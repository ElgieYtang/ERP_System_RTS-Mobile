const db = require('../config/db');
const { nextDocumentNumber } = require('../services/documentNumber');
const path = require('path');
const fs = require('fs');

function mapAccomplishmentRow(r, photos) {
  const reportPhotos = photos.filter(
    (p) => Number(p.accomplishment_id) === Number(r.id)
  );
  return {
    id: r.accomplishment_no,
    dbId: String(r.id),
    projectId: String(r.project_id),
    projectName: r.project_name || 'Project',
    location: r.project_location || '',
    date: r.accomplishment_date,
    displayDate: r.accomplishment_date,
    remarks: r.remarks,
    status: (r.status || 'pending').toLowerCase(),
    images: reportPhotos.map((p) => ({
      id: String(p.id),
      src: `/accomplishments/${r.id}/photos/${p.id}/file`,
    })),
  };
}

async function loadAccomplishment(id) {
  const [[r]] = await db.query(
    `SELECT a.*, p.name as project_name, p.address as project_location 
     FROM accomplishment_main a
     LEFT JOIN setup_project p ON a.project_id = p.id
     WHERE a.id = ? OR a.accomplishment_no = ?`,
    [id, id]
  );
  if (!r) return null;
  const [photos] = await db.query(
    'SELECT * FROM accomplishment_details WHERE accomplishment_id = ?',
    [r.id]
  );
  return mapAccomplishmentRow(r, photos);
}

exports.index = async (req, res) => {
  try {
    const [reports] = await db.query(
      `SELECT a.*, p.name as project_name, p.address as project_location 
       FROM accomplishment_main a
       LEFT JOIN setup_project p ON a.project_id = p.id
       ORDER BY a.id DESC`
    );
    const [photos] = await db.query('SELECT * FROM accomplishment_details');

    const mapped = reports.map((r) => mapAccomplishmentRow(r, photos));

    return res.json({ data: mapped });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.show = async (req, res) => {
  const { id } = req.params;
  try {
    const data = await loadAccomplishment(id);
    if (!data) return res.status(404).json({ message: 'Accomplishment report not found.' });
    return res.json({ data });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.store = async (req, res) => {
  const { projectId, remarks } = req.body;
  try {
    const [[latest]] = await db.query('SELECT accomplishment_no FROM accomplishment_main ORDER BY id DESC LIMIT 1');
    const arNo = nextDocumentNumber('AR-', latest?.accomplishment_no);

    const [result] = await db.query(
      `INSERT INTO accomplishment_main (accomplishment_no, accomplishment_date, project_id, remarks, status)
       VALUES (?, NOW(), ?, ?, 'PENDING')`,
      [arNo, projectId, remarks || null]
    );

    const data = await loadAccomplishment(result.insertId);

    return res.status(201).json({
      message: 'Accomplishment created.',
      data,
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.update = async (req, res) => {
  const { id } = req.params;
  const { status, remarks, date } = req.body;
  try {
    await db.query(
      'UPDATE accomplishment_main SET status = COALESCE(?, status), remarks = COALESCE(?, remarks), accomplishment_date = COALESCE(?, accomplishment_date) WHERE id = ? OR accomplishment_no = ?',
      [status ? status.toUpperCase() : null, remarks || null, date || null, id, id]
    );
    const data = await loadAccomplishment(id);
    return res.json({ message: 'Accomplishment report updated.', data });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.uploadPhotos = async (req, res) => {
  const { id } = req.params;
  if (!req.files || req.files.length === 0) {
    return res.status(422).json({ message: 'No photos provided.' });
  }

  try {
    const [[report]] = await db.query(
      'SELECT id FROM accomplishment_main WHERE id = ? OR accomplishment_no = ?',
      [id, id]
    );
    if (!report) {
      return res.status(404).json({ message: 'Accomplishment report not found.' });
    }

    for (const file of req.files) {
      await db.query(
        'INSERT INTO accomplishment_details (accomplishment_id, path_url) VALUES (?, ?)',
        [report.id, file.filename]
      );
    }

    const data = await loadAccomplishment(report.id);
    return res.status(201).json({ message: 'Photos uploaded successfully.', data });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.showPhoto = async (req, res) => {
  const { photoId } = req.params;
  try {
    const [[photo]] = await db.query('SELECT path_url FROM accomplishment_details WHERE id = ?', [photoId]);
    if (!photo) return res.status(404).send('Not found');

    const filePath = path.join(__dirname, '../../uploads', photo.path_url);
    if (!fs.existsSync(filePath)) return res.status(404).send('File missing');

    return res.sendFile(filePath);
  } catch (err) {
    return res.status(500).send(err.message);
  }
};

exports.destroy = async (req, res) => {
  const { id } = req.params;
  try {
    await db.query('UPDATE accomplishment_main SET status = "INACTIVE" WHERE id = ? OR accomplishment_no = ?', [id, id]);
    return res.json({ message: 'Accomplishment report deactivated.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};

exports.destroyPhoto = async (req, res) => {
  const { photoId } = req.params;
  try {
    const [[photo]] = await db.query('SELECT path_url FROM accomplishment_details WHERE id = ?', [photoId]);
    if (photo && photo.path_url) {
      const filePath = path.join(__dirname, '../../uploads', photo.path_url);
      if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    }
    await db.query('DELETE FROM accomplishment_details WHERE id = ?', [photoId]);
    return res.json({ message: 'Photo deleted.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
};
