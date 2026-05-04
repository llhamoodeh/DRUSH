const express = require('express');
const { sql, getPool } = require('../config/db');

const router = express.Router();

let ensureCompletionTablePromise;

async function ensureCompletionTable() {
  if (!ensureCompletionTablePromise) {
    const pool = await getPool();
    ensureCompletionTablePromise = pool.request().query(`
      IF OBJECT_ID('dbo.schedule_completions', 'U') IS NULL
      BEGIN
        CREATE TABLE dbo.[schedule_completions] (
          id INT IDENTITY(1,1) PRIMARY KEY,
          userid INT NOT NULL,
          groupid INT NOT NULL,
          startdatetime DATETIME2 NOT NULL,
          completedby INT NOT NULL,
          completedat DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
        )
      END

      IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE name = 'UX_schedule_completions_task'
          AND object_id = OBJECT_ID('dbo.schedule_completions')
      )
      BEGIN
        CREATE UNIQUE INDEX [UX_schedule_completions_task]
        ON dbo.[schedule_completions] (userid, groupid, startdatetime)
      END
    `);
  }

  await ensureCompletionTablePromise;
}

function decodeDateParam(value) {
  return decodeURIComponent(value);
}

function tryParseDate(value) {
  if (!value) return null;
  const decoded = decodeDateParam(value);

  // Try direct Date parsing first
  let d = new Date(decoded);
  if (!isNaN(d.getTime())) return d;

  // Try removing trailing Z
  try {
    const withoutZ = decoded.replace(/Z$/, '');
    d = new Date(withoutZ);
    if (!isNaN(d.getTime())) return d;
  } catch (_) {}

  // Try removing fractional seconds
  try {
    const noFrac = decoded.replace(/\.\d{1,6}/, '');
    d = new Date(noFrac);
    if (!isNaN(d.getTime())) return d;
  } catch (_) {}

  // Try space instead of T
  try {
    const space = decoded.replace('T', ' ');
    d = new Date(space);
    if (!isNaN(d.getTime())) return d;
  } catch (_) {}

  return null;
}

function parseNullableGroupId(value) {
  if (value === undefined || value === null || value === '' || value === 'null') {
    return null;
  }

  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed === 0) {
    return null;
  }

  return parsed;
}

async function findScheduleRow(pool, userid, groupid, startdatetimeParam) {
  const parsed = tryParseDate(startdatetimeParam);
  const raw = decodeDateParam(startdatetimeParam);
  const normalizedGroupId = parseNullableGroupId(groupid);
  const groupClause = normalizedGroupId === null
    ? 'groupid IS NULL'
    : 'groupid = @groupid';

  if (parsed) {
    const exactResult = await pool
      .request()
      .input('userid', sql.Int, userid)
      .input('groupid', sql.Int, normalizedGroupId)
      .input('startdatetime', sql.DateTime2, parsed)
      .query(`
        SELECT TOP 1 userid, groupid, startdatetime
        FROM dbo.[schedule]
        WHERE userid = @userid AND ${groupClause} AND startdatetime = @startdatetime
      `);

    if (exactResult.recordset.length > 0) {
      return exactResult.recordset[0];
    }
  }

  const stringResult = await pool
    .request()
    .input('userid', sql.Int, userid)
    .input('groupid', sql.Int, normalizedGroupId)
    .input('raw', sql.NVarChar(64), raw)
    .query(`
      SELECT TOP 1 userid, groupid, startdatetime
      FROM dbo.[schedule]
      WHERE userid = @userid
        AND ${groupClause}
        AND CONVERT(varchar(64), startdatetime, 126) = @raw
    `);

  if (stringResult.recordset.length > 0) {
    return stringResult.recordset[0];
  }

  if (!parsed) {
    return null;
  }

  const prefix = raw.replace(/\.\d{1,6}/, '').replace(/Z$/, '').slice(0, 19);
  const looseResult = await pool
    .request()
    .input('userid', sql.Int, userid)
    .input('groupid', sql.Int, normalizedGroupId)
    .input('prefix', sql.NVarChar(32), prefix)
    .query(`
      SELECT TOP 1 userid, groupid, startdatetime
      FROM dbo.[schedule]
      WHERE userid = @userid
        AND ${groupClause}
        AND CONVERT(varchar(19), startdatetime, 126) = @prefix
      ORDER BY startdatetime DESC
    `);

  return looseResult.recordset[0] || null;
}

router.get('/', async (req, res) => {
  try {
    const pool = await getPool();
    const result = await pool.request().query(`
      SELECT
        s.userid,
        s.groupid,
        s.startdatetime,
        s.enddatetime,
        s.creeatedat,
        s.createdby,
        s.tips,
        c.completedat,
        c.completedby
      FROM dbo.[schedule]
      LEFT JOIN dbo.[schedule_completions] c
        ON c.userid = s.userid
       AND (c.groupid = s.groupid OR (c.groupid = 0 AND s.groupid IS NULL))
       AND c.startdatetime = s.startdatetime
      ORDER BY s.startdatetime DESC
    `);
    return res.json(result.recordset);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:userid/:groupid/:startdatetime', async (req, res) => {
  try {
    const pool = await getPool();
    const parsed = tryParseDate(req.params.startdatetime);
    if (!parsed) {
      return res.status(400).json({ message: 'Invalid startdatetime.' });
    }

    const groupid = parseNullableGroupId(req.params.groupid);
    const result = await pool
      .request()
      .input('userid', sql.Int, Number(req.params.userid))
      .input('groupid', sql.Int, groupid)
      .input('startdatetime', sql.DateTime2, parsed)
      .query(`
        SELECT
          s.userid,
          s.groupid,
          s.startdatetime,
          s.enddatetime,
          s.creeatedat,
          s.createdby,
          s.tips,
          c.completedat,
          c.completedby
        FROM dbo.[schedule] s
        LEFT JOIN dbo.[schedule_completions] c
          ON c.userid = s.userid
         AND (c.groupid = s.groupid OR (c.groupid = 0 AND s.groupid IS NULL))
         AND c.startdatetime = s.startdatetime
        WHERE s.userid = @userid
          AND ((@groupid IS NULL AND s.groupid IS NULL) OR s.groupid = @groupid)
          AND s.startdatetime = @startdatetime
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'schedule item not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/', async (req, res) => {
  const { userid, groupid, startdatetime, enddatetime, creeatedat, createdby, tips } = req.body;
  const normalizedGroupId = parseNullableGroupId(groupid);

  if (!userid || !startdatetime || !enddatetime || !createdby) {
    return res.status(400).json({
      message: 'userid, startdatetime, enddatetime and createdby are required.'
    });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('userid', sql.Int, Number(userid))
      .input('groupid', sql.Int, normalizedGroupId)
      .input('startdatetime', sql.DateTime2, startdatetime)
      .input('enddatetime', sql.DateTime2, enddatetime)
      .input('creeatedat', sql.DateTime2, creeatedat || null)
      .input('createdby', sql.Int, Number(createdby))
      .input('tips', sql.NVarChar(sql.MAX), tips || null)
      .query(`
        INSERT INTO dbo.[schedule] (userid, groupid, startdatetime, enddatetime, creeatedat, createdby, tips)
        OUTPUT INSERTED.userid, INSERTED.groupid, INSERTED.startdatetime, INSERTED.enddatetime,
               INSERTED.creeatedat, INSERTED.createdby, INSERTED.tips
        VALUES (
          @userid,
          @groupid,
          @startdatetime,
          @enddatetime,
          ISNULL(@creeatedat, SYSUTCDATETIME()),
          @createdby,
          @tips
        )
      `);

    return res.status(201).json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.put('/:userid/:groupid/:startdatetime', async (req, res) => {
  const { enddatetime, creeatedat, createdby, tips } = req.body;

  if (!enddatetime || !createdby) {
    return res.status(400).json({ message: 'enddatetime and createdby are required.' });
  }

  try {
    const pool = await getPool();
    const userid = Number(req.params.userid);
    const groupid = parseNullableGroupId(req.params.groupid);
    const scheduleRow = await findScheduleRow(pool, userid, groupid, req.params.startdatetime);

    if (!scheduleRow) {
      return res.status(404).json({ message: 'schedule item not found.' });
    }

    const result = await pool
      .request()
      .input('userid', sql.Int, userid)
      .input('groupid', sql.Int, scheduleRow.groupid ?? null)
      .input('startdatetime', sql.DateTime2, scheduleRow.startdatetime)
      .input('enddatetime', sql.DateTime2, enddatetime)
      .input('creeatedat', sql.DateTime2, creeatedat || null)
      .input('createdby', sql.Int, Number(createdby))
      .input('tips', sql.NVarChar(sql.MAX), tips || null)
      .query(`
        UPDATE dbo.[schedule]
        SET enddatetime = @enddatetime,
            creeatedat = ISNULL(@creeatedat, creeatedat),
            createdby = @createdby,
            tips = @tips
        OUTPUT INSERTED.userid, INSERTED.groupid, INSERTED.startdatetime, INSERTED.enddatetime,
               INSERTED.creeatedat, INSERTED.createdby, INSERTED.tips
        WHERE userid = @userid
          AND ((@groupid IS NULL AND groupid IS NULL) OR groupid = @groupid)
          AND startdatetime = @startdatetime
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'schedule item not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.delete('/:userid/:groupid/:startdatetime', async (req, res) => {
  try {
    const pool = await getPool();

    const userid = Number(req.params.userid);
    const groupid = parseNullableGroupId(req.params.groupid);
    const scheduleRow = await findScheduleRow(pool, userid, groupid, req.params.startdatetime);

    if (!scheduleRow) {
      return res.status(404).json({ message: 'schedule item not found.' });
    }

    const result = await pool
      .request()
      .input('userid', sql.Int, userid)
      .input('groupid', sql.Int, scheduleRow.groupid ?? null)
      .input('startdatetime', sql.DateTime2, scheduleRow.startdatetime)
      .query(`
        DELETE FROM dbo.[schedule]
        WHERE userid = @userid
          AND ((@groupid IS NULL AND groupid IS NULL) OR groupid = @groupid)
          AND startdatetime = @startdatetime
      `);

    if (result.rowsAffected[0] > 0) {
      return res.json({ message: 'schedule item deleted.' });
    }

    return res.status(404).json({ message: 'schedule item not found.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/:userid/:groupid/:startdatetime/complete', async (req, res) => {
  const taskUserId = Number(req.params.userid);

  if (!Number.isFinite(taskUserId)) {
    return res.status(400).json({ message: 'userid must be a number.' });
  }

  if (Number(req.user?.id) !== taskUserId) {
    return res.status(403).json({ message: 'You can only complete your own tasks.' });
  }

  try {
    await ensureCompletionTable();
    const pool = await getPool();
    const groupid = parseNullableGroupId(req.params.groupid);
    const scheduleRow = await findScheduleRow(
      pool,
      taskUserId,
      groupid,
      req.params.startdatetime,
    );

    if (!scheduleRow) {
      return res.status(404).json({ message: 'Task not found.' });
    }

    const startDateTime = scheduleRow.startdatetime;
    const completionGroupId = groupid ?? 0;

    const existingResult = await pool
      .request()
      .input('userid', sql.Int, taskUserId)
      .input('groupid', sql.Int, completionGroupId)
      .input('startdatetime', sql.DateTime2, startDateTime)
      .query(`
        SELECT id, userid, groupid, startdatetime, completedby, completedat
        FROM dbo.[schedule_completions]
        WHERE userid = @userid AND groupid = @groupid AND startdatetime = @startdatetime
      `);

    if (existingResult.recordset.length > 0) {
      return res.json(existingResult.recordset[0]);
    }

    const groupClause = groupid === null ? 'groupid IS NULL' : 'groupid = @groupid';
    const fullTaskResult = await pool
      .request()
      .input('userid', sql.Int, taskUserId)
      .input('groupid', sql.Int, groupid)
      .input('startdatetime', sql.DateTime2, startDateTime)
      .query(`
        SELECT userid, groupid, startdatetime, enddatetime
        FROM dbo.[schedule]
        WHERE userid = @userid
          AND ${groupClause}
          AND startdatetime = @startdatetime
      `);

    if (fullTaskResult.recordset.length === 0) {
      return res.status(404).json({ message: 'Task not found.' });
    }

    const fullTask = fullTaskResult.recordset[0];
    const completionTime = new Date();
    const deadline = new Date(fullTask.enddatetime);

    if (completionTime > deadline) {
      return res.status(400).json({ message: 'Cannot complete task after the deadline.' });
    }

    const insertResult = await pool
      .request()
      .input('userid', sql.Int, taskUserId)
      .input('groupid', sql.Int, completionGroupId)
      .input('startdatetime', sql.DateTime2, startDateTime)
      .input('completedby', sql.Int, taskUserId)
      .query(`
        INSERT INTO dbo.[schedule_completions] (userid, groupid, startdatetime, completedby, completedat)
        OUTPUT INSERTED.id, INSERTED.userid, INSERTED.groupid, INSERTED.startdatetime, INSERTED.completedby, INSERTED.completedat
        VALUES (@userid, @groupid, @startdatetime, @completedby, SYSUTCDATETIME())
      `);

    return res.json({ message: 'Congrats! 🎉🎊', completion: insertResult.recordset[0] });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
