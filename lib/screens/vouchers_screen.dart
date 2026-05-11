import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/voucher.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';

class VouchersScreen extends StatefulWidget {
  final AuthSession session;
  final int coins;

  const VouchersScreen({super.key, required this.session, required this.coins});

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen> with TickerProviderStateMixin {
  static const Color redDark = Color(0xFFB71C1C);
  static const Color red = Color(0xFFE53935);

  final BackendService _backend = const BackendService();
  late TabController _mainTabs;
  late TabController _catTabs;
  late int _coins;

  List<Voucher> _vouchers = [];
  Set<String> _redeemedIds = {};
  List<Redemption> _history = [];
  bool _loadingStore = true;
  bool _loadingHistory = true;
  String? _storeError;
  String? _historyError;

  final List<String> _categories = ['All', 'Food & Drinks', 'Shopping', 'Entertainment', 'Education', 'Health'];

  @override
  void initState() {
    super.initState();
    _coins = widget.coins;
    _mainTabs = TabController(length: 2, vsync: this);
    _catTabs = TabController(length: _categories.length, vsync: this);
    _loadStore();
    _loadHistory();
  }

  @override
  void dispose() {
    _mainTabs.dispose();
    _catTabs.dispose();
    super.dispose();
  }

  Future<void> _loadStore() async {
    setState(() { _loadingStore = true; _storeError = null; });
    try {
      final data = await _backend.fetchVouchers(widget.session.token);
      final list = (data['vouchers'] as List<dynamic>?) ?? [];
      final ids = ((data['redeemedIds'] as List<dynamic>?) ?? []).map((e) => e.toString()).toSet();
      if (!mounted) return;
      setState(() {
        _vouchers = list.whereType<Map<String, dynamic>>().map(Voucher.fromJson).toList();
        _redeemedIds = ids;
        _loadingStore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _storeError = e.toString(); _loadingStore = false; });
    }
  }

  Future<void> _loadHistory() async {
    setState(() { _loadingHistory = true; _historyError = null; });
    try {
      final data = await _backend.fetchRedemptionHistory(widget.session.token);
      if (!mounted) return;
      setState(() {
        _history = data.map(Redemption.fromJson).toList();
        _loadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _historyError = e.toString(); _loadingHistory = false; });
    }
  }

  List<Voucher> _filtered(String cat) => cat == 'All' ? _vouchers : _vouchers.where((v) => v.category == cat).toList();

  Future<void> _redeem(Voucher voucher) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _RedeemSheet(voucher: voucher, coins: _coins, canAfford: _coins >= voucher.coinCost, isRedeemed: _redeemedIds.contains(voucher.id)),
    );
    if (confirmed != true || !mounted) return;

    try {
      final result = await _backend.redeemVoucher(token: widget.session.token, voucherId: voucher.id);
      if (!mounted) return;
      final redemption = result['redemption'] as Map<String, dynamic>?;
      setState(() {
        _coins = (result['remainingCoins'] as num?)?.toInt() ?? _coins;
        _redeemedIds.add(voucher.id);
      });
      _loadHistory();

      if (redemption != null) {
        _showQrDialog(redemption['code']?.toString() ?? '', redemption['qrCode']?.toString(), voucher);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text('${voucher.storeName} voucher redeemed!', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: Colors.white))),
          ]),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString(), style: GoogleFonts.manrope(color: Colors.white)),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  void _showQrDialog(String code, String? qrDataUrl, Voucher voucher) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(gradient: LinearGradient(colors: [voucher.brandColor, voucher.brandColor.withValues(alpha: 0.7)]), borderRadius: BorderRadius.circular(16)),
              child: Icon(voucher.icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 14),
            Text(voucher.storeName, style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(color: voucher.brandColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(voucher.discount, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w800, color: voucher.brandColor)),
            ),
            const SizedBox(height: 18),
            if (qrDataUrl != null && qrDataUrl.contains(',')) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(base64Decode(qrDataUrl.split(',').last), width: 200, height: 200),
              ),
              const SizedBox(height: 14),
            ],
            Container(
              width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Text('Redemption Code', style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black45)),
                const SizedBox(height: 4),
                SelectableText(code, style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800, color: redDark, letterSpacing: 1.2)),
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: redDark, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: Text('Done', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showHistoryQr(Redemption r) {
    // Reuse the QR dialog with a fake voucher for icon/color
    final fakeVoucher = Voucher(id: r.voucherId, storeName: r.storeName, description: r.description, coinCost: r.coinCost, category: r.category, icon: r.icon, brandColor: r.brandColor, discount: r.discount, expiryNote: r.expiryNote);
    _showQrDialog(r.code, r.qrCode, fakeVoucher);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 200, pinned: true, backgroundColor: redDark,
            leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [redDark, red, Color(0xFFFF5252)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                child: SafeArea(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Image.asset('assets/coin.png', width: 36, height: 36, fit: BoxFit.contain),
                      const SizedBox(width: 10),
                      Text('$_coins', style: GoogleFonts.playfairDisplay(fontSize: 42, fontWeight: FontWeight.w700, color: Colors.white)),
                    ]),
                    const SizedBox(height: 4),
                    Text('coins available', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.8))),
                  ]),
                ),
              ),
              title: Text('Rewards Store', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 20)),
              centerTitle: true,
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: TabBar(
                controller: _mainTabs,
                indicatorColor: Colors.white, indicatorWeight: 3,
                labelColor: Colors.white, unselectedLabelColor: Colors.white60,
                labelStyle: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700),
                tabs: const [Tab(text: 'Store'), Tab(text: 'My Vouchers')],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _mainTabs,
          children: [_buildStore(), _buildHistory()],
        ),
      ),
    );
  }

  Widget _buildStore() {
    if (_loadingStore) return const Center(child: CircularProgressIndicator());
    if (_storeError != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Unable to load store', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: redDark)),
        const SizedBox(height: 8),
        Text(_storeError!, style: GoogleFonts.manrope(fontSize: 13, color: Colors.black54), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _loadStore, style: ElevatedButton.styleFrom(backgroundColor: redDark, foregroundColor: Colors.white), child: const Text('Retry')),
      ]));
    }

    return Column(children: [
      SizedBox(
        height: 46,
        child: TabBar(
          controller: _catTabs, isScrollable: true, tabAlignment: TabAlignment.start,
          indicatorColor: redDark, labelColor: redDark, unselectedLabelColor: Colors.black45,
          labelStyle: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700),
          tabs: _categories.map((c) => Tab(text: c)).toList(),
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _catTabs,
          children: _categories.map((cat) {
            final list = _filtered(cat);
            if (list.isEmpty) return Center(child: Text('No vouchers here', style: GoogleFonts.manrope(color: Colors.black45)));
            return LayoutBuilder(builder: (ctx, constraints) {
              final cols = constraints.maxWidth > 700 ? 3 : constraints.maxWidth > 440 ? 2 : 1;
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: cols == 1 ? 2.2 : 0.88),
                itemCount: list.length,
                itemBuilder: (_, i) => _VoucherCard(voucher: list[i], isRedeemed: _redeemedIds.contains(list[i].id), canAfford: _coins >= list[i].coinCost, onTap: () => _redeem(list[i])),
              );
            });
          }).toList(),
        ),
      ),
    ]);
  }

  Widget _buildHistory() {
    if (_loadingHistory) return const Center(child: CircularProgressIndicator());
    if (_historyError != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Unable to load history', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: redDark)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _loadHistory, style: ElevatedButton.styleFrom(backgroundColor: redDark, foregroundColor: Colors.white), child: const Text('Retry')),
      ]));
    }
    if (_history.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.receipt_long_rounded, size: 56, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('No redeemed vouchers yet', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black45)),
        const SizedBox(height: 4),
        Text('Redeem vouchers from the Store tab', style: GoogleFonts.manrope(fontSize: 13, color: Colors.black38)),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _history.length,
      itemBuilder: (_, i) {
        final r = _history[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))]),
          child: Material(
            color: Colors.transparent, borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _showHistoryQr(r),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(gradient: LinearGradient(colors: [r.brandColor, r.brandColor.withValues(alpha: 0.7)]), borderRadius: BorderRadius.circular(14)),
                    child: Icon(r.icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.storeName, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A1A))),
                    const SizedBox(height: 2),
                    Text(r.discount, style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: r.brandColor)),
                    const SizedBox(height: 2),
                    Text(r.code, style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black45, letterSpacing: 0.5)),
                  ])),
                  const SizedBox(width: 8),
                  Column(children: [
                    Icon(Icons.qr_code_rounded, size: 28, color: Colors.black26),
                    const SizedBox(height: 4),
                    Text('View', style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black38)),
                  ]),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Voucher Card ─────────────────────────────────────────────────────
class _VoucherCard extends StatelessWidget {
  final Voucher voucher;
  final bool isRedeemed;
  final bool canAfford;
  final VoidCallback onTap;

  const _VoucherCard({required this.voucher, required this.isRedeemed, required this.canAfford, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: voucher.brandColor.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8)), BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Stack(children: [
          Positioned(top: -20, right: -20, child: Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, color: voucher.brandColor.withValues(alpha: 0.06)))),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [voucher.brandColor, voucher.brandColor.withValues(alpha: 0.7)]), borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: voucher.brandColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]),
                  child: Icon(voucher.icon, color: Colors.white, size: 24),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: voucher.brandColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text(voucher.discount, style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w800, color: voucher.brandColor)),
                ),
              ]),
              const SizedBox(height: 14),
              Text(voucher.storeName, style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A1A)), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Expanded(child: Text(voucher.description, style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black54, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis)),
              Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 10), color: const Color(0xFFF0F0F0)),
              Row(children: [
                Image.asset('assets/coin.png', width: 18, height: 18, fit: BoxFit.contain),
                const SizedBox(width: 6),
                Text('${voucher.coinCost}', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFFEF6C00))),
                const Spacer(),
                if (isRedeemed)
                  _badge('Redeemed', Icons.check_circle_rounded, const Color(0xFF2E7D32), const Color(0xFFE8F5E9))
                else if (!canAfford)
                  Text('Not enough coins', style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black38))
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(gradient: LinearGradient(colors: [voucher.brandColor, voucher.brandColor.withValues(alpha: 0.8)]), borderRadius: BorderRadius.circular(20)),
                    child: Text('Redeem', style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _badge(String label, IconData icon, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

// ── Redeem Confirmation Sheet ────────────────────────────────────────
class _RedeemSheet extends StatelessWidget {
  final Voucher voucher;
  final int coins;
  final bool canAfford;
  final bool isRedeemed;

  const _RedeemSheet({required this.voucher, required this.coins, required this.canAfford, required this.isRedeemed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(gradient: LinearGradient(colors: [voucher.brandColor, voucher.brandColor.withValues(alpha: 0.7)]), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: voucher.brandColor.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8))]),
              child: Icon(voucher.icon, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 18),
            Text(voucher.storeName, style: GoogleFonts.playfairDisplay(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(color: voucher.brandColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(voucher.discount, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w800, color: voucher.brandColor)),
            ),
            const SizedBox(height: 14),
            Text(voucher.description, textAlign: TextAlign.center, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black54, height: 1.5)),
            const SizedBox(height: 20),
            // Cost vs balance
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFFE082))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _costCol('Cost', voucher.coinCost, const Color(0xFFEF6C00)),
                Container(width: 1, height: 40, color: const Color(0xFFFFE082)),
                _costCol('Balance', coins, canAfford ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F)),
              ]),
            ),
            if (voucher.expiryNote != null) ...[
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.schedule_rounded, size: 14, color: Colors.black38),
                const SizedBox(width: 6),
                Text(voucher.expiryNote!, style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black45)),
              ]),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity, height: 52,
              child: isRedeemed
                  ? ElevatedButton.icon(onPressed: null, icon: const Icon(Icons.check_circle_rounded), label: Text('Already Redeemed', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700)), style: ElevatedButton.styleFrom(disabledBackgroundColor: const Color(0xFFE8F5E9), disabledForegroundColor: const Color(0xFF2E7D32), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))
                  : ElevatedButton(
                      onPressed: canAfford ? () => Navigator.pop(context, true) : null,
                      style: ElevatedButton.styleFrom(backgroundColor: voucher.brandColor, foregroundColor: Colors.white, disabledBackgroundColor: Colors.grey.shade200, disabledForegroundColor: Colors.grey.shade500, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: canAfford ? 4 : 0),
                      child: Text(canAfford ? 'Confirm Redemption' : 'Not Enough Coins (need ${voucher.coinCost - coins} more)', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ]),
        ),
      ]),
    );
  }

  Widget _costCol(String label, int value, Color color) {
    return Column(children: [
      Text(label, style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black45)),
      const SizedBox(height: 4),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Image.asset('assets/coin.png', width: 20, height: 20),
        const SizedBox(width: 6),
        Text('$value', style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
      ]),
    ]);
  }
}
