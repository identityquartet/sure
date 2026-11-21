import 'package:flutter/material.dart';

import '../theme/sure_colors.dart';
import 'api.dart';
import 'format.dart';
import 'lookups.dart';
import 'split_screen.dart';
import 'txn_edit_screen.dart';
import 'widgets.dart';

class TxnDetailScreen extends StatefulWidget {
  const TxnDetailScreen({super.key, required this.id, this.initial});
  final String id;
  final Map<String, dynamic>? initial;

  @override
  State<TxnDetailScreen> createState() => _TxnDetailScreenState();
}

class _TxnDetailScreenState extends State<TxnDetailScreen> {
  Map<String, dynamic>? _t;
  Object? _error;
  bool _changed = false;
  List<Map<String, dynamic>>? _children;

  @override
  void initState() {
    super.initState();
    _t = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      final api = SureApi.of(context);
      final data = await api.get('transactions/${widget.id}');
      final m = Map<String, dynamic>.from(data as Map);
      List<Map<String, dynamic>>? children;
      if (m['split_parent'] == true) {
        final s = await api.get('transactions/${widget.id}/split');
        children = ((s as Map)['children'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _t = m;
        _children = children;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit() async {
    final ok = await push<bool>(context, TxnEditScreen(existing: _t));
    if (ok == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Delete transaction?', message: 'This cannot be undone.')) return;
    if (!mounted) return;
    final ok = await guarded(context, () => SureApi.of(context).delete('transactions/${widget.id}'),
        success: 'Transaction deleted');
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _split() async {
    final ok = await push<bool>(context, SplitScreen(transaction: _t!, children: _children));
    if (ok == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _unsplit() async {
    if (!await confirm(context, 'Remove split?',
        message: 'The split parts are removed and the original transaction is restored.',
        action: 'Unsplit')) {
      return;
    }
    if (!mounted) return;
    final ok = await guarded(
        context, () => SureApi.of(context).delete('transactions/${widget.id}/split'),
        success: 'Split removed');
    if (ok) {
      _changed = true;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final m = _t;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Transaction'),
          actions: [
            if (m != null) IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: _edit),
            if (m != null)
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'split') _split();
                  if (v == 'unsplit') _unsplit();
                  if (v == 'delete') _delete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'split',
                      child: Text(m['split_parent'] == true ? 'Edit split' : 'Split transaction')),
                  if (m['split_parent'] == true)
                    const PopupMenuItem(value: 'unsplit', child: Text('Remove split')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
          ],
        ),
        body: m == null
            ? (_error != null
                ? ErrorView(_error!, onRetry: _load)
                : const Center(child: CircularProgressIndicator()))
            : RefreshIndicator(
                onRefresh: _load,
                child: Builder(builder: (context) {
                  final t = Txn(m);
                  return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
                    const SizedBox(height: 24),
                    Center(
                      child: LetterAvatar(t.merchantName ?? t.name,
                          size: 64,
                          color: t.isTransfer ? palette.info : t.categoryColor,
                          icon: t.isTransfer ? Icons.swap_horiz : null),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(t.name,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Amount(t.displayAmount, t.currency,
                          colored: !t.isTransfer,
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 4),
                    Center(
                        child: Text(Fmt.relativeDay(t.date),
                            style: TextStyle(color: palette.textSubdued))),
                    const SizedBox(height: 8),
                    Wrap(alignment: WrapAlignment.center, spacing: 6, children: [
                      if (t.isTransfer) const StatusChip('Transfer'),
                      if (t.splitParent) const StatusChip('Split'),
                      if (t.excluded) const StatusChip('Excluded'),
                      if (t.kind != null && t.kind != 'standard') StatusChip(Fmt.humanize(t.kind)),
                    ]),
                    const SizedBox(height: 16),
                    Panel(children: [
                      KV('Account', t.accountName),
                      KV('Category', null,
                          onTap: _edit,
                          valueWidget: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            if (t.categoryName != null) ...[
                              Dot(t.categoryColor),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                                child: Text(t.categoryName ?? 'Uncategorized',
                                    style: const TextStyle(fontWeight: FontWeight.w500))),
                          ])),
                      KV('Merchant', t.merchantName, onTap: _edit),
                      KV('Tags', null,
                          onTap: _edit,
                          valueWidget: t.tags.isEmpty
                              ? const Text('—', textAlign: TextAlign.right)
                              : Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: t.tags
                                      .map((g) => StatusChip(g['name'].toString(),
                                          color: Fmt.hexColor(g['color'])))
                                      .toList())),
                      KV('Date', Fmt.day(t.dateStr)),
                      KV('Currency', t.currency),
                    ]),
                    if (t.notes != null) ...[
                      const SectionTitle('Notes'),
                      Panel(children: [
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: SizedBox(width: double.infinity, child: Text(t.notes!))),
                      ]),
                    ],
                    if (t.transfer != null) ...[
                      const SectionTitle('Transfer'),
                      Panel(children: _transferRows(t.transfer!)),
                    ],
                    if (_children != null && _children!.isNotEmpty) ...[
                      SectionTitle('Split into ${_children!.length}',
                          action: TextButton(onPressed: _split, child: const Text('Edit'))),
                      Panel(
                        children: _children!.map((c) {
                          final ct = Txn(c);
                          return ListTile(
                            leading: Dot(ct.categoryColor),
                            title: Text(ct.name),
                            subtitle: Text(ct.categoryName ?? 'Uncategorized'),
                            trailing: Amount(ct.displayAmount, ct.currency),
                          );
                        }).toList(),
                      ),
                    ],
                    const SectionTitle('Details'),
                    Panel(children: [
                      KV('Source', Fmt.humanize(m['source']?.toString())),
                      KV('Created', Fmt.dateTime(m['created_at'])),
                      KV('Updated', Fmt.dateTime(m['updated_at'])),
                      if (m['user_modified'] == true) const KV('Edited', 'Yes (protected from sync)'),
                    ]),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: OutlinedButton.icon(
                        onPressed: _delete,
                        icon: Icon(Icons.delete_outline, color: palette.destructive),
                        label: Text('Delete transaction',
                            style: TextStyle(color: palette.destructive)),
                      ),
                    ),
                  ]);
                }),
              ),
      ),
    );
  }

  List<Widget> _transferRows(Map<String, dynamic> tr) {
    final other = tr['other_account'] is Map ? tr['other_account'] as Map : null;
    return [
      if (other != null) KV('Other account', other['name']?.toString()),
      if (tr['amount'] != null) KV('Amount', tr['amount'].toString()),
      if (tr['status'] != null) KV('Status', Fmt.humanize(tr['status'].toString())),
    ];
  }
}

/// Helper used by other screens to resolve a category name from the cache.
String categoryName(String? id) => Lookups.instance.category(id)?['name']?.toString() ?? '';
