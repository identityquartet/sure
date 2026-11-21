import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/privacy_provider.dart';
import '../theme/sure_colors.dart';
import '../utils/money_masker.dart';
import 'api.dart';
import 'format.dart';

void toast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? SureColors.of(context).palette.destructive : null,
  ));
}

Future<bool> confirm(BuildContext context, String title,
    {String? message, String action = 'Delete', bool destructive = true}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: SureColors.of(ctx).palette.destructive)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return res == true;
}

/// Runs [action], showing a snackbar on failure. Returns true on success.
Future<bool> guarded(BuildContext context, Future<void> Function() action,
    {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) toast(context, success);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, e.toString(), error: true);
    return false;
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView(this.error, {super.key, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 48, color: palette.destructive),
        const SizedBox(height: 12),
        Text(error.toString(), textAlign: TextAlign.center),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          Center(child: OutlinedButton(onPressed: onRetry, child: const Text('Retry'))),
        ],
      ]),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.text, {super.key, this.icon = Icons.inbox_outlined, this.hint});
  final String text;
  final String? hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 56, color: palette.textSubdued),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint!, textAlign: TextAlign.center, style: TextStyle(color: palette.textSubdued)),
        ],
      ]),
    );
  }
}

/// Loads data with [load] and rebuilds with [builder]; pull-to-refresh and
/// retry included. Call `key.currentState.reload()` to refresh from outside.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<AsyncView<T>> createState() => AsyncViewState<T>();
}

class AsyncViewState<T> extends State<AsyncView<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_loading && _data == null) {
      child = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _data == null) {
      child = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [ErrorView(_error!, onRetry: reload)]);
    } else {
      child = widget.builder(context, _data as T);
    }
    return RefreshIndicator(onRefresh: reload, child: child);
  }
}

/// Infinite-scrolling list over a paginated endpoint.
class PagedList extends StatefulWidget {
  const PagedList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.header,
    this.empty,
    this.groupBy,
    this.groupHeader,
    this.padding = const EdgeInsets.only(bottom: 96),
    this.onLoaded,
  });

  final Future<ApiPage> Function(int page) fetch;
  final Widget Function(BuildContext context, Map<String, dynamic> item) itemBuilder;
  final Widget? header;
  final Widget? empty;
  final String Function(Map<String, dynamic> item)? groupBy;
  final Widget Function(BuildContext context, String group, List<Map<String, dynamic>> items)?
      groupHeader;
  final EdgeInsets padding;
  final void Function(List<Map<String, dynamic>> items, int? total)? onLoaded;

  @override
  State<PagedList> createState() => PagedListState();
}

class PagedListState extends State<PagedList> {
  final _items = <Map<String, dynamic>>[];
  final _ids = <String>{};
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  int? _total;
  int _generation = 0;
  final _scroll = ScrollController();

  List<Map<String, dynamic>> get items => List.unmodifiable(_items);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    _generation++;
    setState(() {
      _items.clear();
      _ids.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
      _loading = false;
    });
    await _loadMore();
  }

  void removeWhere(bool Function(Map<String, dynamic>) test) {
    setState(() => _items.removeWhere(test));
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final res = await widget.fetch(_page + 1);
      if (!mounted || gen != _generation) return;
      setState(() {
        for (final item in res.items) {
          final id = item['id']?.toString();
          if (id == null || _ids.add(id)) _items.add(item);
        }
        _page = res.page;
        _total = res.totalCount;
        _hasMore = res.hasMore && res.items.isNotEmpty;
        _loading = false;
      });
      widget.onLoaded?.call(_items, _total);
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (widget.header != null) rows.add(widget.header!);
    if (_items.isEmpty && !_loading && _error == null) {
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: widget.padding,
          children: [...rows, widget.empty ?? const EmptyView('Nothing here yet')],
        ),
      );
    }
    String? lastGroup;
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (widget.groupBy != null) {
        final g = widget.groupBy!(item);
        if (g != lastGroup) {
          lastGroup = g;
          final groupItems = _items.where((e) => widget.groupBy!(e) == g).toList();
          rows.add(widget.groupHeader?.call(context, g, groupItems) ?? GroupHeader(g));
        }
      }
      rows.add(widget.itemBuilder(context, item));
    }
    if (_loading) {
      rows.add(const Padding(
          padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
    } else if (_error != null) {
      rows.add(Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(_error.toString(), textAlign: TextAlign.center),
          TextButton(
              onPressed: () {
                setState(() => _error = null);
                _loadMore();
              },
              child: const Text('Retry')),
        ]),
      ));
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        children: rows,
      ),
    );
  }
}

class GroupHeader extends StatelessWidget {
  const GroupHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Container(
      color: palette.surfaceInset,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: palette.textSecondary)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 6),
      child: Row(children: [
        Expanded(
          child: Text(title.toUpperCase(),
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                  color: SureColors.of(context).palette.textSubdued)),
        ),
        if (action != null) action!,
      ]),
    );
  }
}

class KV extends StatelessWidget {
  const KV(this.label, this.value, {super.key, this.onTap, this.valueWidget});
  final String label;
  final String? value;
  final Widget? valueWidget;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 120,
              child: Text(label, style: TextStyle(color: palette.textSubdued))),
          Expanded(
            child: valueWidget ??
                Text((value == null || value!.isEmpty) ? '—' : value!,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: palette.textSubdued),
          ],
        ]),
      ),
    );
  }
}

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 10});
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: color ?? SureColors.of(context).palette.textSubdued, shape: BoxShape.circle),
      );
}

/// Round avatar with the first letter of [name], tinted with [color].
class LetterAvatar extends StatelessWidget {
  const LetterAvatar(this.name, {super.key, this.color, this.icon, this.size = 40});
  final String name;
  final Color? color;
  final IconData? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final c = color ?? palette.textSecondary;
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: icon != null
          ? Icon(icon, size: size * 0.5, color: c)
          : Text(letter,
              style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: size * 0.4)),
    );
  }
}

/// A money amount honouring privacy mode. [value] is signed from the user's
/// point of view; [colored] tints money in green and money out red.
class Amount extends StatelessWidget {
  const Amount(this.value, this.currency,
      {super.key, this.colored = true, this.signed = true, this.style, this.text});
  final double value;
  final String currency;
  final bool colored;
  final bool signed;
  final TextStyle? style;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final hidden = context.watch<PrivacyProvider>().hidden;
    final palette = SureColors.of(context).palette;
    final s = text ?? Fmt.money(value, currency, signed: signed);
    Color? color;
    if (colored) {
      color = value > 0 ? palette.success : (value < 0 ? palette.textPrimary : palette.textSubdued);
    }
    return Text(
      MoneyMasker.mask(s, hidden: hidden),
      style: (style ?? const TextStyle(fontWeight: FontWeight.w600))
          .copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

/// Searchable single-choice bottom sheet. Returns the chosen item, or the
/// sentinel `{}` when [allowNone] and "None" was picked; null when dismissed.
Future<Map<String, dynamic>?> pickOne(
  BuildContext context, {
  required String title,
  required List<Map<String, dynamic>> items,
  String? selectedId,
  bool allowNone = false,
  String noneLabel = 'None',
  Widget Function(Map<String, dynamic>)? leading,
  String Function(Map<String, dynamic>)? subtitle,
  String Function(Map<String, dynamic>)? label,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _PickSheet(
      title: title,
      items: items,
      selected: {if (selectedId != null) selectedId},
      multi: false,
      allowNone: allowNone,
      noneLabel: noneLabel,
      leading: leading,
      subtitle: subtitle,
      label: label,
    ),
  ).then((v) => v);
}

Future<Set<String>?> pickMany(
  BuildContext context, {
  required String title,
  required List<Map<String, dynamic>> items,
  Set<String> selected = const {},
  Widget Function(Map<String, dynamic>)? leading,
  String Function(Map<String, dynamic>)? label,
}) async {
  final res = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _PickSheet(
      title: title,
      items: items,
      selected: selected,
      multi: true,
      leading: leading,
      label: label,
    ),
  );
  if (res == null) return null;
  return (res['ids'] as Set<String>);
}

class _PickSheet extends StatefulWidget {
  const _PickSheet({
    required this.title,
    required this.items,
    required this.selected,
    required this.multi,
    this.allowNone = false,
    this.noneLabel = 'None',
    this.leading,
    this.subtitle,
    this.label,
  });
  final String title;
  final List<Map<String, dynamic>> items;
  final Set<String> selected;
  final bool multi;
  final bool allowNone;
  final String noneLabel;
  final Widget Function(Map<String, dynamic>)? leading;
  final String Function(Map<String, dynamic>)? subtitle;
  final String Function(Map<String, dynamic>)? label;

  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  String _q = '';
  late final Set<String> _sel = {...widget.selected};

  String _label(Map<String, dynamic> m) => widget.label?.call(m) ?? m['name']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items
        .where((m) => _q.isEmpty || _label(m).toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            Expanded(child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium)),
            if (widget.multi) ...[
              TextButton(onPressed: () => setState(_sel.clear), child: const Text('Clear')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, {'ids': _sel}),
                  child: const Text('Done')),
            ],
          ]),
        ),
        if (widget.items.length > 7)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: 'Search', isDense: true),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
        Expanded(
          child: ListView(controller: scroll, children: [
            if (widget.allowNone && !widget.multi)
              ListTile(
                leading: const Icon(Icons.block),
                title: Text(widget.noneLabel),
                trailing: widget.selected.isEmpty ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, <String, dynamic>{}),
              ),
            ...filtered.map((m) {
              final id = m['id']?.toString() ?? '';
              final on = _sel.contains(id);
              final sub = widget.subtitle?.call(m);
              return ListTile(
                leading: widget.leading?.call(m),
                title: Text(_label(m)),
                subtitle: (sub == null || sub.isEmpty) ? null : Text(sub),
                trailing: widget.multi
                    ? Checkbox(
                        value: on,
                        onChanged: (_) => setState(() => on ? _sel.remove(id) : _sel.add(id)))
                    : (on ? const Icon(Icons.check) : null),
                onTap: () {
                  if (widget.multi) {
                    setState(() => on ? _sel.remove(id) : _sel.add(id));
                  } else {
                    Navigator.pop(context, m);
                  }
                },
              );
            }),
          ]),
        ),
      ]),
    );
  }
}

Future<T?> push<T>(BuildContext context, Widget screen) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));

/// A labelled card container used on detail screens.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.children, this.margin});
  final List<Widget> children;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, color: palette.borderSecondary));
      rows.add(children[i]);
    }
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: palette.container,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.borderSecondary),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? SureColors.of(context).palette.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

Color statusColor(BuildContext context, String? status) {
  final p = SureColors.of(context).palette;
  switch (status) {
    case 'completed':
    case 'complete':
    case 'confirmed':
    case 'active':
    case 'success':
      return p.success;
    case 'failed':
    case 'rejected':
    case 'error':
      return p.destructive;
    case 'pending':
    case 'syncing':
    case 'importing':
    case 'processing':
    case 'reverting':
      return p.warning;
    default:
      return p.textSecondary;
  }
}
