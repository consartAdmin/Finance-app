import 'package:flutter/material.dart';

import 'api_service.dart';
import 'models.dart';
import 'ui.dart';

/// Tela inicial: resumo do período de contas a pagar, a receber e vendas.
class DashboardPage extends StatefulWidget {
  /// Abre a aba: 1 = a pagar, 2 = a receber, 3 = vendas.
  final ValueChanged<int> onOpen;
  const DashboardPage({super.key, required this.onOpen});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _Block<T> {
  T? data;
  String? error;
  bool loading = true;
}

class _DashboardPageState extends State<DashboardPage>
    with AutomaticKeepAliveClientMixin {
  final _api = ApiService.instance;
  Period _period = Period.currentMonth();

  final _pay = _Block<List<FinTitle>>();
  final _rec = _Block<List<FinTitle>>();
  final _sales = _Block<SalesReport>();
  int _seq = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      for (final b in [_pay, _rec, _sales]) {
        b.loading = true;
        b.error = null;
      }
    });
    Future<void> run<T>(_Block<T> b, Future<T> Function() f) async {
      try {
        final v = await f();
        if (!mounted || seq != _seq) return;
        setState(() {
          b.data = v;
          b.loading = false;
        });
      } catch (e) {
        if (!mounted || seq != _seq) return;
        setState(() {
          b.error = e.toString();
          b.loading = false;
        });
      }
    }

    await Future.wait([
      run(_pay, () async => (await _api.payables(period: _period)).$1),
      run(_rec, () async => (await _api.receivables(period: _period)).$1),
      run(_sales, () => _api.sales(period: _period)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final pay = _pay.data == null ? null : TitleTotals.of(_pay.data!);
    final rec = _rec.data == null ? null : TitleTotals.of(_rec.data!);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          PeriodBar(
            period: _period,
            onChanged: (p) {
              _period = p;
              _load();
            },
          ),
          if (pay != null && rec != null) _BalanceCard(pay: pay, rec: rec),
          _TitlesCard(
            title: 'Contas a pagar',
            icon: Icons.call_made,
            block: _pay,
            paidLabel: 'Pago',
            onTap: () => widget.onOpen(1),
            onRetry: _load,
          ),
          _TitlesCard(
            title: 'Contas a receber',
            icon: Icons.call_received,
            block: _rec,
            paidLabel: 'Recebido',
            onTap: () => widget.onOpen(2),
            onRetry: _load,
          ),
          _SalesCard(
            block: _sales,
            onTap: () => widget.onOpen(3),
            onRetry: _load,
          ),
        ],
      ),
    );
  }
}

class _DashCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget child;
  const _DashCard({
    required this.title,
    required this.icon,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (onTap != null)
                  Icon(Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant),
              ]),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

Widget _state(_Block b, VoidCallback onRetry, Widget Function() ok) {
  if (b.loading) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(child: CircularProgressIndicator()),
    );
  }
  if (b.error != null) {
    return Row(children: [
      Expanded(child: Text(b.error!)),
      TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
    ]);
  }
  return ok();
}

/// Previsão do período: a receber em aberto menos a pagar em aberto.
class _BalanceCard extends StatelessWidget {
  final TitleTotals pay;
  final TitleTotals rec;
  const _BalanceCard({required this.pay, required this.rec});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = rec.open - pay.open;
    final good = net >= 0;
    final color = good ? Colors.green.shade700 : theme.colorScheme.error;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo previsto (a receber − a pagar em aberto)',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(money(net),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: color)),
            ),
            const SizedBox(height: 10),
            _SplitBar(
              left: rec.open,
              right: pay.open,
              leftColor: Colors.green.shade600,
              rightColor: theme.colorScheme.error,
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text('A receber ${money(rec.open)}',
                    style: theme.textTheme.bodySmall),
              ),
              Text('A pagar ${money(pay.open)}',
                  style: theme.textTheme.bodySmall),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SplitBar extends StatelessWidget {
  final double left;
  final double right;
  final Color leftColor;
  final Color rightColor;
  const _SplitBar({
    required this.left,
    required this.right,
    required this.leftColor,
    required this.rightColor,
  });

  @override
  Widget build(BuildContext context) {
    final sum = left + right;
    final l = sum <= 0 ? 1 : (left / sum * 1000).round().clamp(1, 999);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: l, child: ColoredBox(color: leftColor)),
          const SizedBox(width: 2),
          Expanded(
              flex: sum <= 0 ? 1 : 1000 - l,
              child: ColoredBox(color: rightColor)),
        ]),
      ),
    );
  }
}

class _TitlesCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final _Block<List<FinTitle>> block;
  final String paidLabel;
  final VoidCallback onTap;
  final VoidCallback onRetry;
  const _TitlesCard({
    required this.title,
    required this.icon,
    required this.block,
    required this.paidLabel,
    required this.onTap,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _DashCard(
      title: title,
      icon: icon,
      onTap: onTap,
      child: _state(block, onRetry, () {
        final rows = block.data!;
        final t = TitleTotals.of(rows);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final week = today.add(const Duration(days: 7));
        final soon = rows.where((r) =>
            r.isOpen &&
            r.dueDate != null &&
            !r.dueDate!.isBefore(today) &&
            !r.dueDate!.isAfter(week));
        final soonValue = soon.fold<double>(0, (s, r) => s + r.balance);
        final overdueCount =
            rows.where((r) => r.status == TitleStatus.overdue).length;
        return Column(children: [
          Row(children: [
            Expanded(child: StatTile('Em aberto', money(t.open))),
            Expanded(
              child: StatTile(
                'Vencido${overdueCount > 0 ? ' ($overdueCount)' : ''}',
                money(t.overdue),
                color: t.overdue > 0 ? theme.colorScheme.error : null,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: StatTile(paidLabel, money(t.paid),
                  color: Colors.green.shade700),
            ),
            Expanded(
              child: StatTile(
                  'Vence em 7 dias (${soon.length})', money(soonValue)),
            ),
          ]),
          const SizedBox(height: 10),
          _SplitBar(
            left: t.paid,
            right: t.open,
            leftColor: Colors.green.shade600,
            rightColor: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Text('${t.count} títulos · total ${money(t.total)}',
                  style: theme.textTheme.bodySmall),
            ),
            Text(
                t.total <= 0
                    ? ''
                    : '${(t.paid / t.total * 100).round()}% ${paidLabel.toLowerCase()}',
                style: theme.textTheme.bodySmall),
          ]),
        ]);
      }),
    );
  }
}

class _SalesCard extends StatelessWidget {
  final _Block<SalesReport> block;
  final VoidCallback onTap;
  final VoidCallback onRetry;
  const _SalesCard({
    required this.block,
    required this.onTap,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _DashCard(
      title: 'Vendas',
      icon: Icons.point_of_sale,
      onTap: onTap,
      child: _state(block, onRetry, () {
        final r = block.data!;
        final s = r.summary;
        final top = r.byCustomer.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: StatTile('Faturamento', money(s.amount),
                    color: theme.colorScheme.primary),
              ),
              Expanded(child: StatTile('Notas', '${s.orders}')),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: StatTile('Ticket médio', money(s.averageTicket))),
              Expanded(
                child: StatTile('Lucro bruto', money(s.profit),
                    color: s.profit < 0
                        ? theme.colorScheme.error
                        : Colors.green.shade700),
              ),
            ]),
            if (r.byDay.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Vendas por dia',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              _DayBars(r.byDay),
            ],
            if (top.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Maiores clientes',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              for (final c in top)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(
                      child: Text(c.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Text(money(c.amount),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
            ],
          ],
        );
      }),
    );
  }
}

/// Barras simples do faturamento por dia.
class _DayBars extends StatelessWidget {
  final List<SalesDay> days;
  const _DayBars(this.days);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final max = days.fold<double>(0, (m, d) => d.amount > m ? d.amount : m);
    return SizedBox(
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in days)
            Expanded(
              child: Tooltip(
                message: '${formatDate(d.day)}: ${money(d.amount)}',
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  height: max <= 0 ? 2 : 2 + 54 * (d.amount / max),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
