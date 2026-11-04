import 'package:flutter/material.dart';

import 'models.dart';

void showSnack(BuildContext context, String text, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    duration: Duration(seconds: error ? 6 : 3),
  ));
}

/// Barra de período: mês anterior / próximo, ou período personalizado.
class PeriodBar extends StatelessWidget {
  final Period period;
  final ValueChanged<Period> onChanged;
  const PeriodBar({super.key, required this.period, required this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.today),
            title: const Text('Mês atual'),
            onTap: () => Navigator.pop(ctx, 'month'),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_view_week),
            title: const Text('Próximos 30 dias'),
            onTap: () => Navigator.pop(ctx, 'next30'),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Últimos 30 dias'),
            onTap: () => Navigator.pop(ctx, 'last30'),
          ),
          ListTile(
            leading: const Icon(Icons.date_range),
            title: const Text('Escolher período...'),
            onTap: () => Navigator.pop(ctx, 'custom'),
          ),
        ]),
      ),
    );
    if (!context.mounted || choice == null) return;
    final today = DateTime(now.year, now.month, now.day);
    switch (choice) {
      case 'month':
        onChanged(Period.currentMonth());
      case 'next30':
        onChanged(Period(today, today.add(const Duration(days: 30))));
      case 'last30':
        onChanged(Period(today.subtract(const Duration(days: 30)), today));
      case 'custom':
        final r = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 10),
          lastDate: DateTime(now.year + 10),
          initialDateRange: DateTimeRange(start: period.start, end: period.end),
          helpText: 'Período',
          saveText: 'OK',
        );
        if (r != null) {
          final isWholeMonth = r.start.day == 1 &&
              r.end == DateTime(r.start.year, r.start.month + 1, 0) &&
              r.end.month == r.start.month;
          onChanged(Period(r.start, r.end, isMonth: isWholeMonth));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      IconButton(
        tooltip: 'Mês anterior',
        icon: const Icon(Icons.chevron_left),
        onPressed: () => onChanged(period.isMonth
            ? period.shiftMonth(-1)
            : Period.month(period.start.year, period.start.month - 1)),
      ),
      Expanded(
        child: TextButton.icon(
          onPressed: () => _pick(context),
          icon: const Icon(Icons.calendar_month, size: 18),
          label: Text(period.label, overflow: TextOverflow.ellipsis),
        ),
      ),
      IconButton(
        tooltip: 'Próximo mês',
        icon: const Icon(Icons.chevron_right),
        onPressed: () => onChanged(period.isMonth
            ? period.shiftMonth(1)
            : Period.month(period.start.year, period.start.month + 1)),
      ),
    ]);
  }
}

/// Campo de busca que dispara ao confirmar no teclado ou limpar.
class SearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onSubmit;
  const SearchField({super.key, required this.hint, required this.onSubmit});

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      textInputAction: TextInputAction.search,
      onSubmitted: widget.onSubmit,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _c.clear();
                  setState(() {});
                  widget.onSubmit('');
                },
              ),
      ),
    );
  }
}

/// Bloco de totais (valor grande + legenda).
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const StatTile(this.label, this.value, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600, color: color)),
        ),
      ],
    );
  }
}

/// Cartão com 2 colunas de StatTile.
class StatsCard extends StatelessWidget {
  final List<StatTile> tiles;
  const StatsCard(this.tiles, {super.key});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 12));
      rows.add(Row(children: [
        Expanded(child: tiles[i]),
        const SizedBox(width: 12),
        Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
      ]));
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: rows),
      ),
    );
  }
}

Color statusColor(BuildContext context, TitleStatus s) {
  final scheme = Theme.of(context).colorScheme;
  switch (s) {
    case TitleStatus.paid:
      return Colors.green.shade700;
    case TitleStatus.overdue:
      return scheme.error;
    case TitleStatus.cancelled:
      return scheme.outline;
    case TitleStatus.partial:
      return Colors.orange.shade800;
    case TitleStatus.pending:
      return scheme.primary;
  }
}

class StatusChip extends StatelessWidget {
  final TitleStatus status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child:
          Text(statusLabels[status]!, style: TextStyle(fontSize: 12, color: c)),
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const InfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
              child: SelectableText(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Mensagem de erro com botão de tentar de novo.
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView(this.message, {super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off,
            size: 48, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Tentar de novo'),
        ),
      ]),
    );
  }
}
