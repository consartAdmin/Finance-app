// Modelos e formatação do app Financeiro.

double toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty) return 0;
  return double.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.')) ?? 0;
}

int toInt(dynamic v) => toDouble(v).round();

String str(dynamic v) => v == null ? '' : v.toString().trim();

/// Datas do ERP chegam como "2026-11-04" ou "2026-11-04T00:00:00.000Z".
DateTime? parseDate(dynamic v) {
  final s = str(v);
  if (s.length < 10) return null;
  final d = DateTime.tryParse(s.substring(0, 10));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String formatDate(DateTime? d) =>
    d == null ? '' : '${_two(d.day)}/${_two(d.month)}/${d.year}';

String _two(int n) => n.toString().padLeft(2, '0');

const monthNames = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

/// R$ 1.234,56
String money(double v) {
  final neg = v < 0;
  final cents = (v.abs() * 100).round();
  final intPart = (cents ~/ 100).toString();
  final dec = (cents % 100).toString().padLeft(2, '0');
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  return '${neg ? '-' : ''}R\$ $buf,$dec';
}

/// 1.234 ou 1.234,5
String qty(double v) {
  if (v == v.roundToDouble()) {
    return money(v).replaceFirst('R\$ ', '').replaceFirst(',00', '');
  }
  return money(v).replaceFirst('R\$ ', '');
}

// ── Período ──────────────────────────────────────────────────────────────

class Period {
  final DateTime start;
  final DateTime end;

  /// Ano/mês quando o período é um mês inteiro.
  final bool isMonth;

  const Period(this.start, this.end, {this.isMonth = false});

  factory Period.month(int year, int month) => Period(
        DateTime(year, month, 1),
        DateTime(year, month + 1, 0),
        isMonth: true,
      );

  factory Period.currentMonth() {
    final now = DateTime.now();
    return Period.month(now.year, now.month);
  }

  Period shiftMonth(int delta) {
    return Period.month(start.year, start.month + delta);
  }

  String get label => isMonth
      ? '${monthNames[start.month - 1]} ${start.year}'
      : '${formatDate(start)} a ${formatDate(end)}';
}

// ── Situação dos títulos ─────────────────────────────────────────────────

enum TitleStatus { pending, overdue, partial, paid, cancelled }

const statusLabels = {
  TitleStatus.pending: 'Pendente',
  TitleStatus.overdue: 'Vencido',
  TitleStatus.partial: 'Parcial',
  TitleStatus.paid: 'Pago',
  TitleStatus.cancelled: 'Cancelado',
};

const statusCodes = {
  TitleStatus.pending: 'PENDING',
  TitleStatus.overdue: 'OVERDUE',
  TitleStatus.partial: 'PARTIAL',
  TitleStatus.paid: 'PAID',
  TitleStatus.cancelled: 'CANCELLED',
};

/// Igual ao ERP: pendente com vencimento passado conta como vencido.
TitleStatus effectiveStatus(dynamic raw, DateTime? due, {DateTime? today}) {
  final s = str(raw).toUpperCase();
  final t = today ?? DateTime.now();
  final day = DateTime(t.year, t.month, t.day);
  switch (s) {
    case 'PAID':
    case 'PAGO':
    case 'RECEIVED':
      return TitleStatus.paid;
    case 'CANCELLED':
    case 'CANCELED':
    case 'CANCELADO':
      return TitleStatus.cancelled;
    case 'OVERDUE':
    case 'VENCIDO':
      return TitleStatus.overdue;
    case 'PARTIAL':
    case 'PARCIAL':
      return due != null && due.isBefore(day)
          ? TitleStatus.overdue
          : TitleStatus.partial;
    default:
      return due != null && due.isBefore(day)
          ? TitleStatus.overdue
          : TitleStatus.pending;
  }
}

/// Título de contas a pagar ou a receber.
class FinTitle {
  final int id;
  final String party; // fornecedor ou cliente
  final String invoiceNumber;
  final String documentNumber;
  final String description;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final DateTime? paymentDate;
  final TitleStatus status;
  final double total;
  final double paid;
  final double balance;
  final String bank;
  final String category;
  final String paymentMethod;
  final String notes;
  final Map<String, dynamic> raw;

  FinTitle({
    required this.id,
    required this.party,
    required this.invoiceNumber,
    required this.documentNumber,
    required this.description,
    required this.issueDate,
    required this.dueDate,
    required this.paymentDate,
    required this.status,
    required this.total,
    required this.paid,
    required this.balance,
    required this.bank,
    required this.category,
    required this.paymentMethod,
    required this.notes,
    required this.raw,
  });

  bool get isOpen =>
      status != TitleStatus.paid && status != TitleStatus.cancelled;

  /// Linha de /api/accounts-payable.
  factory FinTitle.payable(Map<String, dynamic> j) {
    final total = toDouble(j['total_value']);
    final paid = toDouble(j['amount_paid']);
    final due = parseDate(j['due_date']);
    final status = effectiveStatus(j['status'], due);
    return FinTitle(
      id: toInt(j['id']),
      party: str(j['supplier_name']),
      invoiceNumber: str(j['invoice_number']),
      documentNumber: str(j['document_number']),
      description: str(j['description']),
      issueDate: parseDate(j['issue_date']),
      dueDate: due,
      paymentDate: parseDate(j['payment_date']),
      status: status,
      total: total,
      paid: paid,
      balance: status == TitleStatus.cancelled
          ? 0
          : (j['balance'] != null ? toDouble(j['balance']) : total - paid),
      bank: '',
      category: [str(j['category_name']), str(j['subcategory_name'])]
          .where((e) => e.isNotEmpty)
          .join(' / '),
      paymentMethod: str(j['payment_method_name']),
      notes: str(j['notes']),
      raw: j,
    );
  }

  /// Linha de /api/accounts-receivable.
  factory FinTitle.receivable(Map<String, dynamic> j) {
    final total = toDouble(j['value']);
    final paid = toDouble(j['paid_value'] ?? j['amount_paid']);
    final due = parseDate(j['due_date']);
    final status = effectiveStatus(j['status'], due);
    final open = total - paid;
    return FinTitle(
      id: toInt(j['id']),
      party: str(j['customer_name']),
      invoiceNumber: str(j['invoice_number']),
      documentNumber: str(j['document_number']),
      description: str(j['description']),
      issueDate: parseDate(j['issue_date']),
      dueDate: due,
      paymentDate: parseDate(j['payment_date']),
      status: status,
      total: total,
      paid: paid,
      balance: status == TitleStatus.cancelled || status == TitleStatus.paid
          ? 0
          : (open < 0 ? 0 : open),
      bank: str(j['account_bank']),
      category: str(j['document_type_name']),
      paymentMethod: '',
      notes: str(j['notes']),
      raw: j,
    );
  }
}

class TitleTotals {
  final int count;
  final double total;
  final double paid;
  final double open;
  final double overdue;

  const TitleTotals(this.count, this.total, this.paid, this.open, this.overdue);

  factory TitleTotals.of(Iterable<FinTitle> rows) {
    var c = 0;
    double t = 0, p = 0, o = 0, v = 0;
    for (final r in rows) {
      c++;
      if (r.status == TitleStatus.cancelled) continue;
      t += r.total;
      p += r.paid;
      o += r.balance;
      if (r.status == TitleStatus.overdue) v += r.balance;
    }
    return TitleTotals(c, t, p, o, v);
  }
}

// ── Vendas (/api/reports/sales) ──────────────────────────────────────────

class SalesSummary {
  final int orders;
  final double items;
  final double amount;
  final double cost;
  final double profit;

  const SalesSummary(
      this.orders, this.items, this.amount, this.cost, this.profit);

  factory SalesSummary.fromJson(Map<String, dynamic> j) => SalesSummary(
        toInt(j['orders_count']),
        toDouble(j['total_items']),
        toDouble(j['total_amount']),
        toDouble(j['total_cost']),
        toDouble(j['gross_profit']),
      );

  double get averageTicket => orders == 0 ? 0 : amount / orders;
}

class SalesDay {
  final DateTime? day;
  final int orders;
  final double amount;
  SalesDay(this.day, this.orders, this.amount);
}

class SalesCustomer {
  final int? id;
  final String name;
  final int orders;
  final double amount;
  SalesCustomer(this.id, this.name, this.orders, this.amount);
}

class SalesProduct {
  final String sku;
  final String description;
  final String unit;
  final double items;
  final double amount;
  final double profit;
  SalesProduct(this.sku, this.description, this.unit, this.items, this.amount,
      this.profit);
}

class SalesOrder {
  final String number;
  final String sourceType;
  final String nfeStatus;
  final DateTime? date;
  final String customer;
  final double items;
  final double amount;
  final double profit;
  SalesOrder(this.number, this.sourceType, this.nfeStatus, this.date,
      this.customer, this.items, this.amount, this.profit);
}

class SalesReport {
  final SalesSummary summary;
  final List<SalesDay> byDay;
  final List<SalesCustomer> byCustomer;
  final List<SalesProduct> byProduct;
  final List<SalesOrder> orders;

  SalesReport(
      this.summary, this.byDay, this.byCustomer, this.byProduct, this.orders);

  static List<Map<String, dynamic>> _list(dynamic v) => (v is List ? v : [])
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();

  factory SalesReport.fromJson(Map<String, dynamic> j) {
    final s = j['summary'];
    return SalesReport(
      SalesSummary.fromJson(
          s is Map ? s.cast<String, dynamic>() : <String, dynamic>{}),
      _list(j['byDay'])
          .map((e) => SalesDay(parseDate(e['day']), toInt(e['orders_count']),
              toDouble(e['total_amount'])))
          .toList()
        ..sort(
            (a, b) => (a.day ?? DateTime(0)).compareTo(b.day ?? DateTime(0))),
      _list(j['byCustomer'])
          .map((e) => SalesCustomer(
              e['customer_id'] == null ? null : toInt(e['customer_id']),
              str(e['customer_name']).isEmpty
                  ? 'Sem cliente'
                  : str(e['customer_name']),
              toInt(e['orders_count']),
              toDouble(e['total_amount'])))
          .toList()
        ..sort((a, b) => b.amount.compareTo(a.amount)),
      _list(j['byProduct'])
          .map((e) => SalesProduct(
              str(e['product_sku']),
              str(e['product_description']),
              str(e['product_unit']),
              toDouble(e['total_items']),
              toDouble(e['total_amount']),
              toDouble(e['gross_profit'])))
          .toList()
        ..sort((a, b) => b.amount.compareTo(a.amount)),
      _list(j['orders'])
          .map((e) => SalesOrder(
              str(e['order_number']),
              str(e['source_type']),
              str(e['nfe_status']),
              parseDate(e['issued_date']),
              str(e['customer_name']),
              toDouble(e['total_items']),
              toDouble(e['total_amount']),
              toDouble(e['gross_profit'])))
          .toList()
        ..sort(
            (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0))),
    );
  }
}

/// Item simples de lista (conta bancária, vendedor).
class Option {
  final String id;
  final String name;
  const Option(this.id, this.name);
}
