import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/sure_colors.dart';
import 'api.dart';
import 'format.dart';
import 'lookups.dart';
import 'txn_detail_screen.dart';
import 'txn_edit_screen.dart';
import 'widgets.dart';

class TxnFilter {
  String search = '';
  Set<String> accountIds = {};
  Set<String> categoryIds = {};
  Set<String> merchantIds = {};
  Set<String> tagIds = {};
  String? type; // income | expense
  DateTime? start;
  DateTime? end;
  double? min;
  double? max;

  TxnFilter();

  TxnFilter copy() => TxnFilter()
    ..search = search
    ..accountIds = {...accountIds}
    ..categoryIds = {...categoryIds}
    ..merchantIds = {...merchantIds}
    ..tagIds = {...tagIds}
    ..type = type
    ..start = start
    ..end = end
    ..min = min
    ..max = max;

  int get activeCount =>
      (accountIds.isNotEmpty ? 1 : 0) +
      (categoryIds.isNotEmpty ? 1 : 0) +
      (merchantIds.isNotEmpty ? 1 : 0) +
      (tagIds.isNotEmpty ? 1 : 0) +
      (type != null ? 1 : 0) +
      (start != null || end != null ? 1 : 0) +
      (min != null || max != null ? 1 : 0);

  Map<String, dynamic> toQuery() {
    double? lo = min, hi = max;
    if (type == 'income') {
      lo = max == null ? null : -max!;
      hi = min == null ? null : -min!;
    }
    return {
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (accountIds.length == 1) 'account_id': accountIds.first,
      if (accountIds.length > 1) 'account_ids': accountIds.toList(),
      if (categoryIds.isNotEmpty) 'category_ids': categoryIds.toList(),
      if (merchantIds.isNotEmpty) 'merchant_ids': merchantIds.toList(),
      if (tagIds.isNotEmpty) 'tag_ids': tagIds.toList(),
      if (type != null) 'type': type,
      if (start != null) 'start_date': Fmt.iso(start!),
      if (end != null) 'end_date': Fmt.iso(end!),
      if (lo != null) 'min_amount': lo,
      if (hi != null) 'max_amount': hi,
    };
  }
}

/// Every transaction across all accounts: server-side search, filters,
/// infinite scroll, day grouping, multi-select bulk edit.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key, this.initial, this.title, this.embedded = false});
  final TxnFilter? initial;
  final String? title;
  final bool embedded;

  @override
  State<TransactionsScreen> createState() => TransactionsScreenState();
}

class TransactionsScreenState extends State<TransactionsScreen> {
  late TxnFilter _filter = widget.initial?.copy() ?? TxnFilter();
  final _listKey = GlobalKey<PagedListState>();
  final _searchCtl = TextEditingController();
  Timer? _debounce;
  int? _total;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _searchCtl.text = _filter.search;
    Lookups.instance.load(context).then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> reload() async => _listKey.currentState?.reload();

  void _apply(TxnFilter f) {
    setState(() {
      _filter = f;
      _selected.clear();
    });
    _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final selecting = _selected.isNotEmpty;
    final body = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _searchCtl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search name, notes, merchant',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchCtl.clear();
                          _apply(_filter.copy()..search = '');
                        }),
              ),
              onChanged: (v) {
                setState(() {});
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 450),
                    () => _apply(_filter.copy()..search = v));
              },
              onSubmitted: (v) => _apply(_filter.copy()..search = v),
            ),
          ),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: _filter.activeCount > 0,
            label: Text('${_filter.activeCount}'),
            child: IconButton.filledTonal(
              tooltip: 'Filters',
              icon: const Icon(Icons.tune),
              onPressed: _openFilters,
            ),
          ),
        ]),
      ),
      _activeChips(),
      Expanded(
        child: PagedList(
          key: _listKey,
          fetch: (page) => SureApi.of(context)
              .page('transactions', 'transactions', page: page, perPage: 50, query: _filter.toQuery()),
          onLoaded: (items, total) {
            if (mounted && total != _total) setState(() => _total = total);
          },
          groupBy: (m) => m['date']?.toString() ?? '',
          groupHeader: (ctx, g, items) {
            final net = items.fold<double>(0, (s, m) => s + Txn(m).displayAmount);
            final cur = items.isEmpty ? 'EUR' : Txn(items.first).currency;
            final d = DateTime.tryParse(g);
            return GroupHeader(d == null ? g : Fmt.relativeDay(d),
                trailing: Amount(net, cur,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)));
          },
          empty: EmptyView(
            _filter.activeCount > 0 || _filter.search.isNotEmpty
                ? 'No transactions match'
                : 'No transactions yet',
            icon: Icons.receipt_long_outlined,
          ),
          itemBuilder: (ctx, m) {
            final t = Txn(m);
            return TxnTile(
              t,
              selected: _selected.contains(t.id),
              onLongPress: () => setState(() =>
                  _selected.contains(t.id) ? _selected.remove(t.id) : _selected.add(t.id)),
              onTap: selecting
                  ? () => setState(() =>
                      _selected.contains(t.id) ? _selected.remove(t.id) : _selected.add(t.id))
                  : () async {
                      final changed = await push<bool>(context, TxnDetailScreen(id: t.id, initial: m));
                      if (changed == true) reload();
                    },
            );
          },
        ),
      ),
    ]);

    final appBar = selecting
        ? AppBar(
            leading: IconButton(
                icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
            title: Text('${_selected.length} selected'),
            actions: [
              IconButton(
                  tooltip: 'Set category',
                  icon: const Icon(Icons.category_outlined),
                  onPressed: _bulkCategory),
              IconButton(
                  tooltip: 'Add tags',
                  icon: const Icon(Icons.sell_outlined),
                  onPressed: _bulkTags),
              IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _bulkDelete),
            ],
          )
        : (widget.embedded
            ? null
            : AppBar(title: Text(widget.title ?? 'Transactions')));

    return Scaffold(
      appBar: appBar,
      body: body,
      floatingActionButton: selecting
          ? null
          : FloatingActionButton(
              heroTag: 'txn-add-${widget.title}',
              tooltip: 'New transaction',
              onPressed: () async {
                final created = await push<bool>(
                    context,
                    TxnEditScreen(
                        defaultAccountId:
                            _filter.accountIds.length == 1 ? _filter.accountIds.first : null));
                if (created == true) reload();
              },
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _activeChips() {
    final l = Lookups.instance;
    final chips = <Widget>[];
    void chip(String label, VoidCallback onClear) => chips.add(Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InputChip(
            label: Text(label, overflow: TextOverflow.ellipsis),
            onDeleted: onClear,
            visualDensity: VisualDensity.compact,
          ),
        ));
    String names(Set<String> ids, Map<String, dynamic>? Function(String) find) =>
        ids.map((id) => find(id)?['name']?.toString() ?? '…').join(', ');

    if (_filter.type != null) {
      chip(Fmt.humanize(_filter.type), () => _apply(_filter.copy()..type = null));
    }
    if (_filter.accountIds.isNotEmpty) {
      chip(names(_filter.accountIds, l.account), () => _apply(_filter.copy()..accountIds = {}));
    }
    if (_filter.categoryIds.isNotEmpty) {
      chip(names(_filter.categoryIds, l.category), () => _apply(_filter.copy()..categoryIds = {}));
    }
    if (_filter.merchantIds.isNotEmpty) {
      chip(names(_filter.merchantIds, l.merchant), () => _apply(_filter.copy()..merchantIds = {}));
    }
    if (_filter.tagIds.isNotEmpty) {
      chip(names(_filter.tagIds, l.tag), () => _apply(_filter.copy()..tagIds = {}));
    }
    if (_filter.start != null || _filter.end != null) {
      chip(
          '${_filter.start == null ? '…' : Fmt.day(_filter.start, pattern: 'd MMM yy')} – ${_filter.end == null ? '…' : Fmt.day(_filter.end, pattern: 'd MMM yy')}',
          () => _apply(_filter.copy()
            ..start = null
            ..end = null));
    }
    if (_filter.min != null || _filter.max != null) {
      chip('${_filter.min?.toStringAsFixed(0) ?? '0'} – ${_filter.max?.toStringAsFixed(0) ?? '∞'}',
          () => _apply(_filter.copy()
            ..min = null
            ..max = null));
    }
    final count = _total == null ? null : '$_total transaction${_total == 1 ? '' : 's'}';
    if (chips.isEmpty && count == null) return const SizedBox(height: 4);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          if (count != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Center(
                  child: Text(count,
                      style: TextStyle(
                          fontSize: 12, color: SureColors.of(context).palette.textSubdued))),
            ),
          ...chips,
        ],
      ),
    );
  }

  Future<void> _openFilters() async {
    await Lookups.instance.load(context).catchError((_) {});
    if (!mounted) return;
    final res = await showModalBottomSheet<TxnFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TxnFilterSheet(filter: _filter.copy()),
    );
    if (res != null) _apply(res);
  }

  Future<void> _bulkCategory() async {
    final l = Lookups.instance;
    final cat = await pickOne(context,
        title: 'Set category',
        items: l.categoriesTree(),
        leading: (c) => Dot(Fmt.hexColor(c['color'])));
    if (cat == null || cat['id'] == null || !mounted) return;
    final api = SureApi.of(context);
    final ids = _selected.toList();
    await guarded(context, () async {
      for (final id in ids) {
        await api.patch('transactions/$id', {
          'transaction': {'category_id': cat['id']}
        });
      }
    }, success: 'Updated ${ids.length} transactions');
    setState(_selected.clear);
    reload();
  }

  Future<void> _bulkTags() async {
    final l = Lookups.instance;
    final tags = await pickMany(context, title: 'Add tags', items: l.tags,
        leading: (t) => Dot(Fmt.hexColor(t['color'])));
    if (tags == null || tags.isEmpty || !mounted) return;
    final api = SureApi.of(context);
    final current = {
      for (final m in _listKey.currentState?.items ?? <Map<String, dynamic>>[]) m['id'].toString(): m
    };
    final ids = _selected.toList();
    await guarded(context, () async {
      for (final id in ids) {
        final existing = current[id] == null
            ? <String>{}
            : Txn(current[id]!).tags.map((t) => t['id'].toString()).toSet();
        await api.patch('transactions/$id', {
          'transaction': {'tag_ids': {...existing, ...tags}.toList()}
        });
      }
    }, success: 'Tagged ${ids.length} transactions');
    setState(_selected.clear);
    reload();
  }

  Future<void> _bulkDelete() async {
    final n = _selected.length;
    if (!await confirm(context, 'Delete $n transaction${n == 1 ? '' : 's'}?',
        message: 'This cannot be undone.')) {
      return;
    }
    if (!mounted) return;
    final api = SureApi.of(context);
    final ids = _selected.toList();
    await guarded(context, () async {
      for (final id in ids) {
        await api.delete('transactions/$id');
      }
    }, success: 'Deleted $n');
    setState(_selected.clear);
    reload();
  }
}

class TxnTile extends StatelessWidget {
  const TxnTile(this.t,
      {super.key, this.onTap, this.onLongPress, this.selected = false, this.showAccount = true});
  final Txn t;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool showAccount;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final sub = <String>[
      if (t.isTransfer) 'Transfer' else (t.categoryName ?? 'Uncategorized'),
      if (showAccount && t.accountName.isNotEmpty) t.accountName,
    ];
    return ListTile(
      selected: selected,
      selectedTileColor: palette.surfaceInset,
      onTap: onTap,
      onLongPress: onLongPress,
      leading: selected
          ? CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.check, color: Colors.white))
          : LetterAvatar(
              t.merchantName ?? t.name,
              color: t.isTransfer ? palette.info : t.categoryColor,
              icon: t.isTransfer ? Icons.swap_horiz : null,
            ),
      title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(children: [
        Flexible(
          child: Text(sub.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: palette.textSubdued)),
        ),
        if (t.tags.isNotEmpty) ...[
          const SizedBox(width: 6),
          Icon(Icons.sell_outlined, size: 12, color: palette.textSubdued),
        ],
        if (t.splitParent) ...[
          const SizedBox(width: 6),
          Icon(Icons.call_split, size: 12, color: palette.textSubdued),
        ],
        if (t.excluded) ...[
          const SizedBox(width: 6),
          Icon(Icons.visibility_off_outlined, size: 12, color: palette.textSubdued),
        ],
      ]),
      trailing: Amount(t.displayAmount, t.currency,
          colored: !t.isTransfer,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              decoration: t.excluded ? TextDecoration.lineThrough : null)),
    );
  }
}

class TxnFilterSheet extends StatefulWidget {
  const TxnFilterSheet({super.key, required this.filter});
  final TxnFilter filter;

  @override
  State<TxnFilterSheet> createState() => _TxnFilterSheetState();
}

class _TxnFilterSheetState extends State<TxnFilterSheet> {
  late final TxnFilter f = widget.filter;
  late final _min = TextEditingController(text: f.min?.toString() ?? '');
  late final _max = TextEditingController(text: f.max?.toString() ?? '');

  String _names(Set<String> ids, Map<String, dynamic>? Function(String) find) => ids.isEmpty
      ? 'Any'
      : ids.map((id) => find(id)?['name']?.toString() ?? '…').join(', ');

  @override
  Widget build(BuildContext context) {
    final l = Lookups.instance;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(controller: scroll, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            Expanded(child: Text('Filters', style: Theme.of(context).textTheme.titleLarge)),
            TextButton(
                onPressed: () => Navigator.pop(context, TxnFilter()..search = f.search),
                child: const Text('Reset')),
            const SizedBox(width: 4),
            FilledButton(onPressed: _apply, child: const Text('Apply')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<String?>(
            segments: const [
              ButtonSegment(value: null, label: Text('All')),
              ButtonSegment(value: 'expense', label: Text('Expenses')),
              ButtonSegment(value: 'income', label: Text('Income')),
            ],
            selected: {f.type},
            onSelectionChanged: (s) => setState(() => f.type = s.first),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.account_balance_outlined),
          title: const Text('Accounts'),
          subtitle: Text(_names(f.accountIds, l.account), maxLines: 2),
          onTap: () async {
            final r = await pickMany(context,
                title: 'Accounts', items: l.accounts, selected: f.accountIds);
            if (r != null) setState(() => f.accountIds = r);
          },
        ),
        ListTile(
          leading: const Icon(Icons.category_outlined),
          title: const Text('Categories'),
          subtitle: Text(_names(f.categoryIds, l.category), maxLines: 2),
          onTap: () async {
            final r = await pickMany(context,
                title: 'Categories',
                items: l.categoriesTree(),
                selected: f.categoryIds,
                leading: (c) => Dot(Fmt.hexColor(c['color'])));
            if (r != null) setState(() => f.categoryIds = r);
          },
        ),
        ListTile(
          leading: const Icon(Icons.storefront_outlined),
          title: const Text('Merchants'),
          subtitle: Text(_names(f.merchantIds, l.merchant), maxLines: 2),
          onTap: () async {
            final r = await pickMany(context,
                title: 'Merchants', items: l.merchants, selected: f.merchantIds);
            if (r != null) setState(() => f.merchantIds = r);
          },
        ),
        ListTile(
          leading: const Icon(Icons.sell_outlined),
          title: const Text('Tags'),
          subtitle: Text(_names(f.tagIds, l.tag), maxLines: 2),
          onTap: () async {
            final r = await pickMany(context,
                title: 'Tags',
                items: l.tags,
                selected: f.tagIds,
                leading: (t) => Dot(Fmt.hexColor(t['color'])));
            if (r != null) setState(() => f.tagIds = r);
          },
        ),
        const SectionTitle('Date'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in const ['This month', 'Last month', 'Last 30 days', 'Last 90 days', 'This year'])
              ActionChip(label: Text(p), onPressed: () => setState(() => _preset(p))),
          ]),
        ),
        Row(children: [
          Expanded(
            child: ListTile(
              title: const Text('From'),
              subtitle: Text(f.start == null ? 'Any' : Fmt.day(f.start)),
              onTap: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: f.start ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100));
                if (d != null) setState(() => f.start = d);
              },
              trailing: f.start == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close), onPressed: () => setState(() => f.start = null)),
            ),
          ),
          Expanded(
            child: ListTile(
              title: const Text('To'),
              subtitle: Text(f.end == null ? 'Any' : Fmt.day(f.end)),
              onTap: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: f.end ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100));
                if (d != null) setState(() => f.end = d);
              },
              trailing: f.end == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close), onPressed: () => setState(() => f.end = null)),
            ),
          ),
        ]),
        const SectionTitle('Amount'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _min,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Min', isDense: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _max,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Max', isDense: true),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text('Amounts apply to money out unless Income is selected.',
              style: TextStyle(fontSize: 12, color: SureColors.of(context).palette.textSubdued)),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _apply, child: const Text('Apply')),
        ),
      ]),
    );
  }

  void _apply() {
    f.min = double.tryParse(_min.text.replaceAll(',', '.'));
    f.max = double.tryParse(_max.text.replaceAll(',', '.'));
    Navigator.pop(context, f);
  }

  void _preset(String p) {
    final now = DateTime.now();
    switch (p) {
      case 'This month':
        f.start = DateTime(now.year, now.month, 1);
        f.end = null;
      case 'Last month':
        f.start = DateTime(now.year, now.month - 1, 1);
        f.end = DateTime(now.year, now.month, 0);
      case 'Last 30 days':
        f.start = now.subtract(const Duration(days: 30));
        f.end = null;
      case 'Last 90 days':
        f.start = now.subtract(const Duration(days: 90));
        f.end = null;
      case 'This year':
        f.start = DateTime(now.year, 1, 1);
        f.end = null;
    }
  }
}
