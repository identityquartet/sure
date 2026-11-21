import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// One page of a paginated list endpoint. Sure uses two pagination shapes
/// (`pagination: {page,total_pages}` and `meta: {current_page,total_pages}`);
/// both are normalised here.
class ApiPage {
  ApiPage(this.items, this.page, this.totalPages, this.totalCount);
  final List<Map<String, dynamic>> items;
  final int page;
  final int totalPages;
  final int? totalCount;
  bool get hasMore => page < totalPages;
}

/// Thin JSON client over `/api/v1`, sharing the auth state (API key or OAuth
/// token) and proxy headers of the upstream app.
class SureApi {
  SureApi(this._auth, {http.Client? client}) : _client = client ?? http.Client();

  factory SureApi.of(BuildContext context) =>
      SureApi(context.read<AuthProvider>());

  final AuthProvider _auth;
  final http.Client _client;
  static const _timeout = Duration(seconds: 45);

  Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await _auth.getValidAccessToken();
    if (token == null && !ApiConfig.isApiKeyAuth) {
      throw ApiException('Not signed in', status: 401);
    }
    return {
      ...ApiConfig.getAuthHeaders(token ?? ''),
      if (json) 'Content-Type': 'application/json',
    };
  }

  Uri uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse('${ApiConfig.baseUrl}/api/v1/$path');
    if (query == null || query.isEmpty) return base;
    final q = <String, dynamic>{};
    query.forEach((k, v) {
      if (v == null) return;
      if (v is List) {
        if (v.isEmpty) return;
        q[k.endsWith('[]') ? k : '$k[]'] = v.map((e) => e.toString()).toList();
      } else if (v.toString().isNotEmpty) {
        q[k] = v.toString();
      }
    });
    return base.replace(queryParameters: q);
  }

  dynamic _decode(http.Response r) {
    final body = r.body.trim();
    dynamic data;
    if (body.isNotEmpty) {
      try {
        data = jsonDecode(body);
      } catch (_) {
        data = null;
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return data;
    throw ApiException(_errorText(data, r), status: r.statusCode);
  }

  String _errorText(dynamic data, http.Response r) {
    if (r.statusCode == 401) return 'Unauthorized (check your API key / login)';
    if (r.statusCode == 403 && data is! Map) return 'Forbidden';
    if (data is Map) {
      final parts = <String>[];
      final msg = data['message'] ?? data['error'];
      if (msg != null) parts.add(msg.toString());
      final errors = data['errors'];
      if (errors is List && errors.isNotEmpty) {
        parts.add(errors.map((e) => e.toString()).join('; '));
      } else if (errors is Map && errors.isNotEmpty) {
        parts.add(errors.entries
            .map((e) => '${e.key} ${e.value is List ? (e.value as List).join(', ') : e.value}')
            .join('; '));
      }
      if (parts.isNotEmpty) return parts.toSet().join(': ');
    }
    return 'Request failed (HTTP ${r.statusCode})';
  }

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) async {
    final r = await _client
        .get(uri(path, query), headers: await _headers())
        .timeout(_timeout);
    return _decode(r);
  }

  Future<dynamic> post(String path, [Object? body]) async {
    final r = await _client
        .post(uri(path),
            headers: await _headers(), body: body == null ? null : jsonEncode(body))
        .timeout(_timeout);
    return _decode(r);
  }

  Future<dynamic> patch(String path, Object body) async {
    final r = await _client
        .patch(uri(path), headers: await _headers(), body: jsonEncode(body))
        .timeout(_timeout);
    return _decode(r);
  }

  Future<dynamic> delete(String path) async {
    final r = await _client
        .delete(uri(path), headers: await _headers())
        .timeout(_timeout);
    return _decode(r);
  }

  Future<Uint8List> download(String path) async {
    final r = await _client
        .get(uri(path), headers: await _headers(json: false))
        .timeout(const Duration(minutes: 5));
    if (r.statusCode >= 200 && r.statusCode < 300) return r.bodyBytes;
    dynamic data;
    try {
      data = jsonDecode(r.body);
    } catch (_) {}
    throw ApiException(_errorText(data, r), status: r.statusCode);
  }

  /// Fetch one page of a list endpoint. [key] is the array key (`transactions`,
  /// `data`, ...); a bare JSON array is accepted too.
  Future<ApiPage> page(String path, String key,
      {int page = 1, int perPage = 50, Map<String, dynamic>? query}) async {
    final data = await get(path, {...?query, 'page': page, 'per_page': perPage});
    if (data is List) {
      return ApiPage(_maps(data), 1, 1, data.length);
    }
    final map = data as Map<String, dynamic>;
    final items = _maps(map[key] ?? map['data'] ?? const []);
    final meta = (map['pagination'] ?? map['meta']) as Map<String, dynamic>?;
    final current = _int(meta?['page'] ?? meta?['current_page']) ?? page;
    final total = _int(meta?['total_pages']) ?? current;
    return ApiPage(items, current, total, _int(meta?['total_count']));
  }

  /// Fetch every page of a list endpoint (for small lookup lists).
  Future<List<Map<String, dynamic>>> all(String path, String key,
      {Map<String, dynamic>? query, int perPage = 100, int maxPages = 50}) async {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    var p = 1;
    while (p <= maxPages) {
      final res = await page(path, key, page: p, perPage: perPage, query: query);
      for (final item in res.items) {
        final id = item['id']?.toString();
        if (id == null || seen.add(id)) out.add(item);
      }
      if (!res.hasMore || res.items.isEmpty) break;
      p++;
    }
    return out;
  }

  static List<Map<String, dynamic>> _maps(dynamic list) => (list as List)
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  static int? _int(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}');
}
