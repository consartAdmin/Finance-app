import 'package:flutter/material.dart';

import 'api_service.dart';
import 'models.dart';
import 'ui.dart';

enum TitleKind { payable, receivable }

/// Filtro de situação (aplicado no app, sobre a lista do período).
enum StatusFilter { all, open, overdue, paid }

const _statusFilterLabels = {
  StatusFilter.all: 'Todos',
  StatusFilter.open: 'Em aberto',
  StatusFilter.overdue: 'Vencidos',
  StatusFilter.paid: 'Pagos',
};

bool matchesStatus(FinTitle t, StatusFilter f) {
  switch (f) {
    case StatusFilter.all:
      return true;
    case StatusFilter.open:
      return t.isOpen;
    case StatusFilter.overdue:
      return t.status == TitleStatus.overdue;
    case StatusFilter.paid:
      return t.status == TitleStatus.paid;
  }
}

/// Contas a pagar ou a receber: período, situação, busca e totais.
class TitlesPage extends StatefulWidget {
  final TitleKind kind;
  const TitlesPage({super.key, required this.kind});

  @override
  State<TitlesPage> createState() => _TitlesPageState();
}

class _TitlesPageState extends State<TitlesPage>
    with AutomaticKeepAliveClientMixin {
  final _api = ApiService.instance;

  Period _period = Period.currentMonth();
  StatusFilter _status = StatusFilter.all;
  String _search = '';
  String _dateType = 'due_date'; // só contas a receber
  String? _bankId; // só contas a receber
  List<Option> _banks = const [];

  List<FinTitle> _rows = const [];
  int _serverTotal = 0;
  bool _loading = true;
  String? _error;
  int _seq = 0;

  bool get _payable => widget.kind == TitleKind.payable;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    if (!_payable) _loadBanks();
  }

  Future<void> _loadBanks() async {
    try {
      final b = await _api.bankAccounts();
      if (mounted) setState(() => _banks = b);
    } catch (_) {
      // Filtro de banco é opcional; segue sem ele.
    }
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (rows, total) = _payable
          ? await _api.payables(period: _period, search: _search)
          : await _api.receivables(
              period: _period,
              dateType: _dateType,
              bankAccountId: _bankId,
              search: _search,
            );
      if (!mounted || seq != _seq) return;
      rows.sort((a, b) {
        final da = (_dateType == 'issue_date' ? a.issueDate : a.dueDate) ??
            DateTime(0);
        final db = (_dateType == 'issue_date' ? b.issueDate : b.dueDate) ??
            DateTime(0);
        final c = da.compareTo(db);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
      setState(() {
        _rows = rows;
        _serverTotal = total;
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

  void _setPeriod(Period p) {
    _period = p;
    _load();
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filtrar data por',
                    style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'due_date', label: Text('Vencimento')),
                    ButtonSegment(value: 'issue_date', label: Text('Emissão')),
                  ],
                  selected: {_dateType},
                  onSelectionChanged: (s) {
                    setSheet(() => _dateType = s.first);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: _bankId,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Conta bancária'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas')),
                    const DropdownMenuItem(
                        value: 'NONE', child: Text('Sem conta bancária')),
                    for (final b in _banks)
                      DropdownMenuItem(value: b.id, child: Text(b.name)),
                  ],
                  onChanged: (v) => setSheet(() => _bankId = v),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44)),
                  child: const Text('Aplicar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) _load();
  }

  void _openDetail(FinTitle t) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(children: [
              Expanded(
                child: Text(t.party.isEmpty ? 'Título ${t.id}' : t.party,
                    style: Theme.of(ctx).textTheme.titleLarge),
              ),
              StatusChip(t.status),
            ]),
            const SizedBox(height: 12),
            InfoRow('Valor', money(t.total)),
            InfoRow(_payable ? 'Pago' : 'Recebido', money(t.paid)),
            InfoRow('Em aberto', money(t.balance)),
            InfoRow('Vencimento', formatDate(t.dueDate)),
            InfoRow('Emissão', formatDate(t.issueDate)),
            InfoRow(_payable ? 'Pagamento' : 'Recebimento',
                formatDate(t.paymentDate)),
            InfoRow('Nota', t.invoiceNumber),
            InfoRow('Documento', t.documentNumber),
            InfoRow('Descrição', t.description),
            InfoRow(_payable ? 'Categoria' : 'Tipo de documento', t.category),
            InfoRow('Forma de pagamento', t.paymentMethod),
            InfoRow('Conta bancária', t.bank),
            InfoRow('Observações', t.notes),
            InfoRow('Código', '${t.id}'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final shown = _rows.where((t) => matchesStatus(t, _status)).toList();
    final totals = TitleTotals.of(shown);
    final paidLabel = _payable ? 'Pago' : 'Recebido';

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          Expanded(
            child: SearchField(
              hint: _payable
                  ? 'Fornecedor, nota, documento...'
                  : 'Cliente, nota, documento...',
              onSubmit: (v) {
                _search = v.trim();
                _load();
              },
            ),
          ),
          if (!_payable)
            IconButton(
              tooltip: 'Mais filtros',
              onPressed: _openFilters,
              icon: Badge(
                isLabelVisible: _dateType != 'due_date' || _bankId != null,
                child: const Icon(Icons.tune),
              ),
            ),
        ]),
      ),
      PeriodBar(period: _period, onChanged: _setPeriod),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          for (final f in StatusFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f == StatusFilter.paid && !_payable
                    ? 'Recebidos'
                    : _statusFilterLabels[f]!),
                selected: _status == f,
                onSelected: (_) => setState(() => _status = f),
              ),
            ),
        ]),
      ),
      if (!_loading && _error == null)
        StatsCard([
          StatTile('Títulos', '${totals.count}'),
          StatTile('Valor total', money(totals.total)),
          StatTile(paidLabel, money(totals.paid), color: Colors.green.shade700),
          StatTile('Em aberto', money(totals.open),
              color: totals.overdue > 0 ? theme.colorScheme.error : null),
          if (totals.overdue > 0)
            StatTile('Vencido', money(totals.overdue),
                color: theme.colorScheme.error),
        ]),
      if (!_loading && _serverTotal > _rows.length)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Mostrando ${_rows.length} de $_serverTotal títulos. '
            'Use um período menor para ver todos.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      Expanded(child: _body(shown)),
    ]);
  }

  Widget _body(List<FinTitle> shown) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: ErrorView(_error!, onRetry: _load));
    }
    if (shown.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: const [
          SizedBox(height: 80),
          Center(child: Text('Nenhum título no filtro.')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: shown.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => _tile(shown[i]),
      ),
    );
  }

  Widget _tile(FinTitle t) {
    final theme = Theme.of(context);
    final date = _dateType == 'issue_date' ? t.issueDate : t.dueDate;
    final sub = [
      if (date != null)
        '${_dateType == 'issue_date' ? 'Emissão' : 'Venc.'} ${formatDate(date)}',
      if (t.invoiceNumber.isNotEmpty) 'NF ${t.invoiceNumber}',
      if (t.invoiceNumber.isEmpty && t.description.isNotEmpty) t.description,
    ].join(' · ');
    return ListTile(
      onTap: () => _openDetail(t),
      title: Text(
          t.party.isEmpty
              ? (t.description.isEmpty ? 'Título ${t.id}' : t.description)
              : t.party,
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(money(t.isOpen ? t.balance : t.total),
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          StatusChip(t.status),
        ],
      ),
    );
  }
}
