import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../widgets/sure_list_group.dart';
import 'budgets_screen.dart';
import 'calendar_screen.dart';
import 'cash_flow_screen.dart';
import 'recent_transactions_screen.dart';
import '../extras/accounts_screen.dart';
import '../extras/data_screens.dart';
import '../extras/manage_screens.dart';
import '../extras/transactions_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      // Setting an explicit ListView padding opts out of the scroll view's
      // automatic safe-area inset, so restore it with SafeArea (keeps the group
      // clear of the status bar / home indicator).
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SureListGroup(
              children: [
                SureListRow(
                  leading: _iconBadge(context, Icons.pie_chart_outline),
                  title: l.moreBudgets,
                  subtitle: l.moreBudgetsSubtitle,
                  showChevron: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BudgetsScreen(),
                      ),
                    );
                  },
                ),
                SureListRow(
                  leading: _iconBadge(context, Icons.calendar_month),
                  title: l.moreCalendar,
                  subtitle: l.moreCalendarSubtitle,
                  showChevron: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CalendarScreen(),
                      ),
                    );
                  },
                ),
                SureListRow(
                  leading: _iconBadge(context, Icons.insights),
                  title: l.moreCashFlow,
                  subtitle: l.moreCashFlowSubtitle,
                  showChevron: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CashFlowScreen(),
                      ),
                    );
                  },
                ),
                SureListRow(
                  leading: _iconBadge(context, Icons.receipt_long),
                  title: l.moreRecentTransactions,
                  subtitle: l.moreRecentTransactionsSubtitle,
                  showChevron: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RecentTransactionsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            SureListGroup(
              header: 'Money',
              children: [
                _row(context, Icons.receipt_long_outlined, 'All transactions',
                    'Search, filter and bulk-edit every transaction', () => const TransactionsScreen()),
                _row(context, Icons.account_balance_outlined, 'Accounts',
                    'Balances, history, valuations and holdings', () => const AccountsScreen()),
                _row(context, Icons.event_repeat, 'Recurring',
                    'Bills, subscriptions and expected income', () => const RecurringScreen()),
                _row(context, Icons.swap_horiz, 'Transfers',
                    'Matched and rejected transfers', () => const TransfersScreen()),
                _row(context, Icons.trending_up, 'Spending vs normal',
                    'This month compared with your usual spending', () => const SpendingScreen()),
              ],
            ),
            const SizedBox(height: 16),
            SureListGroup(
              header: 'Organise',
              children: [
                _row(context, Icons.category_outlined, 'Categories',
                    'Browse and create categories', () => const CategoriesScreen()),
                _row(context, Icons.sell_outlined, 'Tags', 'Create, rename, recolour and delete tags',
                    () => const TagsScreen()),
                _row(context, Icons.storefront_outlined, 'Merchants', 'Browse merchants',
                    () => const MerchantsScreen()),
                _row(context, Icons.rule, 'Rules', 'Automation rules and their run history',
                    () => const RulesScreen()),
              ],
            ),
            const SizedBox(height: 16),
            SureListGroup(
              header: 'Data',
              children: [
                _row(context, Icons.upload_file, 'Imports', 'Upload CSV/QIF files and review imports',
                    () => const ImportsScreen()),
                _row(context, Icons.archive_outlined, 'Data export', 'Export and download all your data',
                    () => const ExportsScreen()),
                _row(context, Icons.sync, 'Sync & server', 'Sync now, sync history, household settings',
                    () => const SyncScreen()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String title, String subtitle,
      Widget Function() screen) {
    return SureListRow(
      leading: _iconBadge(context, icon),
      title: title,
      subtitle: subtitle,
      showChevron: true,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen())),
    );
  }

  Widget _iconBadge(BuildContext context, IconData icon) {
    final palette = SureColors.of(context).palette;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: palette.surfaceInset,
        borderRadius: BorderRadius.circular(SureTokens.radiusMd),
      ),
      child: Icon(icon, color: palette.textPrimary),
    );
  }
}
