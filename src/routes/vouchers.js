const express = require('express');
const QRCode = require('qrcode');
const crypto = require('crypto');
const { sql, getPool } = require('../config/db');

const router = express.Router();

let ensureTablesPromise;

// ── Auto-create tables on first request ──────────────────────────────
async function ensureTables() {
  if (!ensureTablesPromise) {
    const pool = await getPool();
    ensureTablesPromise = pool.request().query(`
      -- Voucher definitions (the store catalogue)
      IF OBJECT_ID('dbo.vouchers', 'U') IS NULL
      BEGIN
        CREATE TABLE dbo.[vouchers] (
          id          NVARCHAR(40)   NOT NULL PRIMARY KEY,
          storeName   NVARCHAR(200)  NOT NULL,
          description NVARCHAR(1000) NOT NULL,
          coinCost    INT            NOT NULL,
          category    NVARCHAR(100)  NOT NULL,
          discount    NVARCHAR(100)  NOT NULL,
          expiryNote  NVARCHAR(200)  NULL,
          iconName    NVARCHAR(100)  NOT NULL DEFAULT 'storefront',
          brandColor  NVARCHAR(10)   NOT NULL DEFAULT 'FF9800',
          active      BIT            NOT NULL DEFAULT 1,
          createdAt   DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
        )
      END

      -- Redemption history
      IF OBJECT_ID('dbo.voucher_redemptions', 'U') IS NULL
      BEGIN
        CREATE TABLE dbo.[voucher_redemptions] (
          id          INT            IDENTITY(1,1) PRIMARY KEY,
          userId      INT            NOT NULL,
          voucherId   NVARCHAR(40)   NOT NULL,
          code        NVARCHAR(100)  NOT NULL,
          qrData      NVARCHAR(MAX)  NULL,
          redeemedAt  DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
          used        BIT            NOT NULL DEFAULT 0,
          usedAt      DATETIME2      NULL
        )
      END
    `);
  }

  await ensureTablesPromise;
}

// ── Seed sample vouchers if table is empty ───────────────────────────
async function seedVouchers(pool) {
  const countResult = await pool.request().query(
    `SELECT COUNT(*) AS cnt FROM dbo.[vouchers]`
  );

  if (countResult.recordset[0].cnt > 0) return;

  const vouchers = [
    { id: 'v1',  storeName: 'Caffein Lab',      description: 'Free hot or iced latte of your choice',   coinCost: 50,  category: 'Food & Drinks',  discount: 'Free Drink', expiryNote: 'Valid for 30 days',  iconName: 'coffee',           brandColor: '0B6B5D' },
    { id: 'v2',  storeName: 'Shawarma Reem',    description: 'Buy 1 Get 1 Free shawarma combo',         coinCost: 35,  category: 'Food & Drinks',  discount: 'BOGO',       expiryNote: 'Valid for 14 days',  iconName: 'fastfood',         brandColor: '8E1F1F' },
    { id: 'v3',  storeName: 'Pizza Al Reef',   description: '25% off your next pizza order',           coinCost: 40,  category: 'Food & Drinks',  discount: '25% OFF',    expiryNote: 'Valid for 21 days',  iconName: 'local_pizza',      brandColor: 'C62828' },
    { id: 'v4',  storeName: 'Amazon',           description: '$10 gift card for any purchase',           coinCost: 100, category: 'Shopping',       discount: '$10 Card',   expiryNote: 'No expiry',          iconName: 'shopping_bag',     brandColor: 'FF9900' },
    { id: 'v5',  storeName: 'Nike',             description: '15% off on footwear & apparel',           coinCost: 80,  category: 'Shopping',       discount: '15% OFF',    expiryNote: 'Valid for 60 days',  iconName: 'directions_run',   brandColor: '111111' },
    { id: 'v6',  storeName: 'IKEA',             description: '$5 off your next purchase over $25',       coinCost: 45,  category: 'Shopping',       discount: '$5 OFF',     expiryNote: 'Valid for 30 days',  iconName: 'chair',            brandColor: '0051BA' },
    { id: 'v7',  storeName: 'Netflix',          description: '1 month free subscription upgrade',       coinCost: 120, category: 'Entertainment',  discount: '1 Month',    expiryNote: 'One-time use',       iconName: 'movie',            brandColor: 'E50914' },
    { id: 'v8',  storeName: 'Spotify',          description: '2 weeks of Premium free',                 coinCost: 60,  category: 'Entertainment',  discount: '2 Weeks',    expiryNote: 'New users only',     iconName: 'headphones',       brandColor: '1DB954' },
    { id: 'v9',  storeName: 'Cinema',           description: 'Buy 1 Get 1 Free movie ticket',           coinCost: 70,  category: 'Entertainment',  discount: 'BOGO',       expiryNote: 'Valid for 14 days',  iconName: 'theaters',         brandColor: '9C27B0' },
    { id: 'v10', storeName: 'Udemy',            description: 'Any course for $9.99',                    coinCost: 90,  category: 'Education',      discount: '$9.99',      expiryNote: 'Valid for 7 days',   iconName: 'school',           brandColor: 'A435F0' },
    { id: 'v11', storeName: 'Book Store',       description: '20% off any book purchase',               coinCost: 30,  category: 'Education',      discount: '20% OFF',    expiryNote: 'Valid for 30 days',  iconName: 'menu_book',        brandColor: '795548' },
    { id: 'v12', storeName: 'Gym Pass',         description: '1 free day pass at any partner gym',      coinCost: 55,  category: 'Health',         discount: 'Free Day',   expiryNote: 'Valid for 14 days',  iconName: 'fitness_center',   brandColor: 'FF5722' },
  ];

  for (const v of vouchers) {
    await pool.request()
      .input('id',          sql.NVarChar(40),   v.id)
      .input('storeName',   sql.NVarChar(200),  v.storeName)
      .input('description', sql.NVarChar(1000), v.description)
      .input('coinCost',    sql.Int,            v.coinCost)
      .input('category',    sql.NVarChar(100),  v.category)
      .input('discount',    sql.NVarChar(100),  v.discount)
      .input('expiryNote',  sql.NVarChar(200),  v.expiryNote)
      .input('iconName',    sql.NVarChar(100),  v.iconName)
      .input('brandColor',  sql.NVarChar(10),   v.brandColor)
      .query(`
        INSERT INTO dbo.[vouchers]
          (id, storeName, description, coinCost, category, discount, expiryNote, iconName, brandColor)
        VALUES
          (@id, @storeName, @description, @coinCost, @category, @discount, @expiryNote, @iconName, @brandColor)
      `);
  }
}

// ── GET /api/vouchers — list all active vouchers ─────────────────────
router.get('/', async (req, res) => {
  try {
    await ensureTables();
    const pool = await getPool();
    await seedVouchers(pool);

    const userId = Number(req.user?.id);

    const result = await pool.request().query(
      `SELECT id, storeName, description, coinCost, category,
              discount, expiryNote, iconName, brandColor
       FROM dbo.[vouchers]
       WHERE active = 1
       ORDER BY coinCost ASC`
    );

    // Also fetch which vouchers this user has already redeemed
    let redeemedIds = [];
    if (Number.isFinite(userId)) {
      const redeemed = await pool.request()
        .input('userId', sql.Int, userId)
        .query(`SELECT DISTINCT voucherId FROM dbo.[voucher_redemptions] WHERE userId = @userId`);
      redeemedIds = redeemed.recordset.map(r => r.voucherId);
    }

    return res.json({
      vouchers: result.recordset,
      redeemedIds
    });
  } catch (err) {
    console.error('Vouchers list error', err);
    return res.status(500).json({ message: err.message });
  }
});

// ── POST /api/vouchers/:id/redeem — redeem a voucher ─────────────────
router.post('/:id/redeem', async (req, res) => {
  try {
    await ensureTables();
    const userId = Number(req.user?.id);
    if (!Number.isFinite(userId)) {
      return res.status(401).json({ message: 'Unauthorized.' });
    }

    const voucherId = req.params.id;
    const pool = await getPool();

    // 1. Fetch the voucher
    const voucherResult = await pool.request()
      .input('id', sql.NVarChar(40), voucherId)
      .query(`SELECT * FROM dbo.[vouchers] WHERE id = @id AND active = 1`);

    if (voucherResult.recordset.length === 0) {
      return res.status(404).json({ message: 'Voucher not found.' });
    }

    const voucher = voucherResult.recordset[0];

    // 2. Check if already redeemed
    const existingResult = await pool.request()
      .input('userId', sql.Int, userId)
      .input('voucherId', sql.NVarChar(40), voucherId)
      .query(`SELECT TOP 1 id FROM dbo.[voucher_redemptions] WHERE userId = @userId AND voucherId = @voucherId`);

    if (existingResult.recordset.length > 0) {
      return res.status(409).json({ message: 'You have already redeemed this voucher.' });
    }

    // 3. Check coin balance
    const userResult = await pool.request()
      .input('userId', sql.Int, userId)
      .query(`SELECT ISNULL(coins, 0) AS coins FROM dbo.[users] WHERE id = @userId`);

    if (userResult.recordset.length === 0) {
      return res.status(404).json({ message: 'User not found.' });
    }

    const userCoins = Number(userResult.recordset[0].coins);
    if (userCoins < voucher.coinCost) {
      return res.status(400).json({
        message: `Not enough coins. You have ${userCoins} but need ${voucher.coinCost}.`
      });
    }

    // 4. Deduct coins
    await pool.request()
      .input('userId', sql.Int, userId)
      .input('cost', sql.Int, voucher.coinCost)
      .query(`UPDATE dbo.[users] SET coins = coins - @cost WHERE id = @userId`);

    // 5. Generate unique redemption code
    const code = `DRUSH-${voucher.id.toUpperCase()}-${crypto.randomBytes(4).toString('hex').toUpperCase()}`;

    // 6. Generate QR code as base64 data URL
    const qrPayload = JSON.stringify({
      code,
      store: voucher.storeName,
      discount: voucher.discount,
      userId,
      redeemedAt: new Date().toISOString()
    });

    const qrDataUrl = await QRCode.toDataURL(qrPayload, {
      errorCorrectionLevel: 'H',
      width: 300,
      margin: 2,
      color: {
        dark: '#' + voucher.brandColor,
        light: '#FFFFFF'
      }
    });

    // 7. Save redemption
    const insertResult = await pool.request()
      .input('userId',    sql.Int,           userId)
      .input('voucherId', sql.NVarChar(40),  voucherId)
      .input('code',      sql.NVarChar(100), code)
      .input('qrData',    sql.NVarChar(sql.MAX), qrDataUrl)
      .query(`
        INSERT INTO dbo.[voucher_redemptions] (userId, voucherId, code, qrData)
        OUTPUT INSERTED.id, INSERTED.code, INSERTED.redeemedAt
        VALUES (@userId, @voucherId, @code, @qrData)
      `);

    const redemption = insertResult.recordset[0];

    // 8. Fetch updated balance
    const updatedUser = await pool.request()
      .input('userId', sql.Int, userId)
      .query(`SELECT ISNULL(coins, 0) AS coins FROM dbo.[users] WHERE id = @userId`);

    return res.status(201).json({
      message: 'Voucher redeemed successfully!',
      redemption: {
        id: redemption.id,
        code: redemption.code,
        redeemedAt: redemption.redeemedAt,
        qrCode: qrDataUrl,
        storeName: voucher.storeName,
        discount: voucher.discount,
      },
      remainingCoins: Number(updatedUser.recordset[0].coins)
    });
  } catch (err) {
    console.error('Voucher redeem error', err);
    return res.status(500).json({ message: err.message });
  }
});

// ── GET /api/vouchers/history — user's redemption history ────────────
router.get('/history', async (req, res) => {
  try {
    await ensureTables();
    const userId = Number(req.user?.id);
    if (!Number.isFinite(userId)) {
      return res.status(401).json({ message: 'Unauthorized.' });
    }

    const pool = await getPool();

    const result = await pool.request()
      .input('userId', sql.Int, userId)
      .query(`
        SELECT
          r.id,
          r.voucherId,
          r.code,
          r.qrData   AS qrCode,
          r.redeemedAt,
          r.used,
          r.usedAt,
          v.storeName,
          v.description,
          v.coinCost,
          v.category,
          v.discount,
          v.expiryNote,
          v.iconName,
          v.brandColor
        FROM dbo.[voucher_redemptions] r
        INNER JOIN dbo.[vouchers] v ON v.id = r.voucherId
        WHERE r.userId = @userId
        ORDER BY r.redeemedAt DESC
      `);

    return res.json(result.recordset);
  } catch (err) {
    console.error('Voucher history error', err);
    return res.status(500).json({ message: err.message });
  }
});

// ── GET /api/vouchers/history/:id — single redemption detail with QR ─
router.get('/history/:id', async (req, res) => {
  try {
    await ensureTables();
    const userId = Number(req.user?.id);
    if (!Number.isFinite(userId)) {
      return res.status(401).json({ message: 'Unauthorized.' });
    }

    const redemptionId = Number(req.params.id);
    if (!Number.isFinite(redemptionId)) {
      return res.status(400).json({ message: 'Invalid redemption id.' });
    }

    const pool = await getPool();

    const result = await pool.request()
      .input('userId', sql.Int, userId)
      .input('id', sql.Int, redemptionId)
      .query(`
        SELECT
          r.id,
          r.voucherId,
          r.code,
          r.qrData   AS qrCode,
          r.redeemedAt,
          r.used,
          r.usedAt,
          v.storeName,
          v.description,
          v.coinCost,
          v.category,
          v.discount,
          v.expiryNote,
          v.iconName,
          v.brandColor
        FROM dbo.[voucher_redemptions] r
        INNER JOIN dbo.[vouchers] v ON v.id = r.voucherId
        WHERE r.id = @id AND r.userId = @userId
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ message: 'Redemption not found.' });
    }

    return res.json(result.recordset[0]);
  } catch (err) {
    console.error('Voucher detail error', err);
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
