const express = require('express');
const { sql, getPool } = require('../config/db');

const router = express.Router();

router.get('/', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool.request().query(`
      SELECT id, name, creatorid, [creation date] AS creationDate
      FROM dbo.[groups]
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
      .query(`
        SELECT id, name, creatorid, [creation date] AS creationDate
        FROM dbo.[groups]
        WHERE id = @id
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'Group not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/', async (req, res) => {
  const { name, creatorid, creationDate } = req.body;

  if (!name || !creatorid) {
    return res.status(400).json({ message: 'name and creatorid are required.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('name', sql.NVarChar(255), name)
      .input('creatorid', sql.Int, Number(creatorid))
      .input('creationDate', sql.DateTime2, creationDate || null)
      .query(`
        INSERT INTO dbo.[groups] (name, creatorid, [creation date])
        OUTPUT INSERTED.id, INSERTED.name, INSERTED.creatorid, INSERTED.[creation date] AS creationDate
        VALUES (@name, @creatorid, ISNULL(@creationDate, SYSUTCDATETIME()))
      `);

    return res.status(201).json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.put('/:id', async (req, res) => {
  const { name, creatorid, creationDate } = req.body;

  if (!name || !creatorid) {
    return res.status(400).json({ message: 'name and creatorid are required.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('id', sql.Int, Number(req.params.id))
      .input('name', sql.NVarChar(255), name)
      .input('creatorid', sql.Int, Number(creatorid))
      .input('creationDate', sql.DateTime2, creationDate || null)
      .query(`
        UPDATE dbo.[groups]
        SET name = @name,
            creatorid = @creatorid,
            [creation date] = ISNULL(@creationDate, [creation date])
        OUTPUT INSERTED.id, INSERTED.name, INSERTED.creatorid, INSERTED.[creation date] AS creationDate
        WHERE id = @id
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'Group not found.' });
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
      .query('DELETE FROM dbo.[groups] WHERE id = @id');

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ message: 'Group not found.' });
    }

    return res.json({ message: 'Group deleted.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
