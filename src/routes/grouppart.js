const express = require('express');
const { sql, getPool } = require('../config/db');

const router = express.Router();

router.get('/', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool.request().query('SELECT id, groupid, userid FROM dbo.[grouppart] ORDER BY id DESC');
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
      .query('SELECT id, groupid, userid FROM dbo.[grouppart] WHERE id = @id');

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'grouppart not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/', async (req, res) => {
  const { groupid, userid } = req.body;

  if (!groupid || !userid) {
    return res.status(400).json({ message: 'groupid and userid are required.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('groupid', sql.Int, Number(groupid))
      .input('userid', sql.Int, Number(userid))
      .query(`
        INSERT INTO dbo.[grouppart] (groupid, userid)
        OUTPUT INSERTED.id, INSERTED.groupid, INSERTED.userid
        VALUES (@groupid, @userid)
      `);

    return res.status(201).json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.put('/:id', async (req, res) => {
  const { groupid, userid } = req.body;

  if (!groupid || !userid) {
    return res.status(400).json({ message: 'groupid and userid are required.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('id', sql.Int, Number(req.params.id))
      .input('groupid', sql.Int, Number(groupid))
      .input('userid', sql.Int, Number(userid))
      .query(`
        UPDATE dbo.[grouppart]
        SET groupid = @groupid,
            userid = @userid
        OUTPUT INSERTED.id, INSERTED.groupid, INSERTED.userid
        WHERE id = @id
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'grouppart not found.' });
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
      .query('DELETE FROM dbo.[grouppart] WHERE id = @id');

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ message: 'grouppart not found.' });
    }

    return res.json({ message: 'grouppart deleted.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
