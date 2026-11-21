import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Formatting helpers shared by the extra screens.
class Fmt {
  const Fmt._();

  static final Map<String, NumberFormat> _cache = {};

  static NumberFormat _currency(String currency) => _cache.putIfAbsent(
      currency,
      () => NumberFormat.simpleCurrency(
          locale: 'en_IE', name: currency.isEmpty ? 'EUR' : currency));

  /// `€1,234.56` (no sign shown for negatives unless [signed]).
  static String money(num value, String currency, {bool signed = false}) {
    final f = _currency(currency).format(value.abs());
    if (value < 0) return '-$f';
    if (signed && value > 0) return '+$f';
    return f;
  }

  /// Parse a plain decimal (`"-11.97"`) or a formatted amount (`"-€1,234.50"`).
  static double? parse(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final direct = double.tryParse(s);
    if (direct != null) return direct;
    final negative = s.contains('-') || (s.startsWith('(') && s.endsWith(')'));
    final cleaned = s.replaceAll(RegExp(r'[^0-9.]'), '');
    final d = double.tryParse(cleaned);
    if (d == null) return null;
    return negative ? -d : d;
  }

  static DateTime? date(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  static String day(dynamic v, {String pattern = 'd MMM yyyy'}) {
    final d = date(v);
    return d == null ? (v?.toString() ?? '') : DateFormat(pattern).format(d);
  }

  static String dateTime(dynamic v) {
    final d = date(v);
    return d == null ? (v?.toString() ?? '-') : DateFormat('d MMM yyyy, HH:mm').format(d);
  }

  static String relativeDay(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (d.year == now.year) return DateFormat('EEEE d MMMM').format(d);
    return DateFormat('EEE d MMMM yyyy').format(d);
  }

  static String iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  static String humanize(String? s) {
    if (s == null || s.isEmpty) return '';
    final t = s.replaceAll('_', ' ');
    return t[0].toUpperCase() + t.substring(1);
  }

  static Color? hexColor(dynamic hex) {
    if (hex == null) return null;
    var s = hex.toString().replaceAll('#', '');
    if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
    if (s.length != 6) return null;
    final v = int.tryParse(s, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  static String bytes(dynamic n) {
    final v = (n is num) ? n.toDouble() : double.tryParse('${n ?? ''}');
    if (v == null) return '-';
    if (v < 1024) return '${v.toInt()} B';
    if (v < 1024 * 1024) return '${(v / 1024).toStringAsFixed(1)} KB';
    return '${(v / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// A transaction as returned by `/api/v1/transactions`, with the display
/// helpers the list and detail screens need.
class Txn {
  Txn(this.json);
  final Map<String, dynamic> json;

  String get id => json['id'].toString();
  String get name => json['name']?.toString() ?? '';
  String get currency => json['currency']?.toString() ?? 'EUR';
  String get dateStr => json['date']?.toString() ?? '';
  DateTime get date => DateTime.tryParse(dateStr) ?? DateTime(1970);
  String? get notes => _s(json['notes']);
  String? get kind => _s(json['kind']);
  bool get excluded => json['excluded'] == true;
  bool get splitParent => json['split_parent'] == true;
  bool get isIncome => json['classification']?.toString() == 'income';

  /// Signed amount in the Sure convention: positive = outflow.
  double get rawAmount =>
      Fmt.parse(json['amount_decimal']) ?? Fmt.parse(json['amount']) ?? 0;

  /// Signed amount from the user's point of view: negative = money out.
  double get displayAmount => -rawAmount;
  double get absAmount => rawAmount.abs();

  Map<String, dynamic>? get account => _m(json['account']);
  String? get accountId => account?['id']?.toString();
  String get accountName => account?['name']?.toString() ?? '';
  Map<String, dynamic>? get category => _m(json['category']);
  String? get categoryId => category?['id']?.toString();
  String? get categoryName => category?['name']?.toString();
  Color? get categoryColor => Fmt.hexColor(category?['color']);
  Map<String, dynamic>? get merchant => _m(json['merchant']);
  String? get merchantId => merchant?['id']?.toString();
  String? get merchantName => merchant?['name']?.toString();
  Map<String, dynamic>? get transfer => _m(json['transfer']);
  List<Map<String, dynamic>> get tags => (json['tags'] is List)
      ? (json['tags'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];

  bool get isTransfer =>
      transfer != null ||
      const {'funds_movement', 'cc_payment', 'loan_payment'}.contains(kind);

  static String? _s(dynamic v) {
    final t = v?.toString().trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static Map<String, dynamic>? _m(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;
}
