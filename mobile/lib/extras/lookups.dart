import 'package:flutter/widgets.dart';

import 'api.dart';

/// Session cache of the small reference lists (accounts, categories, tags,
/// merchants) used by pickers and filters. Call [load] with `force: true`
/// after creating or editing one of them.
class Lookups {
  Lookups._();
  static final Lookups instance = Lookups._();

  List<Map<String, dynamic>> accounts = [];
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> tags = [];
  List<Map<String, dynamic>> merchants = [];
  DateTime? _loadedAt;
  Future<void>? _inflight;

  bool get loaded => _loadedAt != null;

  Future<void> load(BuildContext context, {bool force = false}) {
    if (!force && _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 10)) {
      return Future.value();
    }
    final api = SureApi.of(context);
    return _inflight ??= _load(api).whenComplete(() => _inflight = null);
  }

  Future<void> _load(SureApi api) async {
    final results = await Future.wait([
      api.all('accounts', 'accounts'),
      api.all('categories', 'categories'),
      api.get('tags'),
      api.get('merchants'),
    ]);
    accounts = results[0] as List<Map<String, dynamic>>;
    categories = results[1] as List<Map<String, dynamic>>;
    tags = _list(results[2], 'tags');
    merchants = _list(results[3], 'merchants');
    categories.sort((a, b) => _name(a).toLowerCase().compareTo(_name(b).toLowerCase()));
    tags.sort((a, b) => _name(a).toLowerCase().compareTo(_name(b).toLowerCase()));
    merchants.sort((a, b) => _name(a).toLowerCase().compareTo(_name(b).toLowerCase()));
    _loadedAt = DateTime.now();
  }

  void invalidate() => _loadedAt = null;

  static List<Map<String, dynamic>> _list(dynamic data, String key) {
    final raw = data is List ? data : (data is Map ? (data[key] ?? data['data'] ?? []) : []);
    return (raw as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static String _name(Map<String, dynamic> m) => m['name']?.toString() ?? '';

  Map<String, dynamic>? account(String? id) => _find(accounts, id);
  Map<String, dynamic>? category(String? id) => _find(categories, id);
  Map<String, dynamic>? tag(String? id) => _find(tags, id);
  Map<String, dynamic>? merchant(String? id) => _find(merchants, id);

  static Map<String, dynamic>? _find(List<Map<String, dynamic>> list, String? id) {
    if (id == null) return null;
    for (final m in list) {
      if (m['id']?.toString() == id) return m;
    }
    return null;
  }

  /// Categories ordered parent-first with children right after their parent.
  List<Map<String, dynamic>> categoriesTree() {
    final parents = categories.where((c) => c['parent'] == null).toList();
    final out = <Map<String, dynamic>>[];
    for (final p in parents) {
      out.add(p);
      out.addAll(categories.where((c) =>
          c['parent'] is Map && (c['parent'] as Map)['id']?.toString() == p['id']?.toString()));
    }
    for (final c in categories) {
      if (!out.contains(c)) out.add(c);
    }
    return out;
  }
}
