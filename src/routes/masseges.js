const express = require('express');
const { sql, getPool } = require('../config/db');

const router = express.Router();

router.get('/', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool.request().query(`
      SELECT id, massege, createdat, createdby
      FROM dbo.[masseges]
      ORDER BY id DESC
    `);
    return res.json(result.recordset);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('id', sql.Int, Number(req.params.id))
      .query('SELECT id, massege, createdat, createdby FROM dbo.[masseges] WHERE id = @id');

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'massege not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/', async (req, res) => {
  const { massege, createdat, createdby } = req.body;

  if (!massege || !createdby) {
    return res.status(400).json({ message: 'massege and createdby are required.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('massege', sql.NVarChar(sql.MAX), massege)
      .input('createdat', sql.DateTime2, createdat || null)
      .input('createdby', sql.Int, Number(createdby))
      .query(`
        INSERT INTO dbo.[masseges] (massege, createdat, createdby)
        OUTPUT INSERTED.id, INSERTED.massege, INSERTED.createdat, INSERTED.createdby
        VALUES (@massege, ISNULL(@createdat, SYSUTCDATETIME()), @createdby)
      `);

    return res.status(201).json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.put('/:id', async (req, res) => {
  const { massege, createdat, createdby } = req.body;

  if (!massege || !createdby) {
    return res.status(400).json({ message: 'massege and createdby are required.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('id', sql.Int, Number(req.params.id))
      .input('massege', sql.NVarChar(sql.MAX), massege)
      .input('createdat', sql.DateTime2, createdat || null)
      .input('createdby', sql.Int, Number(createdby))
      .query(`
        UPDATE dbo.[masseges]
        SET massege = @massege,
            createdat = ISNULL(@createdat, createdat),
            createdby = @createdby
        OUTPUT INSERTED.id, INSERTED.massege, INSERTED.createdat, INSERTED.createdby
        WHERE id = @id
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'massege not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('id', sql.Int, Number(req.params.id))
      .query('DELETE FROM dbo.[masseges] WHERE id = @id');

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ message: 'massege not found.' });
    }

    return res.json({ message: 'massege deleted.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
