import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/admin_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/admin_audit_log.dart';
import '../../../models/admin_user.dart';
import '../../../services/supabase_service.dart';

class AdminUsersTab extends ConsumerStatefulWidget {
  const AdminUsersTab({super.key});

  @override
  ConsumerState<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends ConsumerState<AdminUsersTab> {
  final _searchController = TextEditingController();
  String? _searchQuery;
  String _selectedFilter = 'all'; // 'all', 'active', 'restricted', 'banned', 'vip', 'creator', 'audit'

  void _onSearchSubmitted(String val) {
    setState(() {
      _searchQuery = val.trim().isEmpty ? null : val.trim();
    });
  }

  Future<void> _toggleBan(AdminUser user) async {
    final willBan = !user.isBanned;
    String? reason;

    if (willBan) {
      final reasonController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Block / Ban User: ${user.username}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Blocking will permanently suspend this account and prevent any video matching or chat access.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              const Text('Ban Reason:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: reasonController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g. Terms violation, inappropriate conduct, spam bot',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF0F0F1A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Confirm Ban', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      reason = reasonController.text.trim();
      if (reason.isEmpty) reason = 'Administrative safety action';
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Unblock ${user.username}?', style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: const Text('This will restore full chat and video access for this user.', style: TextStyle(color: AppColors.textMuted)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Unban Account', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    final success = await SupabaseService.instance.toggleUserBan(user.id, isBanned: willBan, banReason: reason);
    if (success) {
      ref.invalidate(adminUsersProvider(_searchQuery));
      ref.invalidate(adminAuditLogsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: willBan ? Colors.redAccent : Colors.green,
            content: Text(willBan ? 'User ${user.username} suspended/blocked.' : 'User ${user.username} unbanned.'),
          ),
        );
      }
    }
  }

  Future<void> _showRestrictDialog(AdminUser user) async {
    final isCurrentlyRestricted = user.isCurrentlyRestricted;

    if (isCurrentlyRestricted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Lift Restrictions for ${user.username}?', style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: Text(
            'Current Restriction: ${user.restrictionDisplayName}\nReason: ${user.restrictionReason ?? "None"}\n\nDo you want to clear all active restrictions?',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Lift Restrictions', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      final success = await SupabaseService.instance.restrictUser(user.id, isRestricted: false);
      if (success) {
        ref.invalidate(adminUsersProvider(_searchQuery));
        ref.invalidate(adminAuditLogsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.green, content: Text('Restrictions lifted for ${user.username}.')),
          );
        }
      }
      return;
    }

    // Apply new restriction
    String selectedType = 'chat_mute';
    int durationHours = 24;
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text('Restrict Account: ${user.username}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Restriction Scope:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildRadioOption('chat_mute', 'Mute Text Chat 🔇', 'Disallow sending text chat messages during calls', selectedType, (v) => setModalState(() => selectedType = v)),
                  _buildRadioOption('camera_disabled', 'Disable Camera 📷', 'Force audio-only video chat (camera disabled)', selectedType, (v) => setModalState(() => selectedType = v)),
                  _buildRadioOption('matchmaking_cooldown', 'Matchmaking Cooldown ⏳', 'Suspend user from matchmaking queue temporarily', selectedType, (v) => setModalState(() => selectedType = v)),
                  _buildRadioOption('shadow_flagged', 'Shadow Flag for Review ⚠️', 'Flag user stream for staff moderation review', selectedType, (v) => setModalState(() => selectedType = v)),
                  const SizedBox(height: 12),
                  const Text('Duration:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildDurationChip('1 Hour', 1, durationHours, (h) => setModalState(() => durationHours = h)),
                      _buildDurationChip('24 Hours', 24, durationHours, (h) => setModalState(() => durationHours = h)),
                      _buildDurationChip('7 Days', 168, durationHours, (h) => setModalState(() => durationHours = h)),
                      _buildDurationChip('30 Days', 720, durationHours, (h) => setModalState(() => durationHours = h)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Reason:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'e.g. Chat spam, verbal abuse, inappropriate behavior',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF0F0F1A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[800]),
                child: const Text('Apply Restriction', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    String reason = reasonController.text.trim();
    if (reason.isEmpty) reason = 'Administrative safety restriction';

    final success = await SupabaseService.instance.restrictUser(
      user.id,
      isRestricted: true,
      restrictionType: selectedType,
      reason: reason,
      duration: Duration(hours: durationHours),
    );

    if (success) {
      ref.invalidate(adminUsersProvider(_searchQuery));
      ref.invalidate(adminAuditLogsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.amber[800], content: Text('Restriction applied to ${user.username}.')),
        );
      }
    }
  }

  Widget _buildRadioOption(String value, String title, String subtitle, String current, ValueChanged<String> onChanged) {
    final isSelected = current == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandPink.withOpacity(0.15) : const Color(0xFF0F0F1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? AppColors.brandPink : Colors.white12),
        ),
        child: Row(
          children: [
            Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off, size: 16, color: isSelected ? AppColors.brandPink : Colors.white54),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationChip(String label, int hours, int current, ValueChanged<int> onChanged) {
    final isSelected = current == hours;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onChanged(hours),
      selectedColor: AppColors.brandPink,
      backgroundColor: const Color(0xFF0F0F1A),
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 11),
    );
  }

  Future<void> _showAdjustCoinsDialog(AdminUser user) async {
    final coinsController = TextEditingController();
    final reasonController = TextEditingController();
    bool isAdding = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text('Adjust Coins: ${user.username}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current Balance: ${user.coins} Coins 🪙', style: const TextStyle(color: AppColors.coinGold, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_rounded, size: 14), Text('Add Coins')]),
                        selected: isAdding,
                        onSelected: (_) => setModalState(() => isAdding = true),
                        selectedColor: Colors.green,
                        labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.remove_rounded, size: 14), Text('Deduct Coins')]),
                        selected: !isAdding,
                        onSelected: (_) => setModalState(() => isAdding = false),
                        selectedColor: Colors.redAccent,
                        labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: coinsController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Coin Amount (e.g. 100)',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF0F0F1A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reasonController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Adjustment Reason (e.g. Refund, Bonus)',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF0F0F1A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: isAdding ? Colors.green : Colors.redAccent),
                child: Text(isAdding ? 'Add Coins' : 'Deduct Coins', style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    final amount = int.tryParse(coinsController.text.trim()) ?? 0;
    if (amount <= 0) return;

    final delta = isAdding ? amount : -amount;
    String reason = reasonController.text.trim();
    if (reason.isEmpty) reason = isAdding ? 'Administrative bonus' : 'Administrative adjustment';

    final success = await SupabaseService.instance.adjustUserCoins(user.id, coinDelta: delta, reason: reason);
    if (success) {
      ref.invalidate(adminUsersProvider(_searchQuery));
      ref.invalidate(adminAuditLogsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.green, content: Text('Coins adjusted by $delta for ${user.username}.')),
        );
      }
    }
  }

  Future<void> _toggleVip(AdminUser user) async {
    final willVip = !user.isVip;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${willVip ? 'Grant' : 'Revoke'} VIP Status', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          willVip
              ? 'Grant 30-day VIP membership to ${user.username}? This unlocks all VIP gender filters and privileges.'
              : 'Revoke VIP membership for ${user.username}?',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.coinGold),
            child: Text(willVip ? 'Grant VIP 👑' : 'Revoke VIP', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final success = await SupabaseService.instance.toggleUserVip(user.id, isVip: willVip);
    if (success) {
      ref.invalidate(adminUsersProvider(_searchQuery));
      ref.invalidate(adminAuditLogsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.green, content: Text('VIP status updated for ${user.username}.')),
        );
      }
    }
  }

  Future<void> _showUserDetailsModal(AdminUser user) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Color(0xFF14142B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: AppColors.brandPink, width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.brandPink.withOpacity(0.25),
                  child: Text(user.username.isNotEmpty ? user.username[0].toUpperCase() : 'U', style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.username, style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                      Text('User ID: ${user.id}', style: const TextStyle(fontSize: 11, color: Colors.white54, fontFamily: 'monospace')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(color: Colors.white12),
            const SizedBox(height: 10),
            _infoRow('Country', user.country),
            _infoRow('Gender', user.gender),
            _infoRow('Coins Balance', '${user.coins} Coins 🪙'),
            _infoRow('VIP Member', user.isVip ? 'Active 👑' : 'No'),
            _infoRow('Account Status', user.isBanned ? 'BANNED 🚫' : (user.isCurrentlyRestricted ? 'RESTRICTED ⚠️' : 'ACTIVE ✅')),
            if (user.isRestricted) ...[
              _infoRow('Restriction Scope', user.restrictionDisplayName),
              if (user.restrictionReason != null) _infoRow('Restriction Reason', user.restrictionReason!),
            ],
            if (user.banReason != null) _infoRow('Ban Reason', user.banReason!),
            _infoRow('Reports Received', '${user.reportsCount}'),
            _infoRow('Account Created', '${user.createdAt.year}-${user.createdAt.month.toString().padLeft(2, '0')}-${user.createdAt.day.toString().padLeft(2, '0')}'),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final success = await SupabaseService.instance.resetUserGenderLock(user.id);
                      if (success && mounted) {
                        ref.invalidate(adminUsersProvider(_searchQuery));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(backgroundColor: Colors.green, content: Text('Gender lock reset for ${user.username}. User can re-select gender.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.lock_reset_rounded, size: 16, color: AppColors.brandCyan),
                    label: const Text('Reset Gender Lock', style: TextStyle(color: AppColors.brandCyan, fontSize: 12)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.brandCyan)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _toggleRole(AdminUser user, String role) async {
    final hasRole = user.roles.contains(role);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${hasRole ? 'Revoke' : 'Grant'} $role Role', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          'Are you sure you want to ${hasRole ? 'remove' : 'grant'} the "$role" role for ${user.username}?',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPink),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await SupabaseService.instance.toggleUserRole(user.id, role: role, isGranted: !hasRole);
    if (success) {
      ref.invalidate(adminUsersProvider(_searchQuery));
      ref.invalidate(adminAuditLogsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.green, content: Text('Roles updated for ${user.username}.')),
        );
      }
    }
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = key),
      selectedColor: key == 'audit' ? AppColors.brandCyan : AppColors.brandPink,
      backgroundColor: const Color(0xFF1A1A2E),
      labelStyle: TextStyle(
        color: isSelected ? (key == 'audit' ? Colors.black : Colors.white) : AppColors.textMuted,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top Filter Category Selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF121220),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildFilterChip('all', 'All Users 👥'),
                const SizedBox(width: 6),
                _buildFilterChip('active', 'Active ✅'),
                const SizedBox(width: 6),
                _buildFilterChip('restricted', 'Restricted ⚠️'),
                const SizedBox(width: 6),
                _buildFilterChip('banned', 'Banned 🚫'),
                const SizedBox(width: 6),
                _buildFilterChip('vip', 'VIP 👑'),
                const SizedBox(width: 6),
                _buildFilterChip('creator', 'Creators 🌟'),
                const SizedBox(width: 6),
                _buildFilterChip('audit', 'Audit Logs 📜'),
              ],
            ),
          ),
        ),

        if (_selectedFilter != 'audit') ...[
          // Search box
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onSubmitted: _onSearchSubmitted,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search user by username, ID or country...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.brandPink, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchSubmitted('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),

          // Users list
          Expanded(
            child: ref.watch(adminUsersProvider(_searchQuery)).when(
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandPink)),
                  error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.redAccent))),
                  data: (users) {
                    final filtered = users.where((u) {
                      switch (_selectedFilter) {
                        case 'active':
                          return !u.isBanned && !u.isCurrentlyRestricted;
                        case 'restricted':
                          return u.isCurrentlyRestricted;
                        case 'banned':
                          return u.isBanned;
                        case 'vip':
                          return u.isVip;
                        case 'creator':
                          return u.isCreator;
                        default:
                          return true;
                      }
                    }).toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.person_search_rounded, size: 48, color: Colors.white24),
                            const SizedBox(height: 10),
                            Text('No users matching $_selectedFilter filter', style: const TextStyle(color: AppColors.textMuted)),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) => _buildUserCard(filtered[i]),
                    );
                  },
                ),
          ),
        ] else ...[
          // Audit logs list
          Expanded(
            child: ref.watch(adminAuditLogsProvider).when(
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandPink)),
                  error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.redAccent))),
                  data: (logs) {
                    if (logs.isEmpty) {
                      return const Center(child: Text('No administrative audit logs recorded', style: TextStyle(color: AppColors.textMuted)));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) => _buildAuditLogCard(logs[i]),
                    );
                  },
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildUserCard(AdminUser user) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: user.isBanned
              ? Colors.redAccent.withOpacity(0.5)
              : (user.isCurrentlyRestricted
                  ? Colors.amber.withOpacity(0.4)
                  : Colors.white.withOpacity(0.06)),
          width: user.isBanned || user.isCurrentlyRestricted ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AppColors.brandPink.withOpacity(0.2),
                backgroundImage: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                    ? NetworkImage(user.avatarUrl!)
                    : null,
                child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                    ? Text(
                        user.username.isNotEmpty ? user.username[0].toUpperCase() : 'U',
                        style: const TextStyle(color: AppColors.brandPink, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.username,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (user.isBanned) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text('BANNED 🚫', style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ] else if (user.isCurrentlyRestricted) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              user.restrictionDisplayName,
                              style: const TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${user.country} • ${user.gender} • ${user.coins} Coins 🪙',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                color: const Color(0xFF14142B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onSelected: (action) {
                  if (action == 'ban') _toggleBan(user);
                  if (action == 'restrict') _showRestrictDialog(user);
                  if (action == 'coins') _showAdjustCoinsDialog(user);
                  if (action == 'vip') _toggleVip(user);
                  if (action == 'role_creator') _toggleRole(user, 'creator');
                  if (action == 'role_admin') _toggleRole(user, 'admin');
                  if (action == 'details') _showUserDetailsModal(user);
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'ban',
                    child: Row(
                      children: [
                        Icon(user.isBanned ? Icons.check_circle_outline_rounded : Icons.block_rounded, size: 16, color: user.isBanned ? Colors.green : Colors.redAccent),
                        const SizedBox(width: 8),
                        Text(
                          user.isBanned ? 'Unblock / Unban' : 'Block / Ban User',
                          style: TextStyle(color: user.isBanned ? Colors.green : Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'restrict',
                    child: Row(
                      children: [
                        Icon(user.isCurrentlyRestricted ? Icons.lock_open_rounded : Icons.warning_amber_rounded, size: 16, color: Colors.amber),
                        const SizedBox(width: 8),
                        Text(
                          user.isCurrentlyRestricted ? 'Lift Restrictions' : 'Restrict User...',
                          style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'coins',
                    child: Row(
                      children: [
                        Icon(Icons.monetization_on_rounded, size: 16, color: AppColors.coinGold),
                        SizedBox(width: 8),
                        Text('Adjust Coins (+/-)', style: TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'vip',
                    child: Row(
                      children: [
                        const Icon(Icons.stars_rounded, size: 16, color: AppColors.coinGold),
                        const SizedBox(width: 8),
                        Text(user.isVip ? 'Revoke VIP 👑' : 'Grant VIP 👑', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'role_creator',
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user_rounded, size: 16, color: AppColors.brandCyan),
                        const SizedBox(width: 8),
                        Text(user.isCreator ? 'Revoke Creator' : 'Grant Creator 🌟', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'role_admin',
                    child: Row(
                      children: [
                        const Icon(Icons.admin_panel_settings_rounded, size: 16, color: AppColors.brandPink),
                        const SizedBox(width: 8),
                        Text(user.isAdmin ? 'Revoke Admin' : 'Grant Admin 🛡️', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'details',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: Colors.white70),
                        SizedBox(width: 8),
                        Text('View Full Details', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Badges row: Roles + VIP + Restriction
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (user.isVip)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppColors.coinGold.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.coinGold.withOpacity(0.4)),
                  ),
                  child: const Text('VIP 👑', style: TextStyle(color: AppColors.coinGold, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ...user.roles.map((role) {
                Color roleColor = Colors.white54;
                if (role == 'admin' || role == 'super_admin') roleColor = AppColors.brandPink;
                if (role == 'creator') roleColor = AppColors.brandCyan;
                if (role == 'moderator') roleColor = Colors.purpleAccent;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: roleColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    role.toUpperCase(),
                    style: TextStyle(color: roleColor, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                );
              }),
            ],
          ),

          // If Banned: Red alert box
          if (user.banReason != null && user.banReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 14, color: Colors.redAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Ban: ${user.banReason}',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // If Restricted: Amber alert box
          if (user.isCurrentlyRestricted) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${user.restrictionDisplayName}: ${user.restrictionReason ?? "Account restricted"}',
                      style: const TextStyle(color: Colors.amber, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAuditLogCard(AdminAuditLog log) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                log.actionDisplayName,
                style: const TextStyle(color: AppColors.brandCyan, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                '${log.createdAt.month}/${log.createdAt.day} ${log.createdAt.hour}:${log.createdAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Target: ${log.targetType} (${log.targetId})',
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
          ),
          if (log.details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Details: ${log.details}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
