import 'package:flutter/material.dart';

import '../theme/sure_colors.dart';
import 'api.dart';
import 'format.dart';
import 'lookups.dart';
import 'widgets.dart';

class _Part {
  _Part({String name = '', String amount = '', this.categoryId})
      : name = TextEditingController(text: name),
        amount = TextEditingController(text: amount);
  final TextEditingController name;
  final TextEditingController amount;
  String? categoryId;
}

/// Split a transaction into parts (or edit an existing split). Parts are
/// entered as positive numbers and must add up to the transaction total.
class SplitScreen extends StatefulWidget {
  const SplitScreen({super.key, required this.transaction, this.children});
  final Map<String, dynamic> transaction;
  final List<Map<String, dynamic>>? children;

  @override
  State<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends State<SplitScreen> {
  late final Txn t = Txn(widget.transaction);
  final List<_Part> _parts = [];
  bool _saving = false;

  bool get _existing => widget.children != null && widget.children!.isNotEmpty;
  double get _sign => t.rawAmount < 0 ? -1 : 1;

  @override
  void initState() {
    super.initState();
    if (_existing) {
      for (final c in widget.children!) {
        final ct = Txn(c);
        _parts.add(_Part(
            name: ct.name, amount: ct.absAmount.toStringAsFixed(2), categoryId: ct.categoryId));
      }
    } else {
      final half = (t.absAmount / 2);
      final first = (half * 100).floor() / 100;
      _parts.add(_Part(name: t.name, amount: first.toStringAsFixed(2), categoryId: t.categoryId));
      _parts.add(_Part(name: t.name, amount: (t.absAmount - first).toStringAsFixed(2)));
    }
    Lookups.instance.load(context).whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  double get _allocated => _parts.fold(
      0, (s, p) => s + (double.tryParse(p.amount.text.replaceAll(',', '.')) ?? 0));
  double get _remaining => double.parse((t.absAmount - _allocated).toStringAsFixed(2));

  Future<void> _save() async {
    if (_remaining.abs() > 0.004) {
      toast(context, 'Parts must add up to ${Fmt.money(t.absAmount, t.currency)}', error: true);
      return;
    }
    setState(() => _saving = true);
    final splits = _parts.map((p) {
      final amt = double.parse(p.amount.text.replaceAll(',', '.')) * _sign;
      return {
        'name': p.name.text.trim().isEmpty ? t.name : p.name.text.trim(),
        'amount': amt.toStringAsFixed(2),
        if (p.categoryId != null) 'category_id': p.categoryId,
      };
    }).toList();
    // Make the rounded parts sum exactly to the stored decimal amount.
    final exact = t.rawAmount;
    final sum = splits.fold<double>(0, (s, e) => s + double.parse(e['amount'] as String));
    final diff = exact - sum;
    if (diff.abs() > 0) {
      final last = splits.last;
      last['amount'] = (double.parse(last['amount'] as String) + diff).toStringAsFixed(4);
    }
    final api = SureApi.of(context);
    try {
      final path = 'transactions/${t.id}/split';
      final body = {
        'split': {'splits': splits}
      };
      if (_existing) {
        await api.patch(path, body);
      } else {
        await api.post(path, body);
      }
      if (!mounted) return;
      toast(context, 'Split saved');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final l = Lookups.instance;
    final rem = _remaining;
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing ? 'Edit split' : 'Split transaction'),
        actions: [TextButton(onPressed: _saving ? null : _save, child: const Text('Save'))],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        ListTile(
          title: Text(t.name),
          subtitle: Text(Fmt.day(t.dateStr)),
          trailing: Amount(t.displayAmount, t.currency),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: rem.abs() < 0.005 ? palette.success.withValues(alpha: 0.1) : palette.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            rem.abs() < 0.005
                ? 'Fully allocated'
                : (rem > 0
                    ? '${Fmt.money(rem, t.currency)} left to allocate'
                    : '${Fmt.money(-rem, t.currency)} over the total'),
            textAlign: TextAlign.center,
          ),
        ),
        for (var i = 0; i < _parts.length; i++) _partCard(i, l),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _parts.add(_Part(
                name: t.name, amount: rem > 0 ? rem.toStringAsFixed(2) : ''))),
            icon: const Icon(Icons.add),
            label: const Text('Add part'),
          ),
        ),
      ]),
    );
  }

  Widget _partCard(int i, Lookups l) {
    final p = _parts[i];
    final cat = l.category(p.categoryId);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: p.name,
                decoration: InputDecoration(labelText: 'Part ${i + 1} name', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: TextField(
                controller: p.amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _parts.length <= 2 ? null : () => setState(() => _parts.removeAt(i)),
            ),
          ]),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Dot(Fmt.hexColor(cat?['color']), size: 14),
            title: Text(cat?['name']?.toString() ?? 'Uncategorized'),
            trailing: const Icon(Icons.expand_more),
            onTap: () async {
              final r = await pickOne(context,
                  title: 'Category',
                  items: l.categoriesTree(),
                  selectedId: p.categoryId,
                  allowNone: true,
                  noneLabel: 'Uncategorized',
                  leading: (c) => Dot(Fmt.hexColor(c['color'])));
              if (r != null) setState(() => p.categoryId = r['id']?.toString());
            },
          ),
        ]),
      ),
    );
  }
}
