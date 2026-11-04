import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);

  @override
  String toString() => message;
}

/// Cliente das APIs do ERP usadas pelas telas de Contas a Pagar, Contas a
/// Receber e Relatório de Vendas (somente leitura).
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static const defaultServer = 'https://erp.consart.com.br';
  static const _kServer = 'server_url';
  static const _kToken = 'token';
  static const _kUserName = 'user_name';

  String serverUrl = '';
  String? token;
  String? userName;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    serverUrl = p.getString(_kServer) ?? defaultServer;
    token = p.getString(_kToken);
    userName = p.getString(_kUserName);
  }

  Future<void> logout() async {
    token = null;
    userName = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kUserName);
  }

  static String normalizeServer(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    if (serverUrl.isEmpty) {
      throw ApiException('Configure o endereço do servidor.');
    }
    return Uri.parse('$serverUrl$path').replace(queryParameters: query);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (isLoggedIn) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final req = http.Request(method, _uri(path, query))
      ..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    return _execute(req, timeout: timeout);
  }

  Future<http.Response> _raw(http.BaseRequest req, Duration timeout) async {
    try {
      return await http.Response.fromStream(await req.send().timeout(timeout));
    } on TimeoutException {
      throw ApiException('Servidor não respondeu. Verifique a conexão.');
    } catch (_) {
      throw ApiException('Sem conexão com o servidor ($serverUrl).');
    }
  }

  static ApiException _error(http.Response res, Map<String, dynamic> json) {
    if (res.statusCode == 401) {
      return ApiException('Sessão expirada. Saia e entre novamente.', 401);
    }
    var msg = json['message'] ?? json['error'] ?? json['erro'];
    // Algumas rotas mandam o código em "error" e o texto em "message".
    if (msg is String && RegExp(r'^[A-Z0-9_]+$').hasMatch(msg)) {
      final detail = json['detail'];
      if (detail is String && detail.isNotEmpty) msg = '$msg: $detail';
    }
    return ApiException(
      msg is String && msg.isNotEmpty
          ? msg
          : 'Erro na requisição (${res.statusCode}).',
      res.statusCode,
    );
  }

  Future<dynamic> _execute(
    http.BaseRequest req, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final res = await _raw(req, timeout);
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {}
    final json =
        decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _error(res, json);
    }
    if (json['ok'] == false || json['success'] == false) {
      throw _error(res, json);
    }
    return decoded;
  }

  // ── Login ────────────────────────────────────────────────────────────
  Future<void> login(String server, String login, String password) async {
    final url = normalizeServer(server);
    serverUrl = url;
    final json = _map(await _send('POST', '/api/login',
        body: {'login': login.trim(), 'password': password}));
    final t = json['token'];
    if (t is! String || t.isEmpty) {
      throw ApiException('Login sem token na resposta.');
    }
    token = t;
    final user = json['user'];
    userName = user is Map ? (user['name']?.toString() ?? login) : login;

    final p = await SharedPreferences.getInstance();
    await p.setString(_kServer, url);
    await p.setString(_kToken, t);
    await p.setString(_kUserName, userName!);
  }

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

  /// Aceita lista pura ou {rows|data|items|...: [...]}.
  static List<Map<String, dynamic>> _rows(dynamic json) {
    dynamic raw = json;
    if (json is Map) {
      for (final k in ['rows', 'data', 'items']) {
        final v = json[k];
        if (v is List) {
          raw = v;
          break;
        }
        if (v is Map && v['rows'] is List) {
          raw = v['rows'];
          break;
        }
      }
    }
    return (raw is List ? raw : const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  // ── Dados ────────────────────────────────────────────────────────────

  /// Busca todas as páginas (até [maxRows]) para os totais baterem com o
  /// filtro, como a tela do ERP faz com a página inteira.
  Future<PagedResult> _allPages(
    String path,
    Map<String, String> query, {
    int maxRows = 3000,
  }) async {
    const pageSize = 200;
    final rows = <Map<String, dynamic>>[];
    var total = 0;
    for (var page = 1; page <= (maxRows / pageSize).ceil(); page++) {
      final json = await _send('GET', path, query: {
        ...query,
        'page': '$page',
        'pageSize': '$pageSize',
      });
      final chunk = _rows(json);
      total = json is Map ? toInt(json['total']) : chunk.length;
      rows.addAll(chunk);
      if (chunk.length < pageSize || rows.length >= total) break;
    }
    return PagedResult(rows, total < rows.length ? rows.length : total);
  }

  static Map<String, String> _clean(Map<String, String?> q) => {
        for (final e in q.entries)
          if (e.value != null && e.value!.trim().isNotEmpty)
            e.key: e.value!.trim(),
      };

  /// GET /api/accounts-payable (vencimento no período).
  Future<(List<FinTitle>, int)> payables({
    required Period period,
    String? search,
  }) async {
    final r = await _allPages(
      '/api/accounts-payable',
      _clean({
        'fromDueDate': isoDate(period.start),
        'toDueDate': isoDate(period.end),
        'search': search,
        'orderBy': 'due_date asc',
      }),
    );
    return (r.rows.map(FinTitle.payable).toList(), r.total);
  }

  /// GET /api/accounts-receivable. [dateType] = due_date | issue_date.
  Future<(List<FinTitle>, int)> receivables({
    required Period period,
    String dateType = 'due_date',
    String? status,
    String? bankAccountId,
    String? search,
  }) async {
    final r = await _allPages(
      '/api/accounts-receivable',
      _clean({
        'dateType': dateType,
        'fromDate': isoDate(period.start),
        'toDate': isoDate(period.end),
        'status': status,
        'bankAccountId': bankAccountId,
        'search': search,
        'orderBy': dateType,
        'orderDirection': 'asc',
      }),
    );
    return (r.rows.map(FinTitle.receivable).toList(), r.total);
  }

  Future<List<Option>> bankAccounts() async {
    final json = await _send('GET', '/api/accounts-receivable/bank-accounts');
    return _rows(json)
        .map((e) => Option(str(e['id']), str(e['name'])))
        .where((o) => o.id.isNotEmpty)
        .toList();
  }

  /// GET /api/reports/sales (Relatório de Vendas do ERP).
  Future<SalesReport> sales({
    required Period period,
    String? sellerId,
    String? customerId,
  }) async {
    final json = await _send(
      'GET',
      '/api/reports/sales',
      query: _clean({
        'dateStart': isoDate(period.start),
        'dateEnd': isoDate(period.end),
        'sellerId': sellerId,
        'customerId': customerId,
      }),
      timeout: const Duration(seconds: 60),
    );
    return SalesReport.fromJson(_map(json));
  }

  Future<List<Option>> sellers() async {
    final json = await _send('GET', '/api/sellers',
        query: {'active': 'true', 'limit': '500'});
    return _rows(json)
        .map((e) => Option(
              str(e['id'] ?? e['seller_id']),
              str(e['name']).isNotEmpty ? str(e['name']) : str(e['nickname']),
            ))
        .where((o) => o.id.isNotEmpty)
        .toList();
  }
}

class PagedResult {
  final List<Map<String, dynamic>> rows;
  final int total;
  PagedResult(this.rows, this.total);
}
