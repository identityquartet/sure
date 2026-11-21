import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../theme/sure_colors.dart';
import 'api.dart';
import 'charts.dart';
import 'format.dart';
import 'lookups.dart';
import 'transactions_screen.dart';
import 'widgets.dart';

// ───────────────────────────── Spending vs normal ─────────────────────────────

class SpendingScreen extends StatefulWidget {
  const SpendingScreen({super.key});
  @override
  State<SpendingScreen> createState() => _SpendingScreenState();
}

class _SpendingScreenState extends State<SpendingScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  bool get _isCurrent {
    final n = DateTime.now();
    return _month.year == n.year && _month.month == n.month;
  }

  void _shift(int m) {
    setState(() => _month = DateTime(_month.year, _month.month + m));
    _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Spending vs normal')),
      body: Column(children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
          Expanded(
              child: Text(Fmt.day(_month, pattern: 'MMMM yyyy'),
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
          IconButton(
              icon: const Icon(Icons.chevron_right), onPressed: _isCurrent ? null : () => _shift(1)),
        ]),
        Expanded(
          child: AsyncView<Map<String, dynamic>>(
            key: _key,
            load: () async {
              final end = _isCurrent ? DateTime.now() : DateTime(_month.year, _month.month + 1, 0);
              final d = await SureApi.of(context).get('spending_vs_normal', {
                'start_date': Fmt.iso(_month),
                'end_date': Fmt.iso(end),
              });
              return Map<String, dynamic>.from(d as Map);
            },
            builder: (context, d) {
              final cur = d['currency']?.toString() ?? 'EUR';
              final total = Fmt.parse(d['total']) ?? 0;
              final normal = Fmt.parse(d['normal_total']) ?? 0;
              final cats = ((d['categories'] as List?) ?? []).cast<Map>();
              final maxV = cats.fold<double>(
                  1,
                  (m, c) => [m, Fmt.parse(c['total']) ?? 0, Fmt.parse(c['normal']) ?? 0]
                      .reduce((a, b) => a > b ? a : b));
              final diff = total - normal;
              return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Spent', style: TextStyle(color: palette.textSubdued)),
                    Amount(total, cur,
                        colored: false,
                        signed: false,
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                    if (d['comparable'] == true)
                      Row(children: [
                        Icon(diff > 0 ? Icons.trending_up : Icons.trending_down,
                            size: 18, color: diff > 0 ? palette.destructive : palette.success),
                        const SizedBox(width: 4),
                        Amount(diff.abs(), cur,
                            colored: false,
                            signed: false,
                            style: TextStyle(
                                color: diff > 0 ? palette.destructive : palette.success,
                                fontWeight: FontWeight.w600)),
                        Text(diff > 0 ? ' above normal' : ' below normal',
                            style: TextStyle(color: palette.textSecondary)),
                      ]),
                    if (d['baseline_period'] is Map)
                      Text(
                          'Normal = average of ${Fmt.day((d['baseline_period'] as Map)['start_date'], pattern: 'd MMM')} – ${Fmt.day((d['baseline_period'] as Map)['end_date'], pattern: 'd MMM')}${d['in_progress'] == true ? ', prorated' : ''}',
                          style: TextStyle(fontSize: 12, color: palette.textSubdued)),
                  ]),
                ),
                if (cats.isEmpty) const EmptyView('No spending in this period'),
                ...cats.map((c) {
                  final t = Fmt.parse(c['total']) ?? 0;
                  final n = Fmt.parse(c['normal']) ?? 0;
                  final change = t - n;
                  return InkWell(
                    onTap: c['id'] == null
                        ? null
                        : () => push(
                            context,
                            TransactionsScreen(
                                title: c['name'].toString(),
                                initial: TxnFilter()
                                  ..categoryIds = {c['id'].toString()}
                                  ..type = 'expense'
                                  ..start = _month
                                  ..end = DateTime(_month.year, _month.month + 1, 0))),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Dot(Fmt.hexColor(c['color'])),
                          const SizedBox(width: 8),
                          Expanded(child: Text(c['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w500))),
                          Amount(t, cur, colored: false, signed: false),
                        ]),
                        const SizedBox(height: 6),
                        ShareBar(fraction: t / maxV, marker: n / maxV, color: Fmt.hexColor(c['color'])),
                        const SizedBox(height: 4),
                        Text(
                            n == 0
                                ? 'New this period'
                                : '${change >= 0 ? '+' : '-'}${Fmt.money(change.abs(), cur)} vs normal ${Fmt.money(n, cur)}',
                            style: TextStyle(
                                fontSize: 12,
                                color: change > 0 ? palette.destructive : palette.textSubdued)),
                      ]),
                    ),
                  );
                }),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

// ───────────────────────────── Imports ─────────────────────────────

const importTypes = {
  'TransactionImport': 'Transactions (CSV)',
  'TradeImport': 'Trades (CSV)',
  'AccountImport': 'Accounts (CSV)',
  'CategoryImport': 'Categories (CSV)',
  'MerchantImport': 'Merchants (CSV)',
  'RuleImport': 'Rules (CSV)',
  'MintImport': 'Mint export',
  'ActualImport': 'Actual Budget export',
  'YnabImport': 'YNAB export',
  'QifImport': 'QIF file',
};

class ImportsScreen extends StatefulWidget {
  const ImportsScreen({super.key});
  @override
  State<ImportsScreen> createState() => _ImportsScreenState();
}

class _ImportsScreenState extends State<ImportsScreen> {
  final _key = GlobalKey<PagedListState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Imports')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.upload_file),
        label: const Text('New import'),
        onPressed: () async {
          await Lookups.instance.load(context).catchError((_) {});
          if (!context.mounted) return;
          final ok = await push<bool>(context, const NewImportScreen());
          if (ok == true) _key.currentState?.reload();
        },
      ),
      body: PagedList(
        key: _key,
        fetch: (p) => SureApi.of(context).page('imports', 'data', page: p),
        empty: const EmptyView('No imports', icon: Icons.upload_file),
        itemBuilder: (context, i) => ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(importTypes[i['type']] ?? i['type'].toString()),
          subtitle: Text(
              '${Fmt.dateTime(i['created_at'])} · ${i['rows_count'] ?? 0} rows${i['error'] != null ? '\n${i['error']}' : ''}'),
          trailing: StatusChip(Fmt.humanize(i['status']?.toString()),
              color: statusColor(context, i['status']?.toString())),
          onTap: () => push(context, ImportDetailScreen(id: i['id'].toString())),
        ),
      ),
    );
  }
}

class ImportDetailScreen extends StatelessWidget {
  const ImportDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Import')),
      body: AsyncView<List<dynamic>>(
        load: () async {
          final api = SureApi.of(context);
          final d = await api.get('imports/$id');
          final rows = await api.page('imports/$id/rows', 'data', perPage: 100);
          return [(d as Map)['data'], rows];
        },
        builder: (context, res) {
          final i = Map<String, dynamic>.from(res[0] as Map);
          final rows = res[1] as ApiPage;
          final sd = (i['status_detail'] as Map?) ?? {};
          final conf = (i['configuration'] as Map?) ?? {};
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            const SizedBox(height: 12),
            Panel(children: [
              KV('Type', importTypes[i['type']] ?? i['type']?.toString()),
              KV('Status', Fmt.humanize(i['status']?.toString())),
              KV('Created', Fmt.dateTime(i['created_at'])),
              if (i['account_id'] != null)
                KV('Account', Lookups.instance.account(i['account_id'].toString())?['name']?.toString()),
              ...sd.entries
                  .where((e) => e.value is! Map && e.value is! List && e.value != null)
                  .map((e) => KV(Fmt.humanize(e.key.toString()), e.value.toString())),
              if (i['error'] != null) KV('Error', i['error'].toString()),
            ]),
            if (conf.isNotEmpty) ...[
              const SectionTitle('Configuration'),
              Panel(
                  children: conf.entries
                      .where((e) => e.value != null && e.value.toString().isNotEmpty)
                      .map((e) => KV(Fmt.humanize(e.key.toString()), e.value.toString()))
                      .toList()),
            ],
            SectionTitle('Rows (${rows.totalCount ?? rows.items.length})'),
            ...rows.items.map((r) {
              final f = (r['fields'] as Map?) ?? {};
              final errors = (r['errors'] as List?) ?? [];
              return ListTile(
                dense: true,
                leading: Icon(r['valid'] == true ? Icons.check_circle_outline : Icons.error_outline,
                    color: r['valid'] == true ? palette.success : palette.destructive),
                title: Text([f['date'], f['name'] ?? f['ticker'] ?? f['account'], f['amount'] ?? f['qty']]
                    .where((e) => e != null && e.toString().isNotEmpty)
                    .join(' · ')),
                subtitle: errors.isEmpty
                    ? Text([f['category'], f['tags'], f['account']]
                        .where((e) => e != null && e.toString().isNotEmpty)
                        .join(' · '))
                    : Text(errors.join('; '), style: TextStyle(color: palette.destructive)),
              );
            }),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Mapping and publishing of imports is done in the Sure web app.',
                  style: TextStyle(fontSize: 12, color: palette.textSubdued)),
            ),
          ]);
        },
      ),
    );
  }
}

class NewImportScreen extends StatefulWidget {
  const NewImportScreen({super.key});
  @override
  State<NewImportScreen> createState() => _NewImportScreenState();
}

class _NewImportScreenState extends State<NewImportScreen> {
  String _type = 'TransactionImport';
  String? _accountId;
  String? _fileName;
  String? _content;
  final _date = TextEditingController(text: 'date');
  final _amount = TextEditingController(text: 'amount');
  final _name = TextEditingController(text: 'name');
  final _category = TextEditingController(text: 'category');
  final _tags = TextEditingController(text: 'tags');
  final _notes = TextEditingController(text: 'notes');
  String _dateFormat = '%Y-%m-%d';
  String _numberFormat = '1,234.56';
  String _signage = 'inflows_positive';
  String _colSep = ',';
  bool _publish = false;
  bool _saving = false;
  List<String> _headers = [];

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(withData: true, type: FileType.any);
    final f = res?.files.single;
    if (f == null || f.bytes == null) return;
    final text = utf8.decode(f.bytes!, allowMalformed: true);
    final firstLine = text.split(RegExp(r'\r?\n')).first;
    final sep = firstLine.split(';').length > firstLine.split(',').length ? ';' : ',';
    setState(() {
      _fileName = f.name;
      _content = text;
      _colSep = sep;
      _headers = firstLine.split(sep).map((h) => h.trim().replaceAll('"', '')).toList();
      String? guess(List<String> keys) {
        for (final h in _headers) {
          if (keys.any((k) => h.toLowerCase().contains(k))) return h;
        }
        return null;
      }

      _date.text = guess(['date']) ?? _date.text;
      _amount.text = guess(['amount', 'value']) ?? _amount.text;
      _name.text = guess(['name', 'description', 'payee', 'merchant']) ?? _name.text;
      _category.text = guess(['category']) ?? '';
      _tags.text = guess(['tag']) ?? '';
      _notes.text = guess(['note', 'memo']) ?? '';
    });
  }

  Future<void> _submit() async {
    if (_content == null) {
      toast(context, 'Choose a file first', error: true);
      return;
    }
    setState(() => _saving = true);
    final isCsvTxn = _type == 'TransactionImport' || _type == 'TradeImport';
    try {
      final res = await SureApi.of(context).post('imports', {
        'type': _type,
        'raw_file_content': _content,
        if (_accountId != null) 'account_id': _accountId,
        if (isCsvTxn) ...{
          'date_col_label': _date.text.trim(),
          'amount_col_label': _amount.text.trim(),
          'name_col_label': _name.text.trim(),
          if (_category.text.trim().isNotEmpty) 'category_col_label': _category.text.trim(),
          if (_tags.text.trim().isNotEmpty) 'tags_col_label': _tags.text.trim(),
          if (_notes.text.trim().isNotEmpty) 'notes_col_label': _notes.text.trim(),
          'date_format': _dateFormat,
          'number_format': _numberFormat,
          'signage_convention': _signage,
        },
        'col_sep': _colSep,
        if (_publish) 'publish': 'true',
      });
      if (!mounted) return;
      final status = ((res as Map?)?['data'] as Map?)?['status'];
      toast(context, 'Import created${status != null ? ' ($status)' : ''}');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _col(String label, TextEditingController c) {
    if (_headers.isEmpty) {
      return TextField(controller: c, decoration: InputDecoration(labelText: label));
    }
    return DropdownButtonFormField<String>(
      value: _headers.contains(c.text) ? c.text : null,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: '', child: Text('— none —')),
        ..._headers.map((h) => DropdownMenuItem(value: h, child: Text(h))),
      ],
      onChanged: (v) => setState(() => c.text = v ?? ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Lookups.instance;
    final isCsvTxn = _type == 'TransactionImport' || _type == 'TradeImport';
    return Scaffold(
      appBar: AppBar(title: const Text('New import')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<String>(
          value: _type,
          decoration: const InputDecoration(labelText: 'What are you importing?'),
          items: importTypes.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => setState(() => _type = v ?? 'TransactionImport'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.attach_file),
          label: Text(_fileName ?? 'Choose file'),
        ),
        if (_headers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Columns: ${_headers.join(', ')}',
                style: TextStyle(fontSize: 12, color: SureColors.of(context).palette.textSubdued)),
          ),
        if (isCsvTxn) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Into account'),
            subtitle: Text(l.account(_accountId)?['name']?.toString() ?? 'Taken from an account column'),
            onTap: () async {
              final r = await pickOne(context,
                  title: 'Account',
                  items: l.accounts,
                  selectedId: _accountId,
                  allowNone: true,
                  noneLabel: 'Use account column');
              if (r != null) setState(() => _accountId = r['id']?.toString());
            },
          ),
          const SectionTitle('Columns'),
          _col('Date column', _date),
          _col('Amount column', _amount),
          _col('Name column', _name),
          _col('Category column', _category),
          _col('Tags column', _tags),
          _col('Notes column', _notes),
          const SectionTitle('Format'),
          DropdownButtonFormField<String>(
            value: _dateFormat,
            decoration: const InputDecoration(labelText: 'Date format'),
            items: const ['%Y-%m-%d', '%d/%m/%Y', '%m/%d/%Y', '%d-%m-%Y', '%d.%m.%Y', '%Y/%m/%d']
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (v) => setState(() => _dateFormat = v!),
          ),
          DropdownButtonFormField<String>(
            value: _numberFormat,
            decoration: const InputDecoration(labelText: 'Number format'),
            items: const ['1,234.56', '1.234,56', '1 234,56', '1,234']
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (v) => setState(() => _numberFormat = v!),
          ),
          DropdownButtonFormField<String>(
            value: _signage,
            decoration: const InputDecoration(labelText: 'Amount sign'),
            items: const [
              DropdownMenuItem(value: 'inflows_positive', child: Text('Income is positive')),
              DropdownMenuItem(value: 'inflows_negative', child: Text('Expenses are positive')),
            ],
            onChanged: (v) => setState(() => _signage = v!),
          ),
        ],
        DropdownButtonFormField<String>(
          value: _colSep,
          decoration: const InputDecoration(labelText: 'Separator'),
          items: const [
            DropdownMenuItem(value: ',', child: Text('Comma (,)')),
            DropdownMenuItem(value: ';', child: Text('Semicolon (;)')),
          ],
          onChanged: (v) => setState(() => _colSep = v!),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Publish immediately if valid'),
          subtitle: const Text('Otherwise review and publish in the web app'),
          value: _publish,
          onChanged: (v) => setState(() => _publish = v),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _saving ? null : _submit, child: const Text('Upload')),
      ]),
    );
  }
}

// ───────────────────────────── Exports ─────────────────────────────

class ExportsScreen extends StatefulWidget {
  const ExportsScreen({super.key});
  @override
  State<ExportsScreen> createState() => _ExportsScreenState();
}

class _ExportsScreenState extends State<ExportsScreen> {
  final _key = GlobalKey<PagedListState>();

  Future<void> _download(Map<String, dynamic> e) async {
    final api = SureApi.of(context);
    toast(context, 'Downloading…');
    try {
      final Uint8List bytes = await api.download('family_exports/${e['id']}/download');
      final name = e['filename']?.toString() ?? 'sure-export.zip';
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Save export', fileName: name, bytes: bytes);
      if (mounted) toast(context, path == null ? 'Not saved' : 'Saved $name');
    } catch (err) {
      if (mounted) toast(context, err.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data export')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.archive_outlined),
        label: const Text('New export'),
        onPressed: () async {
          final ok = await guarded(context, () => SureApi.of(context).post('family_exports'),
              success: 'Export started. Pull to refresh in a moment.');
          if (ok) _key.currentState?.reload();
        },
      ),
      body: PagedList(
        key: _key,
        fetch: (p) => SureApi.of(context).page('family_exports', 'data', page: p),
        empty: const EmptyView('No exports yet',
            icon: Icons.archive_outlined,
            hint: 'An export is a ZIP of all your accounts, transactions and settings.'),
        itemBuilder: (context, e) {
          final file = (e['file'] as Map?) ?? {};
          return ListTile(
            leading: const Icon(Icons.folder_zip_outlined),
            title: Text(e['filename']?.toString() ?? 'Export'),
            subtitle: Text('${Fmt.dateTime(e['created_at'])}'
                '${file['byte_size'] != null ? ' · ${Fmt.bytes(file['byte_size'])}' : ''}'),
            trailing: e['downloadable'] == true
                ? IconButton(icon: const Icon(Icons.download), onPressed: () => _download(e))
                : StatusChip(Fmt.humanize(e['status']?.toString()),
                    color: statusColor(context, e['status']?.toString())),
          );
        },
      ),
    );
  }
}

// ───────────────────────────── Sync & server ─────────────────────────────

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _key = GlobalKey<AsyncViewState<List<dynamic>>>();
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    await guarded(context, () => SureApi.of(context).post('sync'), success: 'Sync started');
    if (mounted) setState(() => _syncing = false);
    await Future.delayed(const Duration(seconds: 3));
    _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync & server')),
      body: AsyncView<List<dynamic>>(
        key: _key,
        load: () async {
          final api = SureApi.of(context);
          Future<dynamic> safe(Future<dynamic> f) => f.catchError((_) => null);
          return Future.wait([
            safe(api.get('syncs/latest')),
            safe(api.page('syncs', 'data', perPage: 20)),
            safe(api.get('family_settings')),
            safe(api.get('provider_connections')),
            safe(api.get('usage')),
          ]);
        },
        builder: (context, r) {
          final latest = (r[0] as Map?)?['data'] as Map?;
          final syncs = (r[1] as ApiPage?)?.items ?? [];
          final fam = r[2] as Map?;
          final conns = ((r[3] as Map?)?['data'] as List?) ?? [];
          final usage = r[4] as Map?;
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _syncing ? null : _sync,
                icon: _syncing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: const Text('Sync all accounts now'),
              ),
            ),
            if (latest != null) ...[
              const SectionTitle('Latest sync'),
              Panel(children: [
                KV('Status', null,
                    valueWidget: Align(
                        alignment: Alignment.centerRight,
                        child: StatusChip(Fmt.humanize(latest['status']?.toString()),
                            color: statusColor(context, latest['status']?.toString())))),
                KV('What', (latest['syncable'] as Map?)?['name']?.toString()),
                KV('Finished', Fmt.dateTime(latest['completed_at'] ?? latest['failed_at'])),
                if (latest['error'] != null) KV('Error', latest['error'].toString()),
              ]),
            ],
            if (conns.isNotEmpty) ...[
              const SectionTitle('Bank connections'),
              Panel(
                children: conns.map((c) {
                  final m = c as Map;
                  return ListTile(
                    leading: const Icon(Icons.link),
                    title: Text(m['name']?.toString() ?? m['provider']?.toString() ?? 'Connection'),
                    subtitle: Text([
                      if (m['provider'] != null) Fmt.humanize(m['provider'].toString()),
                      if (m['last_synced_at'] != null) 'synced ${Fmt.dateTime(m['last_synced_at'])}',
                    ].join(' · ')),
                    trailing: m['status'] == null
                        ? null
                        : StatusChip(Fmt.humanize(m['status'].toString()),
                            color: statusColor(context, m['status'].toString())),
                  );
                }).toList(),
              ),
            ],
            if (syncs.isNotEmpty) ...[
              const SectionTitle('Recent syncs'),
              Panel(
                children: syncs.map((s) {
                  return ListTile(
                    dense: true,
                    title: Text('${(s['syncable'] as Map?)?['type'] ?? ''}: ${(s['syncable'] as Map?)?['name'] ?? ''}'),
                    subtitle: Text(Fmt.dateTime(s['created_at'])),
                    trailing: StatusChip(Fmt.humanize(s['status']?.toString()),
                        color: statusColor(context, s['status']?.toString())),
                  );
                }).toList(),
              ),
            ],
            if (fam != null) ...[
              const SectionTitle('Household settings'),
              Panel(children: [
                KV('Name', fam['name']?.toString()),
                KV('Currency', fam['currency']?.toString()),
                KV('Country', fam['country']?.toString()),
                KV('Locale', fam['locale']?.toString()),
                KV('Date format', fam['date_format']?.toString()),
                KV('Month starts', fam['month_start_day']?.toString()),
                KV('Timezone', fam['timezone']?.toString()),
              ]),
            ],
            if (usage != null && usage['api_key'] is Map) ...[
              const SectionTitle('API key'),
              Panel(children: [
                KV('Name', (usage['api_key'] as Map)['name']?.toString()),
                KV('Scopes', ((usage['api_key'] as Map)['scopes'] as List?)?.join(', ')),
                KV('Created', Fmt.dateTime((usage['api_key'] as Map)['created_at'])),
              ]),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Settings are read-only here; change them in the Sure web app.',
                  style: TextStyle(fontSize: 12, color: palette.textSubdued)),
            ),
          ]);
        },
      ),
    );
  }
}
