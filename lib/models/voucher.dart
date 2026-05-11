import 'package:flutter/material.dart';

class Voucher {
  final String id;
  final String storeName;
  final String description;
  final int coinCost;
  final String category;
  final IconData icon;
  final Color brandColor;
  final String discount;
  final String? expiryNote;

  const Voucher({
    required this.id,
    required this.storeName,
    required this.description,
    required this.coinCost,
    required this.category,
    required this.icon,
    required this.brandColor,
    required this.discount,
    this.expiryNote,
  });

  factory Voucher.fromJson(Map<String, dynamic> json) {
    return Voucher(
      id: (json['id'] ?? '').toString(),
      storeName: (json['storeName'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      coinCost: (json['coinCost'] as num?)?.toInt() ?? 0,
      category: (json['category'] ?? '').toString(),
      discount: (json['discount'] ?? '').toString(),
      expiryNote: json['expiryNote']?.toString(),
      icon: _iconFromName((json['iconName'] ?? 'storefront').toString()),
      brandColor: _colorFromHex((json['brandColor'] ?? 'FF9800').toString()),
    );
  }

  static IconData _iconFromName(String name) {
    const map = <String, IconData>{
      'coffee': Icons.coffee_rounded,
      'fastfood': Icons.fastfood_rounded,
      'local_pizza': Icons.local_pizza_rounded,
      'shopping_bag': Icons.shopping_bag_rounded,
      'directions_run': Icons.directions_run_rounded,
      'chair': Icons.chair_rounded,
      'movie': Icons.movie_rounded,
      'headphones': Icons.headphones_rounded,
      'theaters': Icons.theaters_rounded,
      'school': Icons.school_rounded,
      'menu_book': Icons.menu_book_rounded,
      'fitness_center': Icons.fitness_center_rounded,
      'storefront': Icons.storefront_rounded,
    };
    return map[name] ?? Icons.storefront_rounded;
  }

  static Color _colorFromHex(String hex) {
    final cleaned = hex.replaceAll('#', '');
    final value = int.tryParse('FF$cleaned', radix: 16) ?? 0xFFFF9800;
    return Color(value);
  }
}

class Redemption {
  final int id;
  final String voucherId;
  final String code;
  final String? qrCode;
  final DateTime redeemedAt;
  final bool used;
  final DateTime? usedAt;
  final String storeName;
  final String description;
  final int coinCost;
  final String category;
  final String discount;
  final String? expiryNote;
  final String iconName;
  final String brandColorHex;

  const Redemption({
    required this.id,
    required this.voucherId,
    required this.code,
    this.qrCode,
    required this.redeemedAt,
    required this.used,
    this.usedAt,
    required this.storeName,
    required this.description,
    required this.coinCost,
    required this.category,
    required this.discount,
    this.expiryNote,
    required this.iconName,
    required this.brandColorHex,
  });

  factory Redemption.fromJson(Map<String, dynamic> json) {
    return Redemption(
      id: (json['id'] as num?)?.toInt() ?? 0,
      voucherId: (json['voucherId'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      qrCode: json['qrCode']?.toString(),
      redeemedAt: DateTime.tryParse(json['redeemedAt']?.toString() ?? '') ??
          DateTime.now(),
      used: json['used'] == true || json['used'] == 1,
      usedAt: json['usedAt'] != null
          ? DateTime.tryParse(json['usedAt'].toString())
          : null,
      storeName: (json['storeName'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      coinCost: (json['coinCost'] as num?)?.toInt() ?? 0,
      category: (json['category'] ?? '').toString(),
      discount: (json['discount'] ?? '').toString(),
      expiryNote: json['expiryNote']?.toString(),
      iconName: (json['iconName'] ?? 'storefront').toString(),
      brandColorHex: (json['brandColor'] ?? 'FF9800').toString(),
    );
  }

  IconData get icon => Voucher._iconFromName(iconName);
  Color get brandColor => Voucher._colorFromHex(brandColorHex);
}
