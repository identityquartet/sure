import 'package:flutter/material.dart';

import '../theme/sure_colors.dart';
import 'api.dart';
import 'format.dart';
import 'lookups.dart';
import 'transactions_screen.dart';
import 'widgets.dart';

const sureColors = [
  '#e99537', '#4da568', '#6471eb', '#db5a54', '#df4e92', '#c44fe9', '#eb5429',
  '#61c9ea', '#805dee', '#6ad28a', '#1570EF', '#F23E94', '#6172F3', '#737373',
];

Widget colorPicker(String? selected, ValueChanged<String> onPick) => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: sureColors.map((c) {
        final on = selected?.toLowerCase() == c.toLowerCase();
        return GestureDetector(
          onTap: () => onPick(c),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Fmt.hexColor(c),
              shape: BoxShape.circle,
              border: on ? Border.all(width: 3, color: Colors.black54) : null,
            ),
            child: on ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
          ),
        );
      }).toList(),
    );

// ───────────────────────────── Categories ─────────────────────────────

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final _key = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();

  Future<void> _create() async {
    final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const _CategorySheet());
    if (ok == true) {
      if (mounted) await Lookups.instance.load(context, force: true);
      _key.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(Icons.add)),
      body: AsyncView<List<Map<String, dynamic>>>(
        key: _key,
        load: () async {
          await Lookups.instance.load(context, force: true);
          return Lookups.instance.categoriesTree();
        },
        builder: (context, cats) {
          if (cats.isEmpty) return const EmptyView('No categories');
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: cats.map((c) {
              final child = c['parent'] != null;
              return ListTile(
                contentPadding: EdgeInsets.only(left: child ? 48 : 16, right: 16),
                leading: Dot(Fmt.hexColor(c['color']), size: 14),
                title: Text(c['name'].toString()),
                subtitle: (c['subcategories_count'] ?? 0) > 0
                    ? Text('${c['subcategories_count']} subcategories')
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => push(
                    context,
                    TransactionsScreen(
                        title: c['name'].toString(),
                        initial: TxnFilter()..categoryIds = {c['id'].toString()})),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet();
  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  final _name = TextEditingController();
  String _color = sureColors.first;
  String? _parentId;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final parents = Lookups.instance.categories.where((c) => c['parent'] == null).toList();
    final parent = Lookups.instance.category(_parentId);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('New category', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name')),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Parent'),
          subtitle: Text(parent?['name']?.toString() ?? 'None (top level)'),
          onTap: () async {
            final r = await pickOne(context,
                title: 'Parent category',
                items: parents,
                selectedId: _parentId,
                allowNone: true,
                noneLabel: 'None (top level)');
            if (r != null) setState(() => _parentId = r['id']?.toString());
          },
        ),
        const SizedBox(height: 8),
        colorPicker(_color, (c) => setState(() => _color = c)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  if (_name.text.trim().isEmpty) return;
                  final api = SureApi.of(context);
                  setState(() => _saving = true);
                  final ok = await guarded(
                      context,
                      () => api.post('categories', {
                            'category': {
                              'name': _name.text.trim(),
                              'color': _color,
                              if (_parentId != null) 'parent_id': _parentId,
                            }
                          }),
                      success: 'Category created');
                  if (!mounted) return;
                  setState(() => _saving = false);
                  if (ok) Navigator.pop(context, true);
                },
          child: const Text('Create'),
        ),
        const SizedBox(height: 8),
        Text('Editing and deleting categories is web-only (not in the API).',
            style: TextStyle(fontSize: 12, color: SureColors.of(context).palette.textSubdued)),
      ]),
    );
  }
}

// ───────────────────────────── Tags ─────────────────────────────

class TagsScreen extends StatefulWidget {
  const TagsScreen({super.key});
  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
  final _key = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();

  Future<void> _edit([Map<String, dynamic>? tag]) async {
    final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _TagSheet(existing: tag));
    if (ok == true) {
      Lookups.instance.invalidate();
      _key.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
      body: AsyncView<List<Map<String, dynamic>>>(
        key: _key,
        load: () async {
          await Lookups.instance.load(context, force: true);
          return Lookups.instance.tags;
        },
        builder: (context, tags) {
          if (tags.isEmpty) {
            return const EmptyView('No tags yet', icon: Icons.sell_outlined, hint: 'Tap + to create one.');
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: tags
                .map((t) => ListTile(
                      leading: Dot(Fmt.hexColor(t['color']), size: 14),
                      title: Text(t['name'].toString()),
                      onTap: () => push(
                          context,
                          TransactionsScreen(
                              title: '#${t['name']}', initial: TxnFilter()..tagIds = {t['id'].toString()})),
                      trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(t)),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}

class _TagSheet extends StatefulWidget {
  const _TagSheet({this.existing});
  final Map<String, dynamic>? existing;
  @override
  State<_TagSheet> createState() => _TagSheetState();
}

class _TagSheetState extends State<_TagSheet> {
  late final _name = TextEditingController(text: widget.existing?['name']?.toString() ?? '');
  late String _color = widget.existing?['color']?.toString() ?? sureColors[2];

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(editing ? 'Edit tag' : 'New tag', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(controller: _name, autofocus: !editing, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 16),
        colorPicker(_color, (c) => setState(() => _color = c)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            if (_name.text.trim().isEmpty) return;
            final api = SureApi.of(context);
            final body = {
              'tag': {'name': _name.text.trim(), 'color': _color}
            };
            final ok = await guarded(context, () async {
              if (editing) {
                await api.patch('tags/${widget.existing!['id']}', body);
              } else {
                await api.post('tags', body);
              }
            }, success: editing ? 'Tag updated' : 'Tag created');
            if (ok && context.mounted) Navigator.pop(context, true);
          },
          child: Text(editing ? 'Save' : 'Create'),
        ),
        if (editing)
          TextButton(
            onPressed: () async {
              if (!await confirm(context, 'Delete tag "${widget.existing!['name']}"?',
                  message: 'It is removed from all transactions.')) {
                return;
              }
              if (!context.mounted) return;
              final ok = await guarded(
                  context, () => SureApi.of(context).delete('tags/${widget.existing!['id']}'),
                  success: 'Tag deleted');
              if (ok && context.mounted) Navigator.pop(context, true);
            },
            child: Text('Delete', style: TextStyle(color: SureColors.of(context).palette.destructive)),
          ),
      ]),
    );
  }
}

// ───────────────────────────── Merchants ─────────────────────────────

class MerchantsScreen extends StatelessWidget {
  const MerchantsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Merchants')),
      body: AsyncView<List<Map<String, dynamic>>>(
        load: () async {
          await Lookups.instance.load(context, force: true);
          return Lookups.instance.merchants;
        },
        builder: (context, list) {
          if (list.isEmpty) {
            return const EmptyView('No merchants',
                icon: Icons.storefront_outlined,
                hint: 'Merchants come from bank sync or are created in the web app.');
          }
          return ListView(
            children: list
                .map((m) => ListTile(
                      leading: LetterAvatar(m['name'].toString(), color: Fmt.hexColor(m['color'])),
                      title: Text(m['name'].toString()),
                      subtitle: m['website_url'] == null ? null : Text(m['website_url'].toString()),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => push(
                          context,
                          TransactionsScreen(
                              title: m['name'].toString(),
                              initial: TxnFilter()..merchantIds = {m['id'].toString()})),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}

// ───────────────────────────── Recurring ─────────────────────────────

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  final _key = GlobalKey<PagedListState>();

  Future<void> _edit([Map<String, dynamic>? r]) async {
    await Lookups.instance.load(context).catchError((_) {});
    if (!mounted) return;
    final ok = await push<bool>(context, RecurringEditScreen(existing: r));
    if (ok == true) _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
      body: PagedList(
        key: _key,
        fetch: (p) => SureApi.of(context).page('recurring_transactions', 'recurring_transactions', page: p),
        empty: const EmptyView('No recurring transactions',
            icon: Icons.event_repeat,
            hint: 'Sure detects these automatically, or add one with +.'),
        itemBuilder: (context, r) {
          final status = r['status']?.toString();
          final amt = Fmt.parse(r['amount']) ?? 0;
          return ListTile(
            leading: LetterAvatar(r['name']?.toString() ?? '?', icon: Icons.event_repeat),
            title: Text(r['name']?.toString() ?? '(unnamed)'),
            subtitle: Text([
              if (r['next_expected_date'] != null) 'Next ${Fmt.day(r['next_expected_date'])}',
              if (r['expected_day_of_month'] != null) 'day ${r['expected_day_of_month']}',
              if ((r['account'] as Map?)?['name'] != null) (r['account'] as Map)['name'],
              if (r['autopay'] == true) 'autopay',
            ].join(' · ')),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Amount(-amt, r['currency']?.toString() ?? 'EUR'),
                if (status != null && status != 'active')
                  Text(Fmt.humanize(status), style: TextStyle(fontSize: 11, color: palette.textSubdued)),
              ],
            ),
            onTap: () => _edit(r),
          );
        },
      ),
    );
  }
}

class RecurringEditScreen extends StatefulWidget {
  const RecurringEditScreen({super.key, this.existing});
  final Map<String, dynamic>? existing;
  @override
  State<RecurringEditScreen> createState() => _RecurringEditScreenState();
}

class _RecurringEditScreenState extends State<RecurringEditScreen> {
  late final e = widget.existing;
  late final _name = TextEditingController(text: e?['name']?.toString() ?? '');
  late final _amount = TextEditingController(
      text: e == null ? '' : (Fmt.parse(e!['amount']) ?? 0).toStringAsFixed(2));
  late final _day = TextEditingController(text: e?['expected_day_of_month']?.toString() ?? '');
  late final _url = TextEditingController(text: e?['payment_url']?.toString() ?? '');
  late final _notes = TextEditingController(text: e?['notes']?.toString() ?? '');
  late String _status = e?['status']?.toString() ?? 'active';
  late bool _autopay = e?['autopay'] == true;
  late DateTime _next = DateTime.tryParse(e?['next_expected_date']?.toString() ?? '') ??
      DateTime(DateTime.now().year, DateTime.now().month + 1, DateTime.now().day);
  late DateTime _last = DateTime.tryParse(e?['last_occurrence_date']?.toString() ?? '') ?? DateTime.now();
  late String? _accountId = (e?['account'] as Map?)?['id']?.toString();
  late String? _merchantId = (e?['merchant'] as Map?)?['id']?.toString();
  bool _saving = false;

  bool get _editing => e != null;

  Future<void> _save() async {
    setState(() => _saving = true);
    final api = SureApi.of(context);
    final common = {
      if (const ['active', 'inactive'].contains(_status)) 'status': _status,
      if (_day.text.trim().isNotEmpty) 'expected_day_of_month': int.tryParse(_day.text.trim()),
      'next_expected_date': Fmt.iso(_next),
      'payment_url': _url.text.trim(),
      'autopay': _autopay,
      'notes': _notes.text.trim(),
    };
    try {
      if (_editing) {
        await api.patch('recurring_transactions/${e!['id']}', {'recurring_transaction': common});
      } else {
        final acct = Lookups.instance.account(_accountId);
        await api.post('recurring_transactions', {
          'recurring_transaction': {
            ...common,
            'name': _name.text.trim(),
            'amount': _amount.text.trim().replaceAll(',', '.'),
            'currency': acct?['currency'] ?? 'EUR',
            'last_occurrence_date': Fmt.iso(_last),
            if (_accountId != null) 'account_id': _accountId,
            if (_merchantId != null) 'merchant_id': _merchantId,
          }
        });
      }
      if (mounted) {
        toast(context, 'Saved');
        Navigator.pop(context, true);
      }
    } catch (err) {
      if (mounted) toast(context, err.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Delete recurring transaction?')) return;
    if (!mounted) return;
    final ok = await guarded(context, () => SureApi.of(context).delete('recurring_transactions/${e!['id']}'),
        success: 'Deleted');
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<DateTime?> _pickDate(DateTime init) => showDatePicker(
      context: context, initialDate: init, firstDate: DateTime(2000), lastDate: DateTime(2100));

  @override
  Widget build(BuildContext context) {
    final l = Lookups.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Recurring' : 'New recurring'),
        actions: [
          if (_editing) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
          TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: _name,
            enabled: !_editing,
            decoration: const InputDecoration(labelText: 'Name')),
        TextField(
            controller: _amount,
            enabled: !_editing,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(
                labelText: 'Amount', helperText: 'Positive = money out, negative = money in')),
        if (!_editing) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Account'),
            subtitle: Text(l.account(_accountId)?['name']?.toString() ?? 'None'),
            onTap: () async {
              final r = await pickOne(context,
                  title: 'Account', items: l.accounts, selectedId: _accountId, allowNone: true);
              if (r != null) setState(() => _accountId = r['id']?.toString());
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Merchant'),
            subtitle: Text(l.merchant(_merchantId)?['name']?.toString() ?? 'None'),
            onTap: () async {
              final r = await pickOne(context,
                  title: 'Merchant', items: l.merchants, selectedId: _merchantId, allowNone: true);
              if (r != null) setState(() => _merchantId = r['id']?.toString());
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Last occurrence'),
            subtitle: Text(Fmt.day(_last)),
            onTap: () async {
              final d = await _pickDate(_last);
              if (d != null) setState(() => _last = d);
            },
          ),
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Next expected'),
          subtitle: Text(Fmt.day(_next)),
          onTap: () async {
            final d = await _pickDate(_next);
            if (d != null) setState(() => _next = d);
          },
        ),
        TextField(
            controller: _day,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Expected day of month')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: const ['active', 'inactive'].contains(_status) ? _status : null,
          decoration: const InputDecoration(labelText: 'Status'),
          items: const ['active', 'inactive']
              .map((s) => DropdownMenuItem(value: s, child: Text(Fmt.humanize(s))))
              .toList(),
          onChanged: (v) => setState(() => _status = v ?? 'active'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Autopay'),
          value: _autopay,
          onChanged: (v) => setState(() => _autopay = v),
        ),
        TextField(controller: _url, decoration: const InputDecoration(labelText: 'Payment URL')),
        TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes')),
        if (_editing) ...[
          const SizedBox(height: 16),
          Panel(margin: EdgeInsets.zero, children: [
            KV('Occurrences', e!['occurrence_count']?.toString()),
            KV('Last seen', Fmt.day(e!['last_occurrence_date'])),
            KV('Expected range',
                e!['expected_amount_min'] == null ? null : '${e!['expected_amount_min']} – ${e!['expected_amount_max']}'),
            KV('Detected', e!['manual'] == true ? 'Manual' : 'Automatic'),
          ]),
        ],
      ]),
    );
  }
}

// ───────────────────────────── Rules ─────────────────────────────

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  String _cond(Map c) {
    final subs = (c['sub_conditions'] as List?) ?? [];
    if (subs.isNotEmpty) {
      return '(${subs.map((s) => _cond(s as Map)).join(' ${c['operator'] ?? 'and'} ')})';
    }
    return '${Fmt.humanize(c['condition_type']?.toString().replaceAll('transaction_', ''))} ${c['operator']} ${c['value'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rules'),
          bottom: const TabBar(tabs: [Tab(text: 'Rules'), Tab(text: 'Run history')]),
        ),
        body: TabBarView(children: [
          PagedList(
            fetch: (p) => SureApi.of(context).page('rules', 'data', page: p, perPage: 50),
            empty: const EmptyView('No rules', icon: Icons.rule),
            itemBuilder: (context, r) {
              final conds = ((r['conditions'] as List?) ?? []).map((c) => _cond(c as Map)).toList();
              final actions = ((r['actions'] as List?) ?? [])
                  .map((a) => '${Fmt.humanize((a as Map)['action_type']?.toString())}${a['value'] != null ? ': ${_actionValue(a)}' : ''}')
                  .toList();
              return ListTile(
                leading: Icon(r['active'] == true ? Icons.bolt : Icons.bolt_outlined,
                    color: r['active'] == true ? palette.success : palette.textSubdued),
                title: Text(r['name']?.toString() ?? 'Untitled rule'),
                subtitle: Text([
                  if (conds.isNotEmpty) 'If ${conds.join(' and ')}',
                  if (actions.isNotEmpty) '→ ${actions.join(', ')}',
                  if (r['effective_date'] != null) 'from ${Fmt.day(r['effective_date'])}',
                ].join('\n')),
                isThreeLine: conds.isNotEmpty && actions.isNotEmpty,
              );
            },
          ),
          PagedList(
            fetch: (p) => SureApi.of(context).page('rule_runs', 'data', page: p, perPage: 50),
            empty: const EmptyView('No rule runs yet', icon: Icons.history),
            itemBuilder: (context, r) => ListTile(
              title: Text(r['rule_name']?.toString() ?? ''),
              subtitle: Text(
                  '${Fmt.dateTime(r['executed_at'])} · ${Fmt.humanize(r['execution_type']?.toString())}\n'
                  '${r['transactions_modified']} changed of ${r['transactions_processed']} processed'
                  '${r['error_message'] != null ? '\n${r['error_message']}' : ''}'),
              isThreeLine: true,
              trailing: StatusChip(Fmt.humanize(r['status']?.toString()),
                  color: statusColor(context, r['status']?.toString())),
            ),
          ),
        ]),
      ),
    );
  }

  String _actionValue(Map a) {
    final v = a['value']?.toString() ?? '';
    final type = a['action_type']?.toString() ?? '';
    if (type.contains('category')) return Lookups.instance.category(v)?['name']?.toString() ?? v;
    if (type.contains('tag')) return Lookups.instance.tag(v)?['name']?.toString() ?? v;
    if (type.contains('merchant')) return Lookups.instance.merchant(v)?['name']?.toString() ?? v;
    return v;
  }
}

// ───────────────────────────── Transfers ─────────────────────────────

class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key});

  Widget _leg(BuildContext context, Map? t) {
    if (t == null) return const SizedBox();
    return Text('${(t['account'] as Map?)?['name'] ?? ''}',
        maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Transfers'),
          bottom: const TabBar(tabs: [Tab(text: 'Matched'), Tab(text: 'Rejected')]),
        ),
        body: TabBarView(children: [
          PagedList(
            fetch: (p) => SureApi.of(context).page('transfers', 'transfers', page: p),
            groupBy: (m) => Fmt.day(m['date'], pattern: 'MMMM yyyy'),
            empty: const EmptyView('No transfers', icon: Icons.swap_horiz),
            itemBuilder: (context, t) => ListTile(
              leading: LetterAvatar('', icon: Icons.swap_horiz, color: palette.info),
              title: Row(children: [
                Flexible(child: _leg(context, t['outflow_transaction'] as Map?)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.arrow_forward, size: 14)),
                Flexible(child: _leg(context, t['inflow_transaction'] as Map?)),
              ]),
              subtitle: Text('${Fmt.day(t['date'])} · ${Fmt.humanize(t['transfer_type']?.toString())}'
                  '${t['status'] != 'confirmed' ? ' · ${Fmt.humanize(t['status']?.toString())}' : ''}'),
              trailing: Amount(Fmt.parse(t['amount']) ?? 0, t['currency']?.toString() ?? 'EUR',
                  colored: false, signed: false),
            ),
          ),
          PagedList(
            fetch: (p) => SureApi.of(context).page('rejected_transfers', 'rejected_transfers', page: p),
            empty: const EmptyView('No rejected transfer matches', icon: Icons.block),
            itemBuilder: (context, t) {
              final out = t['outflow_transaction'] as Map?;
              final inn = t['inflow_transaction'] as Map?;
              return ListTile(
                leading: const Icon(Icons.link_off),
                title: Text('${out?['name'] ?? ''} ↔ ${inn?['name'] ?? ''}'),
                subtitle: Text(
                    '${(out?['account'] as Map?)?['name'] ?? ''} → ${(inn?['account'] as Map?)?['name'] ?? ''} · ${Fmt.day(out?['date'])}'),
                trailing: Text(out?['amount']?.toString() ?? ''),
              );
            },
          ),
        ]),
      ),
    );
  }
}
