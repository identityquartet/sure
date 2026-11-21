import 'package:flutter/material.dart';

import 'api.dart';
import 'format.dart';
import 'lookups.dart';
import 'widgets.dart';

/// Create or edit a transaction (all fields the API accepts).
class TxnEditScreen extends StatefulWidget {
  const TxnEditScreen({super.key, this.existing, this.defaultAccountId});
  final Map<String, dynamic>? existing;
  final String? defaultAccountId;

  @override
  State<TxnEditScreen> createState() => _TxnEditScreenState();
}

class _TxnEditScreenState extends State<TxnEditScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String _nature = 'expense';
  DateTime _date = DateTime.now();
  String? _accountId;
  String? _categoryId;
  String? _merchantId;
  Set<String> _tagIds = {};
  bool _saving = false;
  bool _ready = false;
  late final bool _splitParent;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      final t = Txn(e);
      _name.text = t.name;
      _amount.text = t.absAmount.toStringAsFixed(2);
      _notes.text = t.notes ?? '';
      _nature = t.rawAmount < 0 ? 'income' : 'expense';
      _date = t.date;
      _accountId = t.accountId;
      _categoryId = t.categoryId;
      _merchantId = t.merchantId;
      _tagIds = t.tags.map((m) => m['id'].toString()).toSet();
      _splitParent = t.splitParent;
    } else {
      _accountId = widget.defaultAccountId;
      _splitParent = false;
    }
    Lookups.instance.load(context).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _ready = true;
        _accountId ??= Lookups.instance.accounts.isNotEmpty
            ? Lookups.instance.accounts.first['id'].toString()
            : null;
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_accountId == null) {
      toast(context, 'Choose an account', error: true);
      return;
    }
    setState(() => _saving = true);
    final api = SureApi.of(context);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'notes': _notes.text.trim(),
      if (!_splitParent) 'date': Fmt.iso(_date),
      if (!_splitParent) 'amount': _amount.text.trim().replaceAll(',', '.'),
      if (!_splitParent) 'nature': _nature,
      if (_categoryId != null) 'category_id': _categoryId,
      if (_merchantId != null) 'merchant_id': _merchantId,
      'tag_ids': _tagIds.toList(),
    };
    try {
      if (_editing) {
        await api.patch('transactions/${widget.existing!['id']}', {'transaction': body});
      } else {
        final acct = Lookups.instance.account(_accountId);
        await api.post('transactions', {
          'transaction': {
            ...body,
            'account_id': _accountId,
            if (acct?['currency'] != null) 'currency': acct!['currency'],
          }
        });
      }
      if (!mounted) return;
      toast(context, _editing ? 'Transaction updated' : 'Transaction added');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Lookups.instance;
    final acct = l.account(_accountId);
    final cat = l.category(_categoryId);
    final merch = l.merchant(_merchantId);
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit transaction' : 'New transaction'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
                if (!_splitParent)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'expense',
                            label: Text('Expense'),
                            icon: Icon(Icons.arrow_upward)),
                        ButtonSegment(
                            value: 'income',
                            label: Text('Income'),
                            icon: Icon(Icons.arrow_downward)),
                      ],
                      selected: {_nature},
                      onSelectionChanged: (s) => setState(() => _nature = s.first),
                    ),
                  ),
                if (_splitParent)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'This transaction is split. Amount and date are edited from the split editor.'),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextFormField(
                    controller: _amount,
                    enabled: !_splitParent,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: '${acct?['currency'] ?? ''} ',
                    ),
                    validator: (v) {
                      if (_splitParent) return null;
                      final d = double.tryParse((v ?? '').replaceAll(',', '.'));
                      if (d == null || d <= 0) return 'Enter an amount';
                      return null;
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Description'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('Account'),
                  subtitle: Text(acct?['name']?.toString() ?? 'Choose'),
                  enabled: !_editing,
                  onTap: () async {
                    final r = await pickOne(context,
                        title: 'Account',
                        items: l.accounts,
                        selectedId: _accountId,
                        subtitle: (a) => Fmt.humanize(a['account_type']?.toString()));
                    if (r != null && r['id'] != null) {
                      setState(() => _accountId = r['id'].toString());
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Date'),
                  subtitle: Text(Fmt.day(_date)),
                  enabled: !_splitParent,
                  onTap: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 366)));
                    if (d != null) setState(() => _date = d);
                  },
                ),
                ListTile(
                  leading: Dot(Fmt.hexColor(cat?['color']), size: 18),
                  title: const Text('Category'),
                  subtitle: Text(cat?['name']?.toString() ?? 'Uncategorized'),
                  onTap: () async {
                    final r = await pickOne(context,
                        title: 'Category',
                        items: l.categoriesTree(),
                        selectedId: _categoryId,
                        label: (c) => c['parent'] == null ? '${c['name']}' : '    ${c['name']}',
                        leading: (c) => Dot(Fmt.hexColor(c['color'])));
                    if (r != null && r['id'] != null) {
                      setState(() => _categoryId = r['id'].toString());
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('Merchant'),
                  subtitle: Text(merch?['name']?.toString() ?? 'None'),
                  onTap: () async {
                    final r = await pickOne(context,
                        title: 'Merchant', items: l.merchants, selectedId: _merchantId);
                    if (r != null && r['id'] != null) {
                      setState(() => _merchantId = r['id'].toString());
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.sell_outlined),
                  title: const Text('Tags'),
                  subtitle: Text(_tagIds.isEmpty
                      ? 'None'
                      : _tagIds.map((id) => l.tag(id)?['name'] ?? '…').join(', ')),
                  onTap: () async {
                    final r = await pickMany(context,
                        title: 'Tags',
                        items: l.tags,
                        selected: _tagIds,
                        leading: (t) => Dot(Fmt.hexColor(t['color'])));
                    if (r != null) setState(() => _tagIds = r);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextFormField(
                    controller: _notes,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                ),
              ]),
            ),
    );
  }
}
