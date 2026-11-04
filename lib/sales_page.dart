import 'package:flutter/material.dart';

import 'api_service.dart';
import 'models.dart';
import 'ui.dart';

enum SalesView { days, customers, products, orders }

const _viewLabels = {
  SalesView.days: 'Por dia',
  SalesView.customers: 'Clientes',
  SalesView.products: 'Produtos',
  SalesView.orders: 'Notas',
};

/// Vendas do período (Relatório de Vendas do ERP).
class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage>
    with AutomaticKeepAliveClientMixin {
  final _api = ApiService.instance;

  Period _period = Period.currentMonth();
  Option? _seller;
  Option? _customer;
  List<Option> _sellers = const [];
  SalesView _view = SalesView.days;

  SalesReport? _report;
  bool _loading = true;
  String? _error;
  int _seq = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSellers();
  }

  Future<void> _loadSellers() async {
    try {
      final s = await _api.sellers();
      if (mounted) setState(() => _sellers = s);
    } catch (_) {
      // Sem lista de vendedores o filtro fica desabilitado.
    }
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.sales(
        period: _period,
        sellerId: _seller?.id,
        customerId: _customer?.id,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _report = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickSeller() async {
    if (_sellers.isEmpty) {
      showSnack(context, 'Lista de vendedores indisponível.', error: true);
      return;
    }
    final picked = await showModalBottomSheet<Option>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          children: [
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Todos os vendedores'),
              onTap: () => Navigator.pop(ctx, const Option('', '')),
            ),
            for (final s in _sellers)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(s.name),
                selected: s.id == _seller?.id,
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _seller = picked.id.isEmpty ? null : picked;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              InputChip(
                avatar: const Icon(Icons.badge_outlined, size: 18),
                label: Text(_seller?.name ?? 'Vendedor: todos'),
                selected: _seller != null,
                onPressed: _pickSeller,
                onDeleted: _seller == null
                    ? null
                    : () {
                        _seller = null;
                        _load();
                      },
              ),
              const SizedBox(width: 8),
              if (_customer != null)
                InputChip(
                  avatar: const Icon(Icons.person, size: 18),
                  label: Text(_customer!.name),
                  selected: true,
                  onDeleted: () {
                    _customer = null;
                    _load();
                  },
                )
              else
                ActionChip(
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: const Text('Cliente: toque em Clientes'),
                  onPressed: () => setState(() => _view = SalesView.customers),
                ),
            ]),
          ),
          ..._content(),
        ],
      ),
    );
  }

  List<Widget> _content() {
    if (_loading) {
      return const [
        SizedBox(height: 120),
        Center(child: CircularProgressIndicator()),
      ];
    }
    if (_error != null) return [ErrorView(_error!, onRetry: _load)];
    final r = _report!;
    final s = r.summary;
    final theme = Theme.of(context);
    return [
      StatsCard([
        StatTile('Faturamento', money(s.amount),
            color: theme.colorScheme.primary),
        StatTile('Notas', '${s.orders}'),
        StatTile('Ticket médio', money(s.averageTicket)),
        StatTile('Itens', qty(s.items)),
        StatTile('Custo', money(s.cost)),
        StatTile('Lucro bruto', money(s.profit),
            color:
                s.profit < 0 ? theme.colorScheme.error : Colors.green.shade700),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: SegmentedButton<SalesView>(
          showSelectedIcon: false,
          segments: [
            for (final v in SalesView.values)
              ButtonSegment(value: v, label: Text(_viewLabels[v]!)),
          ],
          selected: {_view},
          onSelectionChanged: (v) => setState(() => _view = v.first),
        ),
      ),
      ..._viewRows(r),
    ];
  }

  List<Widget> _viewRows(SalesReport r) {
    Widget empty() => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('Nenhuma venda no período.')),
        );
    final theme = Theme.of(context);
    final bold =
        theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600);
    switch (_view) {
      case SalesView.days:
        if (r.byDay.isEmpty) return [empty()];
        final max =
            r.byDay.fold<double>(0, (m, d) => d.amount > m ? d.amount : m);
        return [
          for (final d in r.byDay.reversed)
            ListTile(
              dense: true,
              title: Text(formatDate(d.day)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(
                  value: max == 0 ? 0 : d.amount / max,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(money(d.amount), style: bold),
                  Text('${d.orders} nota${d.orders == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
        ];
      case SalesView.customers:
        if (r.byCustomer.isEmpty) return [empty()];
        return [
          for (final c in r.byCustomer)
            ListTile(
              title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${c.orders} nota${c.orders == 1 ? '' : 's'}'
                  '${c.id != null && _customer == null ? ' · toque para filtrar' : ''}'),
              trailing: Text(money(c.amount), style: bold),
              onTap: c.id == null || _customer != null
                  ? null
                  : () {
                      _customer = Option('${c.id}', c.name);
                      _view = SalesView.orders;
                      _load();
                    },
            ),
        ];
      case SalesView.products:
        if (r.byProduct.isEmpty) return [empty()];
        return [
          for (final p in r.byProduct)
            ListTile(
              title: Text(p.description.isEmpty ? p.sku : p.description,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text([
                if (p.sku.isNotEmpty) p.sku,
                '${qty(p.items)}${p.unit.isEmpty ? '' : ' ${p.unit}'}',
                'lucro ${money(p.profit)}',
              ].join(' · ')),
              trailing: Text(money(p.amount), style: bold),
            ),
        ];
      case SalesView.orders:
        if (r.orders.isEmpty) return [empty()];
        return [
          for (final o in r.orders)
            ListTile(
              title: Text(
                  o.customer.isEmpty ? 'Pedido ${o.number}' : o.customer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Text([
                formatDate(o.date),
                '${o.sourceType == 'BUDGET' ? 'Orçamento' : 'Pedido'} ${o.number}',
                if (o.nfeStatus.isNotEmpty) o.nfeStatus,
              ].join(' · ')),
              trailing: Text(money(o.amount), style: bold),
            ),
        ];
    }
  }
}
