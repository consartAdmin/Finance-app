import 'package:consart_financeiro/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('money formata em reais', () {
    expect(money(1234.5), 'R\$ 1.234,50');
    expect(money(0), 'R\$ 0,00');
    expect(money(-10), '-R\$ 10,00');
    expect(money(1000000), 'R\$ 1.000.000,00');
    expect(qty(12), '12');
    expect(qty(1.5), '1,50');
  });

  test('datas do ERP', () {
    expect(parseDate('2026-11-04T00:00:00.000Z'), DateTime(2026, 11, 4));
    expect(parseDate('2026-02-28'), DateTime(2026, 2, 28));
    expect(parseDate(null), isNull);
    expect(isoDate(DateTime(2026, 2, 3)), '2026-02-03');
  });

  test('período mensal', () {
    final p = Period.month(2026, 2);
    expect(p.end, DateTime(2026, 2, 28));
    expect(p.shiftMonth(-2).start, DateTime(2025, 12, 1));
    expect(p.label, 'Fevereiro 2026');
  });

  test('situação efetiva: pendente vencido vira vencido', () {
    final today = DateTime(2026, 11, 4);
    expect(effectiveStatus('PENDING', DateTime(2026, 11, 3), today: today),
        TitleStatus.overdue);
    expect(effectiveStatus('PENDING', DateTime(2026, 11, 4), today: today),
        TitleStatus.pending);
    expect(effectiveStatus('PAID', DateTime(2026, 1, 1), today: today),
        TitleStatus.paid);
    expect(effectiveStatus('cancelled', null, today: today),
        TitleStatus.cancelled);
  });

  test('contas a pagar e totais', () {
    final rows = [
      FinTitle.payable({
        'id': 1,
        'supplier_name': 'Fornecedor A',
        'due_date': '2020-01-10',
        'status': 'PENDING',
        'total_value': '100.00',
        'amount_paid': '0',
        'balance': '100.00',
      }),
      FinTitle.payable({
        'id': 2,
        'due_date': '2020-01-10',
        'status': 'PAID',
        'total_value': 50,
        'amount_paid': 50,
        'balance': 0,
      }),
      FinTitle.payable({
        'id': 3,
        'status': 'CANCELLED',
        'total_value': 70,
      }),
    ];
    expect(rows.first.status, TitleStatus.overdue);
    final t = TitleTotals.of(rows);
    expect(t.count, 3);
    expect(t.total, 150);
    expect(t.paid, 50);
    expect(t.open, 100);
    expect(t.overdue, 100);
  });

  test('contas a receber', () {
    final r = FinTitle.receivable({
      'id': 9,
      'customer_name': 'Cliente B',
      'value': '200.5',
      'paid_value': '50.5',
      'due_date': '2999-01-01',
      'status': 'PENDING',
      'account_bank': 'Itaú',
    });
    expect(r.balance, 150);
    expect(r.status, TitleStatus.pending);
    expect(r.bank, 'Itaú');
  });

  test('relatório de vendas', () {
    final r = SalesReport.fromJson({
      'summary': {
        'orders_count': '2',
        'total_items': '3',
        'total_amount': '300.00',
        'total_cost': '120',
        'gross_profit': '180',
      },
      'byDay': [
        {'day': '2026-11-02', 'orders_count': 1, 'total_amount': 100},
        {'day': '2026-11-01', 'orders_count': 1, 'total_amount': 200},
      ],
      'byCustomer': [
        {
          'customer_id': 5,
          'customer_name': 'X',
          'orders_count': 1,
          'total_amount': 100
        },
        {
          'customer_id': null,
          'customer_name': '',
          'orders_count': 1,
          'total_amount': 200
        },
      ],
      'byProduct': [],
      'orders': [
        {
          'order_number': '10',
          'issued_date': '2026-11-01',
          'total_amount': 200
        },
      ],
    });
    expect(r.summary.amount, 300);
    expect(r.summary.averageTicket, 150);
    expect(r.byDay.first.day, DateTime(2026, 11, 1));
    expect(r.byCustomer.first.name, 'Sem cliente');
    expect(r.orders.single.number, '10');
  });
}
