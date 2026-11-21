import 'package:flutter/material.dart';

import '../theme/sure_colors.dart';
import 'api.dart';
import 'charts.dart';
import 'format.dart';
import 'lookups.dart';
import 'transactions_screen.dart';
import 'widgets.dart';

const _typeOrder = [
  'depository',
  'investment',
  'crypto',
  'property',
  'vehicle',
  'other_asset',
  'credit_card',
  'loan',
  'other_liability',
];

String accountTypeLabel(String? t) {
  switch (t) {
    case 'depository':
      return 'Cash';
    case 'investment':
      return 'Investments';
    case 'crypto':
      return 'Crypto';
    case 'property':
      return 'Property';
    case 'vehicle':
      return 'Vehicles';
    case 'other_asset':
      return 'Other assets';
    case 'credit_card':
      return 'Credit cards';
    case 'loan':
      return 'Loans';
    case 'other_liability':
      return 'Other liabilities';
    default:
      return Fmt.humanize(t);
  }
}

IconData accountTypeIcon(String? t) {
  switch (t) {
    case 'depository':
      return Icons.account_balance_outlined;
    case 'investment':
      return Icons.show_chart;
    case 'crypto':
      return Icons.currency_bitcoin;
    case 'property':
      return Icons.home_outlined;
    case 'vehicle':
      return Icons.directions_car_outlined;
    case 'credit_card':
      return Icons.credit_card;
    case 'loan':
      return Icons.request_quote_outlined;
    default:
      return Icons.account_balance_wallet_outlined;
  }
}

/// All accounts grouped by type with group totals.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: AsyncView<List<Map<String, dynamic>>>(
        load: () => SureApi.of(context).all('accounts', 'accounts'),
        builder: (context, accounts) {
          if (accounts.isEmpty) return const EmptyView('No accounts');
          final groups = <String, List<Map<String, dynamic>>>{};
          for (final a in accounts) {
            groups.putIfAbsent(a['account_type']?.toString() ?? 'other', () => []).add(a);
          }
          final keys = groups.keys.toList()
            ..sort((a, b) {
              final ia = _typeOrder.indexOf(a), ib = _typeOrder.indexOf(b);
              return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
            });
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            for (final k in keys) ...[
              Builder(builder: (context) {
                final list = groups[k]!..sort((a, b) => (Fmt.parse(b['balance']) ?? 0).abs().compareTo((Fmt.parse(a['balance']) ?? 0).abs()));
                final cur = list.first['currency']?.toString() ?? 'EUR';
                final sameCur = list.every((a) => a['currency'] == cur);
                final total = list.fold<double>(0, (s, a) => s + (Fmt.parse(a['balance']) ?? 0));
                return SectionTitle(accountTypeLabel(k),
                    action: sameCur
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Amount(total, cur,
                                colored: false,
                                signed: false,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: palette.textSubdued)),
                          )
                        : null);
              }),
              Panel(
                children: groups[k]!.map((a) {
                  final bal = Fmt.parse(a['balance']) ?? 0;
                  final status = a['status']?.toString();
                  return ListTile(
                    leading: LetterAvatar(a['name'].toString(),
                        icon: accountTypeIcon(k), color: palette.textSecondary),
                    title: Text(a['name'].toString()),
                    subtitle: Text([
                      if (a['subtype'] != null) Fmt.humanize(a['subtype'].toString()),
                      if (a['institution_name'] != null) a['institution_name'].toString(),
                      if (status != null && status != 'active') Fmt.humanize(status),
                    ].join(' · ')),
                    trailing: Amount(bal, a['currency'].toString(), colored: false, signed: false),
                    onTap: () => push(context, AccountDetailScreen(account: a)),
                  );
                }).toList(),
              ),
            ],
          ]);
        },
      ),
    );
  }
}

class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.account});
  final Map<String, dynamic> account;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  late Map<String, dynamic> a = widget.account;
  String _range = '3M';
  List<ChartPoint>? _points;
  Object? _chartError;

  String get id => a['id'].toString();
  String get currency => a['currency']?.toString() ?? 'EUR';
  bool get isInvestment => const {'investment', 'crypto'}.contains(a['account_type']);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final api = SureApi.of(context);
    try {
      final fresh = await api.get('accounts/$id');
      if (mounted) setState(() => a = Map<String, dynamic>.from(fresh as Map));
    } catch (_) {}
    await _loadChart();
  }

  DateTime? get _start {
    final now = DateTime.now();
    switch (_range) {
      case '1M':
        return now.subtract(const Duration(days: 31));
      case '3M':
        return now.subtract(const Duration(days: 92));
      case '6M':
        return now.subtract(const Duration(days: 183));
      case '1Y':
        return now.subtract(const Duration(days: 366));
      case '5Y':
        return now.subtract(const Duration(days: 365 * 5));
      default:
        return null;
    }
  }

  Future<void> _loadChart() async {
    setState(() {
      _points = null;
      _chartError = null;
    });
    try {
      final rows = await SureApi.of(context).all('balances', 'balances',
          perPage: 100,
          maxPages: 20,
          query: {
            'account_id': id,
            if (_start != null) 'start_date': Fmt.iso(_start!),
          });
      final byDate = <String, double>{};
      for (final r in rows) {
        final d = r['date']?.toString();
        if (d == null) continue;
        byDate.putIfAbsent(d, () {
          final cents = r['end_balance_cents'] ?? r['balance_cents'];
          if (cents is num) return cents / 100.0;
          return Fmt.parse(r['end_balance'] ?? r['balance']) ?? 0;
        });
      }
      final pts = byDate.entries
          .map((e) => ChartPoint(DateTime.parse(e.key), e.value))
          .toList()
        ..sort((x, y) => x.date.compareTo(y.date));
      if (mounted) setState(() => _points = pts);
    } catch (e) {
      if (mounted) setState(() => _chartError = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final bal = Fmt.parse(a['balance']) ?? 0;
    final tabs = <Tab>[
      const Tab(text: 'Activity'),
      const Tab(text: 'Valuations'),
      if (isInvestment) const Tab(text: 'Holdings'),
      if (isInvestment) const Tab(text: 'Trades'),
      const Tab(text: 'Info'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(title: Text(a['name'].toString())),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(accountTypeLabel(a['account_type']?.toString()),
                      style: TextStyle(color: palette.textSubdued)),
                  Amount(bal, currency,
                      colored: false,
                      signed: false,
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                  if (a['cash_balance'] != null && a['cash_balance'] != a['balance'])
                    Row(children: [
                      Text('Cash ', style: TextStyle(color: palette.textSubdued)),
                      Amount(Fmt.parse(a['cash_balance']) ?? 0, currency,
                          colored: false, signed: false, style: const TextStyle()),
                    ]),
                  const SizedBox(height: 8),
                  _chartError != null
                      ? SizedBox(height: 120, child: Center(child: Text(_chartError.toString())))
                      : (_points == null
                          ? const SizedBox(
                              height: 204, child: Center(child: CircularProgressIndicator()))
                          : LineChart(_points!, currency: currency)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [
                      for (final r in const ['1M', '3M', '6M', '1Y', '5Y', 'All'])
                        ButtonSegment(value: r, label: Text(r)),
                    ],
                    selected: {_range},
                    onSelectionChanged: (s) {
                      setState(() => _range = s.first);
                      _loadChart();
                    },
                  ),
                ]),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabHeader(TabBar(isScrollable: tabs.length > 4, tabs: tabs),
                  Theme.of(context).scaffoldBackgroundColor),
            ),
          ],
          body: TabBarView(children: [
            TransactionsScreen(
                embedded: true, title: a['name'].toString(), initial: TxnFilter()..accountIds = {id}),
            _ValuationsTab(account: a, onChanged: _refresh),
            if (isInvestment) _HoldingsTab(accountId: id),
            if (isInvestment) _TradesTab(account: a, onChanged: _refresh),
            _InfoTab(account: a),
          ]),
        ),
      ),
    );
  }
}

class _TabHeader extends SliverPersistentHeaderDelegate {
  _TabHeader(this.bar, this.bg);
  final TabBar bar;
  final Color bg;
  @override
  double get minExtent => bar.preferredSize.height;
  @override
  double get maxExtent => bar.preferredSize.height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: bg, child: bar);
  @override
  bool shouldRebuild(covariant _TabHeader old) => old.bar != bar;
}

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.account});
  final Map<String, dynamic> account;

  @override
  Widget build(BuildContext context) {
    final a = account;
    return ListView(padding: const EdgeInsets.symmetric(vertical: 16), children: [
      Panel(children: [
        KV('Name', a['name']?.toString()),
        KV('Type', accountTypeLabel(a['account_type']?.toString())),
        KV('Subtype', Fmt.humanize(a['subtype']?.toString())),
        KV('Classification', Fmt.humanize(a['classification']?.toString())),
        KV('Currency', a['currency']?.toString()),
        KV('Status', Fmt.humanize(a['status']?.toString())),
        KV('Institution', a['institution_name']?.toString()),
        KV('Created', Fmt.dateTime(a['created_at'])),
        KV('Updated', Fmt.dateTime(a['updated_at'])),
      ]),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
            'Renaming, creating and deleting accounts is only available in the Sure web app (the API does not expose it).',
            style: TextStyle(fontSize: 12, color: SureColors.of(context).palette.textSubdued)),
      ),
    ]);
  }
}

class _ValuationsTab extends StatefulWidget {
  const _ValuationsTab({required this.account, required this.onChanged});
  final Map<String, dynamic> account;
  final VoidCallback onChanged;

  @override
  State<_ValuationsTab> createState() => _ValuationsTabState();
}

class _ValuationsTabState extends State<_ValuationsTab> {
  final _key = GlobalKey<PagedListState>();

  Future<void> _edit([Map<String, dynamic>? v]) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ValuationSheet(account: widget.account, existing: v),
    );
    if (ok == true) {
      _key.currentState?.reload();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.account['id'].toString();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'val-add',
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Update balance'),
      ),
      body: PagedList(
        key: _key,
        fetch: (p) => SureApi.of(context)
            .page('valuations', 'valuations', page: p, query: {'account_id': id}),
        empty: const EmptyView('No valuations',
            hint: 'Record the balance on a date to correct the account history.',
            icon: Icons.timeline),
        itemBuilder: (context, v) => ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: Amount(Fmt.parse(v['amount']) ?? 0, v['currency']?.toString() ?? 'EUR',
              colored: false, signed: false),
          subtitle: Text([
            Fmt.day(v['date']),
            Fmt.humanize(v['kind']?.toString()),
            if (v['notes'] != null) v['notes'].toString(),
          ].where((s) => s.isNotEmpty).join(' · ')),
          onTap: () => _edit(v),
        ),
      ),
    );
  }
}

class ValuationSheet extends StatefulWidget {
  const ValuationSheet({super.key, required this.account, this.existing});
  final Map<String, dynamic> account;
  final Map<String, dynamic>? existing;

  @override
  State<ValuationSheet> createState() => _ValuationSheetState();
}

class _ValuationSheetState extends State<ValuationSheet> {
  late final _amount = TextEditingController(
      text: widget.existing == null
          ? ''
          : (Fmt.parse(widget.existing!['amount']) ?? 0).toStringAsFixed(2));
  late final _notes = TextEditingController(text: widget.existing?['notes']?.toString() ?? '');
  late DateTime _date =
      DateTime.tryParse(widget.existing?['date']?.toString() ?? '') ?? DateTime.now();
  bool _saving = false;

  Future<void> _save() async {
    final amt = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (amt == null) {
      toast(context, 'Enter a balance', error: true);
      return;
    }
    setState(() => _saving = true);
    final api = SureApi.of(context);
    final body = {
      'amount': amt.toStringAsFixed(2),
      'date': Fmt.iso(_date),
      'notes': _notes.text.trim(),
    };
    try {
      if (widget.existing == null) {
        await api.post('valuations', {
          'valuation': {...body, 'account_id': widget.account['id']},
          'upsert': true,
        });
      } else {
        await api.patch('valuations/${widget.existing!['id']}', {'valuation': body});
      }
      if (mounted) {
        toast(context, 'Balance saved');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.existing == null ? 'Update balance' : 'Edit valuation',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(
              labelText: 'Balance', prefixText: '${widget.account['currency'] ?? ''} '),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(Fmt.day(_date)),
          onTap: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now());
            if (d != null) setState(() => _date = d);
          },
        ),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes')),
        const SizedBox(height: 16),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ]),
    );
  }
}

class _HoldingsTab extends StatelessWidget {
  const _HoldingsTab({required this.accountId});
  final String accountId;

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<Map<String, dynamic>>>(
      load: () async {
        final rows = await SureApi.of(context)
            .all('holdings', 'holdings', query: {'account_id': accountId});
        // Keep the latest row per security.
        final latest = <String, Map<String, dynamic>>{};
        for (final h in rows) {
          final sec = (h['security'] as Map?)?['id']?.toString() ?? h['id'].toString();
          final cur = latest[sec];
          if (cur == null || (h['date']?.toString() ?? '').compareTo(cur['date']?.toString() ?? '') > 0) {
            latest[sec] = h;
          }
        }
        final list = latest.values.toList()
          ..sort((x, y) => (Fmt.parse(y['amount']) ?? 0).compareTo(Fmt.parse(x['amount']) ?? 0));
        return list;
      },
      builder: (context, list) {
        if (list.isEmpty) return const EmptyView('No holdings', icon: Icons.pie_chart_outline);
        final total = list.fold<double>(0, (s, h) => s + (Fmt.parse(h['amount']) ?? 0));
        return ListView(children: list.map((h) {
          final sec = (h['security'] as Map?) ?? {};
          final amt = Fmt.parse(h['amount']) ?? 0;
          return ListTile(
            leading: LetterAvatar(sec['ticker']?.toString() ?? '?'),
            title: Text(sec['ticker']?.toString() ?? ''),
            subtitle: Text(
                '${sec['name'] ?? ''}\n${h['qty']} × ${h['price']}${h['avg_cost'] != null ? ' · avg ${h['avg_cost']}' : ''}'),
            isThreeLine: true,
            trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Amount(amt, h['currency']?.toString() ?? 'EUR', colored: false, signed: false),
                  Text(total == 0 ? '' : '${(amt / total * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 12, color: SureColors.of(context).palette.textSubdued)),
                ]),
          );
        }).toList());
      },
    );
  }
}

class _TradesTab extends StatefulWidget {
  const _TradesTab({required this.account, required this.onChanged});
  final Map<String, dynamic> account;
  final VoidCallback onChanged;

  @override
  State<_TradesTab> createState() => _TradesTabState();
}

class _TradesTabState extends State<_TradesTab> {
  final _key = GlobalKey<PagedListState>();

  Future<void> _new() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TradeSheet(account: widget.account),
    );
    if (ok == true) {
      _key.currentState?.reload();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.account['id'].toString();
    return Scaffold(
      floatingActionButton: FloatingActionButton(
          heroTag: 'trade-add', onPressed: _new, child: const Icon(Icons.add)),
      body: PagedList(
        key: _key,
        fetch: (p) =>
            SureApi.of(context).page('trades', 'trades', page: p, query: {'account_id': id}),
        empty: const EmptyView('No trades', icon: Icons.swap_vert),
        itemBuilder: (context, t) => ListTile(
          title: Text(t['name']?.toString() ?? ''),
          subtitle: Text(
              '${Fmt.day(t['date'])} · ${t['investment_activity_label'] ?? ''} · ${t['qty']} @ ${t['price']}'),
          trailing: Text(t['amount']?.toString() ?? ''),
          onLongPress: () async {
            if (!await confirm(context, 'Delete trade?')) return;
            if (!context.mounted) return;
            final ok = await guarded(context, () => SureApi.of(context).delete('trades/${t['id']}'),
                success: 'Trade deleted');
            if (ok) {
              _key.currentState?.reload();
              widget.onChanged();
            }
          },
        ),
      ),
    );
  }
}

class TradeSheet extends StatefulWidget {
  const TradeSheet({super.key, required this.account});
  final Map<String, dynamic> account;

  @override
  State<TradeSheet> createState() => _TradeSheetState();
}

class _TradeSheetState extends State<TradeSheet> {
  String _type = 'buy';
  final _ticker = TextEditingController();
  final _qty = TextEditingController();
  final _price = TextEditingController();
  final _amount = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  static const _security = {'buy', 'sell', 'reinvestment', 'sweep_in', 'sweep_out'};
  bool get _needsSecurity => _security.contains(_type);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await SureApi.of(context).post('trades', {
        'trade': {
          'account_id': widget.account['id'],
          'type': _type,
          'date': Fmt.iso(_date),
          'currency': widget.account['currency'],
          if (_needsSecurity) 'ticker': _ticker.text.trim().toUpperCase(),
          if (_needsSecurity) 'qty': _qty.text.trim(),
          if (_needsSecurity) 'price': _price.text.trim(),
          if (!_needsSecurity) 'amount': _amount.text.trim(),
        }
      });
      if (mounted) {
        toast(context, 'Trade added');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('New trade', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: const [
            'buy', 'sell', 'dividend', 'interest', 'fee', 'deposit', 'withdrawal', 'reinvestment'
          ].map((t) => DropdownMenuItem(value: t, child: Text(Fmt.humanize(t)))).toList(),
          onChanged: (v) => setState(() => _type = v ?? 'buy'),
        ),
        if (_needsSecurity) ...[
          TextField(controller: _ticker, decoration: const InputDecoration(labelText: 'Ticker')),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Quantity'))),
            const SizedBox(width: 12),
            Expanded(
                child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Price'))),
          ]),
        ] else
          TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount')),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(Fmt.day(_date)),
          onTap: () async {
            final d = await showDatePicker(
                context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime.now());
            if (d != null) setState(() => _date = d);
          },
        ),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ]),
    );
  }
}

/// Unused helper to keep lookups warm when opening accounts first.
Future<void> warmLookups(BuildContext context) => Lookups.instance.load(context);
