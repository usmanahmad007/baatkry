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
  bool _showingAuditLogs = false;

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
          title: Text('Suspend Account: ${user.username}', style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter reason for account suspension/ban:', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 10),
              TextField(
                controller: reasonController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g. Terms violation, inappropriate video conduct',
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
              child: const Text('Confirm Ban', style: TextStyle(color: Colors.white)),
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
          title: Text('Unban ${user.username}?', style: const TextStyle(color: Colors.white, fontSize: 16)),
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
            content: Text(willBan ? 'User ${user.username} suspended.' : 'User ${user.username} unbanned.'),
          ),
        );
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top toggle: Users vs Audit Logs
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF121220),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('User Accounts'),
                selected: !_showingAuditLogs,
                onSelected: (_) => setState(() => _showingAuditLogs = false),
                selectedColor: AppColors.brandPink,
                backgroundColor: const Color(0xFF1A1A2E),
                labelStyle: TextStyle(color: !_showingAuditLogs ? Colors.white : AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Audit Logs'),
                selected: _showingAuditLogs,
                onSelected: (_) => setState(() => _showingAuditLogs = true),
                selectedColor: AppColors.brandCyan,
                backgroundColor: const Color(0xFF1A1A2E),
                labelStyle: TextStyle(color: _showingAuditLogs ? Colors.black : AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),

        if (!_showingAuditLogs) ...[
          // Search box
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onSubmitted: _onSearchSubmitted,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search user by username...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.brandPink),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchSubmitted('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // Users list
          Expanded(
            child: ref.watch(adminUsersProvider(_searchQuery)).when(
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandPink)),
                  error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.redAccent))),
                  data: (users) {
                    if (users.isEmpty) {
                      return const Center(
                        child: Text('No users matching search query', style: TextStyle(color: AppColors.textMuted)),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) => _buildUserCard(users[i]),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: user.isBanned ? Colors.redAccent.withOpacity(0.4) : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.brandPink.withOpacity(0.2),
                child: Text(
                  user.username.isNotEmpty ? user.username[0].toUpperCase() : 'U',
                  style: const TextStyle(color: AppColors.brandPink, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          user.username,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        if (user.isBanned) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('BANNED', style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${user.country} • ${user.gender} • ${user.coins} Coins',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                color: const Color(0xFF1A1A2E),
                onSelected: (action) {
                  if (action == 'ban') _toggleBan(user);
                  if (action == 'role_creator') _toggleRole(user, 'creator');
                  if (action == 'role_admin') _toggleRole(user, 'admin');
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'ban',
                    child: Text(
                      user.isBanned ? 'Unban Account' : 'Suspend / Ban Account',
                      style: TextStyle(color: user.isBanned ? Colors.green : Colors.redAccent, fontSize: 13),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'role_creator',
                    child: Text(
                      user.isCreator ? 'Revoke Creator Role' : 'Grant Creator Role',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'role_admin',
                    child: Text(
                      user.isAdmin ? 'Revoke Admin Role' : 'Grant Admin Role',
                      style: const TextStyle(color: AppColors.brandPink, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Role Badges
          Wrap(
            spacing: 6,
            children: user.roles.map((role) {
              Color roleColor = Colors.white54;
              if (role == 'admin' || role == 'super_admin') roleColor = AppColors.brandPink;
              if (role == 'creator') roleColor = AppColors.brandCyan;
              if (role == 'moderator') roleColor = Colors.purpleAccent;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: roleColor.withOpacity(0.4)),
                ),
                child: Text(
                  role.toUpperCase(),
                  style: TextStyle(color: roleColor, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              );
            }).toList(),
          ),

          if (user.banReason != null && user.banReason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Ban Reason: ${user.banReason}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
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

