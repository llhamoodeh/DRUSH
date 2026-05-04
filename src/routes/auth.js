const express = require('express');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { sql, getPool } = require('../config/db');
const authMiddleware = require('../middleware/auth');

const router = express.Router();

let ensureScheduleTablePromise;
let ensureCompletionTablePromise;
let ensureCoinsColumnPromise;

async function ensureScheduleTable() {
  if (!ensureScheduleTablePromise) {
    const pool = await getPool();
    ensureScheduleTablePromise = pool.request().query(`
      IF COL_LENGTH('dbo.schedule', 'id') IS NULL
      BEGIN
        ALTER TABLE dbo.[schedule]
        ADD id INT IDENTITY(1,1) NOT NULL
      END

      IF COL_LENGTH('dbo.schedule', 'penalized') IS NULL
      BEGIN
        ALTER TABLE dbo.[schedule]
        ADD penalized BIT NOT NULL DEFAULT 0
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

async function ensureCoinsColumn() {
  if (!ensureCoinsColumnPromise) {
    const pool = await getPool();
    ensureCoinsColumnPromise = pool.request().query(`
      IF NOT EXISTS (
        SELECT 1
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'users'
          AND COLUMN_NAME = 'coins'
      )
      BEGIN
        ALTER TABLE dbo.[users]
        ADD coins INT NOT NULL DEFAULT 0
      END
    `);
  }

  await ensureCoinsColumnPromise;
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

async function applyOverduePenalties(pool, userId) {
  const request = pool.request().input('now', sql.DateTime2, new Date());

  if (Number.isFinite(userId)) {
    request.input('userid', sql.Int, userId);
  }

  await request.query(`
    DECLARE @overdue TABLE (id INT, userid INT);

    INSERT INTO @overdue (id, userid)
    SELECT s.id, s.userid
    FROM dbo.[schedule] s
    LEFT JOIN dbo.[schedule_completions] c
      ON c.userid = s.userid
     AND c.startdatetime = s.startdatetime
     AND (c.groupid = s.groupid OR (c.groupid = 0 AND s.groupid IS NULL))
    WHERE s.enddatetime < @now
      AND (s.penalized = 0 OR s.penalized IS NULL)
      AND c.userid IS NULL
      ${Number.isFinite(userId) ? 'AND s.userid = @userid' : ''};

    UPDATE u
    SET coins = coins - (o.cnt * 10)
    FROM dbo.[users] u
    INNER JOIN (
      SELECT userid, COUNT(*) AS cnt
      FROM @overdue
      GROUP BY userid
    ) o ON o.userid = u.id;

    UPDATE s
    SET penalized = 1
    FROM dbo.[schedule] s
    INNER JOIN @overdue o ON o.id = s.id;
  `);
}

router.post('/login', async (req, res) => {
  const { email, password } = req.body || {};

  if (!email || !password) {
    return res.status(400).json({ message: 'email and password are required.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('email', sql.NVarChar(320), email)
      .query(`SELECT TOP 1 id, name, email, [password] AS passwordHash, ISNULL(coins,0) AS coins FROM dbo.[users] WHERE email = @email`);

    if (result.recordset.length === 0) {
      return res.status(401).json({ message: 'Invalid email or password.' });
    }

    const user = result.recordset[0];
    const ok = await bcrypt.compare(password, user.passwordHash || '');

    if (!ok) {
      return res.status(401).json({ message: 'Invalid email or password.' });
    }

    const token = jwt.sign({ id: user.id, email: user.email, name: user.name }, process.env.JWT_SECRET || 'change-this-secret', { expiresIn: '7d' });

    return res.json({ token, user: { id: user.id, name: user.name, email: user.email, coins: Number(user.coins || 0) } });
  } catch (err) {
    console.error('Login error', err);
    return res.status(500).json({ message: err.message });
  }
});

router.post('/register', async (req, res) => {
  const { name, email, password } = req.body || {};

  if (!name || !email || !password) {
    return res.status(400).json({ message: 'name, email and password are required.' });
  }

  if ((password || '').length < 6) {
    return res.status(400).json({ message: 'Password must be at least 6 characters.' });
  }

  try {
    const pool = await getPool();

    const existing = await pool.request().input('email', sql.NVarChar(320), email).query(`SELECT TOP 1 id FROM dbo.[users] WHERE email = @email`);
    if (existing.recordset.length > 0) {
      return res.status(409).json({ message: 'An account with that email already exists.' });
    }

    const passwordHash = await bcrypt.hash(password, 10);

    const insertResult = await pool
      .request()
      .input('name', sql.NVarChar(200), name)
      .input('email', sql.NVarChar(320), email)
      .input('password', sql.NVarChar(4000), passwordHash)
      .query(`
        INSERT INTO dbo.[users] (name, email, [password])
        OUTPUT INSERTED.id, INSERTED.name, INSERTED.email
        VALUES (@name, @email, @password)
      `);

    const inserted = insertResult.recordset[0];
    const token = jwt.sign({ id: inserted.id, email: inserted.email, name: inserted.name }, process.env.JWT_SECRET || 'change-this-secret', { expiresIn: '7d' });

    return res.status(201).json({ token, user: { id: inserted.id, name: inserted.name, email: inserted.email } });
  } catch (err) {
    console.error('Register error', err);
    return res.status(500).json({ message: err.message });
  }
});

router.get('/me', authMiddleware, async (req, res) => {
  try {
    const userId = Number(req.user?.id);
    if (!Number.isFinite(userId)) return res.status(401).json({ message: 'Unauthorized.' });

    const pool = await getPool();
    const result = await pool.request().input('id', sql.Int, userId).query(`SELECT id, name, email, ISNULL(coins,0) AS coins FROM dbo.[users] WHERE id = @id`);
    if (result.recordset.length === 0) return res.status(404).json({ message: 'User not found.' });
    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/me/coins', authMiddleware, async (req, res) => {
  try {
    const userId = Number(req.user?.id);
    if (!Number.isFinite(userId)) return res.status(401).json({ message: 'Unauthorized.' });

    await ensureCompletionTable();
    await ensureCoinsColumn();
    const pool = await getPool();
    await applyOverduePenalties(pool, userId);

    const result = await pool.request().input('id', sql.Int, userId).query(`SELECT id, name, email, ISNULL(coins,0) AS coins FROM dbo.[users] WHERE id = @id`);
    if (result.recordset.length === 0) return res.status(404).json({ message: 'User not found.' });
    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/me/streak', authMiddleware, async (req, res) => {
  try {
    const userId = Number(req.user?.id);
    if (!Number.isFinite(userId)) return res.status(401).json({ message: 'Unauthorized.' });

    await ensureCompletionTable();
    await ensureCoinsColumn();
    const pool = await getPool();
    await applyOverduePenalties(pool, userId);

    const completionsResult = await pool
      .request()
      .input('userid', sql.Int, userId)
      .query(`
        SELECT CONVERT(DATE, c.completedat) as completionDate
        FROM dbo.[schedule_completions] c
        INNER JOIN dbo.[schedule] s 
          ON s.userid = c.userid
         AND s.startdatetime = c.startdatetime
         AND (s.groupid = c.groupid OR (c.groupid = 0 AND s.groupid IS NULL))
        WHERE c.userid = @userid 
          AND c.completedat <= s.enddatetime
        GROUP BY CONVERT(DATE, c.completedat)
        ORDER BY CONVERT(DATE, c.completedat) ASC
      `);

    const completedDates = completionsResult.recordset.map(r => new Date(r.completionDate));

    const statsResult = await pool
      .request()
      .input('userid', sql.Int, userId)
      .query(`
        SELECT 
          SUM(CASE WHEN c.completedat <= s.enddatetime THEN 1 ELSE 0 END) as onTimeCount,
          SUM(CASE WHEN c.completedat > s.enddatetime THEN 1 ELSE 0 END) as lateCount
        FROM dbo.[schedule_completions] c
        INNER JOIN dbo.[schedule] s 
          ON s.userid = c.userid
         AND s.startdatetime = c.startdatetime
         AND (s.groupid = c.groupid OR (c.groupid = 0 AND s.groupid IS NULL))
        WHERE c.userid = @userid
      `);

    const stats = statsResult.recordset[0] || { onTimeCount: 0, lateCount: 0 };

    let currentStreak = 0;
    let longestStreak = 0;
    let tempStreak = 0;
    let lastStreakDate = null;

    const today = new Date();
    today.setHours(0,0,0,0);

    for (let i = 0; i < completedDates.length; i++) {
      const current = new Date(completedDates[i]);
      current.setHours(0,0,0,0);

      if (i === 0) {
        tempStreak = 1;
        lastStreakDate = current;
      } else {
        const prev = new Date(completedDates[i - 1]);
        prev.setHours(0,0,0,0);
        const daysDiff = Math.floor((current.getTime() - prev.getTime()) / (1000*60*60*24));

        if (daysDiff === 1) {
          tempStreak++;
          lastStreakDate = current;
        } else if (daysDiff > 1) {
          longestStreak = Math.max(longestStreak, tempStreak);
          tempStreak = 1;
          lastStreakDate = current;
        }
      }
    }

    longestStreak = Math.max(longestStreak, tempStreak);

    if (lastStreakDate) {
      const daysSinceLastCompletion = Math.floor((today.getTime() - lastStreakDate.getTime()) / (1000*60*60*24));
      if (daysSinceLastCompletion <= 1) {
        currentStreak = tempStreak;
      }
    }

    return res.json({ currentStreak, longestStreak, lastStreakDate: lastStreakDate ? lastStreakDate.toISOString().split('T')[0] : null, totalOnTimeCompletions: (stats.onTimeCount||0), totalLateCompletions: (stats.lateCount||0) });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/leaderboard', authMiddleware, async (req, res) => {
  try {
    const userId = Number(req.user?.id);
    if (!Number.isFinite(userId)) return res.status(401).json({ message: 'Unauthorized.' });

    await ensureCompletionTable();
    await ensureCoinsColumn();
    const pool = await getPool();
    await applyOverduePenalties(pool, null);

    const usersResult = await pool.request().query(`SELECT id, name, ISNULL(coins,0) AS coins FROM dbo.[users]`);

    const completionResult = await pool.request().query(`
      SELECT
        c.userid,
        CONVERT(DATE, c.completedat) AS completionDate,
        SUM(CASE WHEN c.completedat <= s.enddatetime THEN 1 ELSE 0 END) AS onTimeCount,
        SUM(CASE WHEN c.completedat > s.enddatetime THEN 1 ELSE 0 END) AS lateCount
      FROM dbo.[schedule_completions] c
      INNER JOIN dbo.[schedule] s
        ON s.userid = c.userid
       AND s.startdatetime = c.startdatetime
       AND (s.groupid = c.groupid OR (c.groupid = 0 AND s.groupid IS NULL))
      GROUP BY c.userid, CONVERT(DATE, c.completedat)
    `);

    const completionRows = completionResult.recordset;
    const statsByUser = new Map();

    for (const row of completionRows) {
      const uid = Number(row.userid);
      const completionDate = row.completionDate ? new Date(row.completionDate) : null;
      const onTimeCount = Number(row.onTimeCount || 0);
      const lateCount = Number(row.lateCount || 0);

      if (!statsByUser.has(uid)) {
        statsByUser.set(uid, { dates: [], totalOnTimeCompletions: 0, totalLateCompletions: 0 });
      }

      const userStats = statsByUser.get(uid);
      if (completionDate && onTimeCount > 0) userStats.dates.push(completionDate);
      userStats.totalOnTimeCompletions += onTimeCount;
      userStats.totalLateCompletions += lateCount;
    }

    const today = new Date();
    today.setHours(0,0,0,0);

    const leaderboard = usersResult.recordset.map(user => {
      const uid = Number(user.id);
      const userStats = statsByUser.get(uid) || { dates: [], totalOnTimeCompletions: 0, totalLateCompletions: 0 };

      const dates = userStats.dates.map(d => { const n = new Date(d); n.setHours(0,0,0,0); return n; }).sort((a,b)=>a.getTime()-b.getTime());

      let longestStreak = 0, tempStreak = 0, lastStreakDate = null;

      for (let i=0;i<dates.length;i++){
        const current = dates[i];
        if (i===0){ tempStreak=1; lastStreakDate=current; continue; }
        const prev = dates[i-1];
        const daysDiff = Math.floor((current.getTime()-prev.getTime())/(1000*60*60*24));
        if (daysDiff===1){ tempStreak++; lastStreakDate=current; } else if (daysDiff>1){ longestStreak = Math.max(longestStreak, tempStreak); tempStreak=1; lastStreakDate=current; }
      }
      longestStreak = Math.max(longestStreak, tempStreak);

      let currentStreak = 0;
      if (lastStreakDate) {
        const daysSinceLastCompletion = Math.floor((today.getTime() - lastStreakDate.getTime())/(1000*60*60*24));
        if (daysSinceLastCompletion <= 1) currentStreak = tempStreak;
      }

      return {
        userId: uid,
        name: user.name,
        coins: Number(user.coins || 0),
        currentStreak,
        longestStreak,
        totalOnTimeCompletions: userStats.totalOnTimeCompletions,
        totalLateCompletions: userStats.totalLateCompletions
      };
    });

    leaderboard.sort((l,r)=>{
      if (r.coins !== l.coins) return r.coins - l.coins;
      if (r.currentStreak !== l.currentStreak) return r.currentStreak - l.currentStreak;
      if (r.totalOnTimeCompletions !== l.totalOnTimeCompletions) return r.totalOnTimeCompletions - l.totalOnTimeCompletions;
      return l.name.localeCompare(r.name);
    });

    const ranked = leaderboard.map((entry, idx)=>({ rank: idx+1, isCurrentUser: entry.userId === userId, ...entry }));
    return res.json(ranked);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
