const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { sql, getPool } = require('../config/db');
const authMiddleware = require('../middleware/auth');

const router = express.Router();

router.post('/login', async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ message: 'email and password are required.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('email', sql.NVarChar(320), email)
      .query(`
        SELECT TOP 1 id, name, email, [password] AS password_hash
        FROM dbo.[users]
        WHERE email = @email
      `);

    if (result.recordset.length === 0) {
      return res.status(401).json({ message: 'Invalid credentials.' });
    }

    const user = result.recordset[0];

    let passwordMatches = false;
    try {
      passwordMatches = await bcrypt.compare(password, user.password_hash);
    } catch (err) {
      passwordMatches = false;
    }

    if (!passwordMatches) {
      passwordMatches = password === user.password_hash;
    }

    if (!passwordMatches) {
      return res.status(401).json({ message: 'Invalid credentials.' });
    }

    const token = jwt.sign(
      { id: user.id, email: user.email, name: user.name },
      process.env.JWT_SECRET || 'change-this-secret',
      { expiresIn: '7d' }
    );

    return res.json({
      token,
      user: {
        id: user.id,
        name: user.name,
        email: user.email
      }
    });
  } catch (err) {
    if (typeof err.message === 'string' && err.message.includes("Login failed for user")) {
      return res.status(500).json({ message: 'Database authentication failed. Check DB_USER and DB_PASSWORD configuration.' });
    }

    return res.status(500).json({ message: err.message });
  }
});

router.get('/me/coins', authMiddleware, async (req, res) => {
  try {
    const userId = Number(req.user?.id);
    
    if (!Number.isFinite(userId)) {
      return res.status(401).json({ message: 'Unauthorized.' });
    }

    const pool = await getPool();
    
    // Ensure coins column exists
    await pool.request().query(`
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

    const result = await pool
      .request()
      .input('id', sql.Int, userId)
      .query(`
        SELECT id, name, email, ISNULL(coins, 0) AS coins
        FROM dbo.[users]
        WHERE id = @id
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'User not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/me/streak', authMiddleware, async (req, res) => {
  try {
    const userId = Number(req.user?.id);
    
    if (!Number.isFinite(userId)) {
      return res.status(401).json({ message: 'Unauthorized.' });
    }

    const pool = await getPool();

    // Get all on-time completions for the user, ordered by date
    const completionsResult = await pool
      .request()
      .input('userid', sql.Int, userId)
      .query(`
        SELECT CONVERT(DATE, c.completedat) as completionDate
        FROM dbo.[schedule_completions] c
        INNER JOIN dbo.[schedule] s 
          ON s.userid = c.userid 
          AND s.groupid = c.groupid 
          AND s.startdatetime = c.startdatetime
        WHERE c.userid = @userid 
          AND c.completedat <= s.enddatetime
        GROUP BY CONVERT(DATE, c.completedat)
        ORDER BY CONVERT(DATE, c.completedat) ASC
      `);

    const completedDates = completionsResult.recordset.map(r => new Date(r.completionDate));

    // Count total on-time and late completions
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
          AND s.groupid = c.groupid 
          AND s.startdatetime = c.startdatetime
        WHERE c.userid = @userid
      `);

    const stats = statsResult.recordset[0] || { onTimeCount: 0, lateCount: 0 };

    // Calculate streaks
    let currentStreak = 0;
    let longestStreak = 0;
    let tempStreak = 0;
    let lastStreakDate = null;

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    for (let i = 0; i < completedDates.length; i++) {
      const current = new Date(completedDates[i]);
      current.setHours(0, 0, 0, 0);

      if (i === 0) {
        tempStreak = 1;
        lastStreakDate = current;
      } else {
        const prev = new Date(completedDates[i - 1]);
        prev.setHours(0, 0, 0, 0);
        
        const daysDiff = Math.floor((current.getTime() - prev.getTime()) / (1000 * 60 * 60 * 24));

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

    // Determine current streak: only if last completion was today or yesterday
    currentStreak = 0;
    if (lastStreakDate) {
      const daysSinceLastCompletion = Math.floor((today.getTime() - lastStreakDate.getTime()) / (1000 * 60 * 60 * 24));
      // If last completion was today or yesterday, count the streak
      if (daysSinceLastCompletion <= 1) {
        currentStreak = tempStreak;
      }
    }

    return res.json({
      currentStreak,
      longestStreak,
      lastStreakDate: lastStreakDate ? lastStreakDate.toISOString().split('T')[0] : null,
      totalOnTimeCompletions: (stats.onTimeCount || 0),
      totalLateCompletions: (stats.lateCount || 0),
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/leaderboard', authMiddleware, async (req, res) => {
  try {
    const userId = Number(req.user?.id);

    if (!Number.isFinite(userId)) {
      return res.status(401).json({ message: 'Unauthorized.' });
    }

    const pool = await getPool();

    await pool.request().query(`
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

    const usersResult = await pool.request().query(`
      SELECT id, name, ISNULL(coins, 0) AS coins
      FROM dbo.[users]
    `);

    const completionResult = await pool.request().query(`
      SELECT
        c.userid,
        CONVERT(DATE, c.completedat) AS completionDate,
        SUM(CASE WHEN c.completedat <= s.enddatetime THEN 1 ELSE 0 END) AS onTimeCount,
        SUM(CASE WHEN c.completedat > s.enddatetime THEN 1 ELSE 0 END) AS lateCount
      FROM dbo.[schedule_completions] c
      INNER JOIN dbo.[schedule] s
        ON s.userid = c.userid
        AND s.groupid = c.groupid
        AND s.startdatetime = c.startdatetime
      GROUP BY c.userid, CONVERT(DATE, c.completedat)
      ORDER BY c.userid, CONVERT(DATE, c.completedat) ASC
    `);

    const completionRows = completionResult.recordset;
    const statsByUser = new Map();

    for (const row of completionRows) {
      const uid = Number(row.userid);
      const completionDate = row.completionDate ? new Date(row.completionDate) : null;
      const onTimeCount = Number(row.onTimeCount || 0);
      const lateCount = Number(row.lateCount || 0);

      if (!statsByUser.has(uid)) {
        statsByUser.set(uid, {
          dates: [],
          totalOnTimeCompletions: 0,
          totalLateCompletions: 0,
        });
      }

      const userStats = statsByUser.get(uid);
      if (completionDate && onTimeCount > 0) {
        userStats.dates.push(completionDate);
      }
      userStats.totalOnTimeCompletions += onTimeCount;
      userStats.totalLateCompletions += lateCount;
    }

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const leaderboard = usersResult.recordset.map((user) => {
      const uid = Number(user.id);
      const userStats = statsByUser.get(uid) || {
        dates: [],
        totalOnTimeCompletions: 0,
        totalLateCompletions: 0,
      };

      const dates = userStats.dates
        .map((date) => {
          const normalized = new Date(date);
          normalized.setHours(0, 0, 0, 0);
          return normalized;
        })
        .sort((left, right) => left.getTime() - right.getTime());

      let longestStreak = 0;
      let tempStreak = 0;
      let lastStreakDate = null;

      for (let i = 0; i < dates.length; i++) {
        const current = dates[i];
        if (i === 0) {
          tempStreak = 1;
          lastStreakDate = current;
          continue;
        }

        const prev = dates[i - 1];
        const daysDiff = Math.floor((current.getTime() - prev.getTime()) / (1000 * 60 * 60 * 24));

        if (daysDiff === 1) {
          tempStreak++;
          lastStreakDate = current;
        } else if (daysDiff > 1) {
          longestStreak = Math.max(longestStreak, tempStreak);
          tempStreak = 1;
          lastStreakDate = current;
        }
      }

      longestStreak = Math.max(longestStreak, tempStreak);

      let currentStreak = 0;
      if (lastStreakDate) {
        const daysSinceLastCompletion = Math.floor((today.getTime() - lastStreakDate.getTime()) / (1000 * 60 * 60 * 24));
        if (daysSinceLastCompletion <= 1) {
          currentStreak = tempStreak;
        }
      }

      return {
        userId: uid,
        name: user.name,
        coins: Number(user.coins || 0),
        currentStreak,
        longestStreak,
        totalOnTimeCompletions: userStats.totalOnTimeCompletions,
        totalLateCompletions: userStats.totalLateCompletions,
      };
    });

    leaderboard.sort((left, right) => {
      if (right.coins !== left.coins) {
        return right.coins - left.coins;
      }
      if (right.currentStreak !== left.currentStreak) {
        return right.currentStreak - left.currentStreak;
      }
      if (right.totalOnTimeCompletions !== left.totalOnTimeCompletions) {
        return right.totalOnTimeCompletions - left.totalOnTimeCompletions;
      }
      return left.name.localeCompare(right.name);
    });

    const ranked = leaderboard.map((entry, index) => ({
      rank: index + 1,
      isCurrentUser: entry.userId === userId,
      ...entry,
    }));

    return res.json(ranked);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
