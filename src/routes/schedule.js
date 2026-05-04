const express = require('express');
const { sql, getPool } = require('../config/db');

const router = express.Router();

let ensureScheduleTablePromise;
let ensureCompletionTablePromise;

async function ensureScheduleTable() {
  if (!ensureScheduleTablePromise) {
    const pool = await getPool();
    ensureScheduleTablePromise = pool.request().query(`
      IF COL_LENGTH('dbo.schedule', 'id') IS NULL
      BEGIN
        ALTER TABLE dbo.[schedule]
        ADD id INT IDENTITY(1,1) NOT NULL
      END

      IF NOT EXISTS (
        SELECT 1
        FROM sys.key_constraints
        WHERE type = 'PK'
          AND parent_object_id = OBJECT_ID('dbo.schedule')
      )
      BEGIN
        ALTER TABLE dbo.[schedule]
        ADD CONSTRAINT PK_schedule_id PRIMARY KEY (id)
      END
    `);
  }

  await ensureScheduleTablePromise;
}

async function ensureCompletionTable() {
  await ensureScheduleTable();
  if (!ensureCompletionTablePromise) {
    const pool = await getPool();
    ensureCompletionTablePromise = pool.request().query(`
      IF OBJECT_ID('dbo.schedule_completions', 'U') IS NULL
      BEGIN
        CREATE TABLE dbo.[schedule_completions] (
          userid INT NOT NULL,
          groupid INT NOT NULL,
          startdatetime DATETIME2 NOT NULL,
          completedby INT NOT NULL,
          completedat DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
          PRIMARY KEY (userid, groupid, startdatetime)
        )
      END
    `);
  }

  await ensureCompletionTablePromise;
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

router.get('/', async (req, res) => {
  try {
    await ensureScheduleTable();
    await ensureCompletionTable();
    const pool = await getPool();
    const result = await pool.request().query(`
      SELECT
        s.id,
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
       AND c.startdatetime = s.startdatetime
       AND (c.groupid = s.groupid OR (c.groupid = 0 AND s.groupid IS NULL))
      ORDER BY s.startdatetime DESC
    `);
    return res.json(result.recordset);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: err.message });
  }
});

router.get('/:id', async (req, res) => {
  const scheduleId = Number(req.params.id);

  if (!Number.isFinite(scheduleId)) {
    return res.status(400).json({ message: 'id must be a number.' });
  }

  try {
    await ensureScheduleTable();
    await ensureCompletionTable();
    const pool = await getPool();
    const result = await pool
      .request()
      .input('id', sql.Int, scheduleId)
      .query(`
        SELECT
          s.id,
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
          ON c.scheduleid = s.id
        WHERE s.id = @id
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
    await ensureScheduleTable();
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
        OUTPUT INSERTED.id, INSERTED.userid, INSERTED.groupid, INSERTED.startdatetime, INSERTED.enddatetime,
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

router.put('/:id', async (req, res) => {
  const scheduleId = Number(req.params.id);
  const { userid, groupid, startdatetime, enddatetime, creeatedat, createdby, tips } = req.body;

  if (!Number.isFinite(scheduleId)) {
    return res.status(400).json({ message: 'id must be a number.' });
  }

  if (!userid || !startdatetime || !enddatetime || !createdby) {
    return res.status(400).json({ message: 'userid, startdatetime, enddatetime and createdby are required.' });
  }

  try {
    await ensureScheduleTable();
    const pool = await getPool();
    const normalizedGroupId = parseNullableGroupId(groupid);
    const result = await pool
      .request()
      .input('id', sql.Int, scheduleId)
      .input('userid', sql.Int, Number(userid))
      .input('groupid', sql.Int, normalizedGroupId)
      .input('startdatetime', sql.DateTime2, startdatetime)
      .input('enddatetime', sql.DateTime2, enddatetime)
      .input('creeatedat', sql.DateTime2, creeatedat || null)
      .input('createdby', sql.Int, Number(createdby))
      .input('tips', sql.NVarChar(sql.MAX), tips || null)
      .query(`
        UPDATE dbo.[schedule]
        SET userid = @userid,
            groupid = @groupid,
            startdatetime = @startdatetime,
            enddatetime = @enddatetime,
            creeatedat = ISNULL(@creeatedat, creeatedat),
            createdby = @createdby,
            tips = @tips
        OUTPUT INSERTED.id, INSERTED.userid, INSERTED.groupid, INSERTED.startdatetime, INSERTED.enddatetime,
               INSERTED.creeatedat, INSERTED.createdby, INSERTED.tips
        WHERE id = @id
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'schedule item not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  const scheduleId = Number(req.params.id);

  if (!Number.isFinite(scheduleId)) {
    return res.status(400).json({ message: 'id must be a number.' });
  }

  try {
    await ensureScheduleTable();
    const pool = await getPool();
    await pool
      .request()
      .input('scheduleid', sql.Int, scheduleId)
      .query(`
        DELETE FROM dbo.[schedule_completions]
        WHERE scheduleid = @scheduleid
      `);

    const result = await pool
      .request()
      .input('id', sql.Int, scheduleId)
      .query(`
        DELETE FROM dbo.[schedule]
        WHERE id = @id
      `);

    if (result.rowsAffected[0] > 0) {
      return res.json({ message: 'schedule item deleted.' });
    }

    return res.status(404).json({ message: 'schedule item not found.' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/:id/complete', async (req, res) => {
  const scheduleId = Number(req.params.id);

  if (!Number.isFinite(scheduleId)) {
    return res.status(400).json({ message: 'id must be a number.' });
  }

  try {
    await ensureCompletionTable();
    const pool = await getPool();
    const scheduleResult = await pool
      .request()
      .input('id', sql.Int, scheduleId)
      .query(`
        SELECT id, userid, groupid, startdatetime, enddatetime
        FROM dbo.[schedule]
        WHERE id = @id
      `);

    if (scheduleResult.recordset.length === 0) {
      return res.status(404).json({ message: 'Task not found.' });
    }

    const schedule = scheduleResult.recordset[0];
    const taskUserId = Number(schedule.userid);
    const scheduleGroupId = schedule.groupid ?? 0;

    if (Number(req.user?.id) !== taskUserId) {
      return res.status(403).json({ message: 'You can only complete your own tasks.' });
    }

    if (schedule.groupid !== null) {
      return res.status(400).json({ message: 'Group tasks must be completed through the group endpoint.' });
    }

    const existingResult = await pool
      .request()
      .input('scheduleid', sql.Int, scheduleId)
      .query(`
        SELECT id, scheduleid, userid, groupid, startdatetime, completedby, completedat
        FROM dbo.[schedule_completions]
        WHERE scheduleid = @scheduleid
      `);

    if (existingResult.recordset.length > 0) {
      return res.json(existingResult.recordset[0]);
    }

    const completionTime = new Date();
    const deadline = new Date(schedule.enddatetime);

    if (completionTime > deadline) {
      return res.status(400).json({ message: 'Cannot complete task after the deadline.' });
    }

    const insertResult = await pool
      .request()
      .input('scheduleid', sql.Int, scheduleId)
      .input('userid', sql.Int, taskUserId)
      .input('groupid', sql.Int, scheduleGroupId)
      .input('startdatetime', sql.DateTime2, schedule.startdatetime)
      .input('completedby', sql.Int, taskUserId)
      .query(`
        INSERT INTO dbo.[schedule_completions] (scheduleid, userid, groupid, startdatetime, completedby, completedat)
        OUTPUT INSERTED.id, INSERTED.scheduleid, INSERTED.userid, INSERTED.groupid, INSERTED.startdatetime, INSERTED.completedby, INSERTED.completedat
        VALUES (@scheduleid, @userid, @groupid, @startdatetime, @completedby, SYSUTCDATETIME())
      `);

    return res.json({ message: 'Congrats! 🎉🎊', completion: insertResult.recordset[0] });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
