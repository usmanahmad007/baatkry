import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/creator_application.dart';
import '../../services/supabase_service.dart';
import 'creator_application_modal.dart';
import 'creator_dashboard_screen.dart';

class CreatorStatusModal extends ConsumerWidget {
  const CreatorStatusModal({super.key});

  static Future<void> show(BuildContext context) async {
    final uid = SupabaseService.instance.currentProfile?.id;
    if (uid != null) {
      final isCreator = await SupabaseService.instance.checkIsCreator(uid);
      if (isCreator && context.mounted) {
        CreatorDashboardScreen.show(context);
        return;
      }
      final app = await SupabaseService.instance.fetchMyCreatorApplication();
      if (app != null && app.isApproved && context.mounted) {
        CreatorDashboardScreen.show(context);
        return;
      }
    }
    if (!context.mounted) return;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreatorStatusModal(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGuest = ref.watch(isGuestProvider);
    final isCreatorAsync = ref.watch(isCreatorProvider);
    final applicationAsync = ref.watch(myCreatorApplicationProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.backgroundElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: const Border(top: BorderSide(color: AppColors.brandIndigo, width: 2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandIndigo.withOpacity(0.25),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: AppColors.vipGoldGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.stars_rounded, color: Colors.black, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Creator Studio',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Monetize your video chats & withdraw real earnings',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // State Handler
          Flexible(
            child: SingleChildScrollView(
              child: applicationAsync.when(
                data: (app) {
                  final isApproved = isCreatorAsync.valueOrNull == true || app?.isApproved == true;

                  if (isApproved) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        CreatorDashboardScreen.show(context);
                      }
                    });
                    return _buildApprovedView(context);
                  } else if (app != null && app.isPending) {
                    return _buildPendingView(context, app);
                  } else if (app != null && app.isRejected) {
                    return _buildRejectedView(context, app);
                  } else {
                    return _buildNotAppliedView(context, isGuest);
                  }
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(color: AppColors.brandIndigo),
                  ),
                ),
                error: (_, __) => _buildNotAppliedView(context, isGuest),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovedView(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.success.withOpacity(0.2),
                AppColors.brandIndigo.withOpacity(0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.success.withOpacity(0.6), width: 1.5),
          ),
          child: Column(
            children: [
              const Icon(Icons.verified_rounded, color: AppColors.success, size: 54),
              const SizedBox(height: 12),
              const Text(
                'You are an Approved Creator! 🎉',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your account is officially verified. You earn 70% commission on every gift you receive in video calls, credited in withdrawable USD.',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_rounded, color: AppColors.coinGold, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Commission Rate: 70% Creator / 30% Platform',
                      style: TextStyle(color: AppColors.coinGold, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    CreatorDashboardScreen.show(context);
                  },
                  icon: const Icon(Icons.account_balance_wallet_rounded, size: 18, color: Colors.black),
                  label: const Text('Open Earnings Dashboard', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.coinGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPendingView(BuildContext context, CreatorApplication app) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.warning.withOpacity(0.2),
                AppColors.brandIndigo.withOpacity(0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.warning.withOpacity(0.5), width: 1.5),
          ),
          child: Column(
            children: [
              const Icon(Icons.hourglass_top_rounded, color: AppColors.warning, size: 52),
              const SizedBox(height: 12),
              Text(
                app.status.displayName,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your KYC verification is currently being reviewed by our administrative compliance team.\n\nReviews typically complete within 12 to 48 hours.',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _infoRow('Applicant', app.fullName),
                    const Divider(color: Colors.white12, height: 16),
                    _infoRow('Document Type', app.idDocumentType.displayName),
                    const Divider(color: Colors.white12, height: 16),
                    _infoRow('Country', app.country),
                    const Divider(color: Colors.white12, height: 16),
                    _infoRow('Submitted On', '${app.createdAt.year}-${app.createdAt.month.toString().padLeft(2, '0')}-${app.createdAt.day.toString().padLeft(2, '0')}'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRejectedView(BuildContext context, CreatorApplication app) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.danger.withOpacity(0.2),
                AppColors.brandIndigo.withOpacity(0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.danger.withOpacity(0.5), width: 1.5),
          ),
          child: Column(
            children: [
              const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 52),
              const SizedBox(height: 12),
              const Text(
                'Application Needs Updates',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                app.rejectionReason != null && app.rejectionReason!.isNotEmpty
                    ? 'Reason: ${app.rejectionReason}'
                    : 'Your submitted identification documents could not be verified.',
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  CreatorApplicationModal.show(context);
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reapply as Creator', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandIndigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotAppliedView(BuildContext context, bool isGuest) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pitch Hero Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandIndigo.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'Earn Real Cash on Baatkry',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'Receive virtual gifts from strangers during video chats and convert them into withdrawable real money in your bank account, JazzCash, or EasyPaisa.',
                style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Steps
        _buildFeatureItem(Icons.verified_user_rounded, 'KYC Identity Verification', 'Quick 18+ identity check with passport, national ID, or driver’s license.'),
        _buildFeatureItem(Icons.card_giftcard_rounded, '70% Gift Commission', 'Keep 70% of every gift sent to you during random video calls.'),
        _buildFeatureItem(Icons.account_balance_rounded, 'Direct Bank & Mobile Payouts', 'Request cash withdrawals starting at just \$20.00 USD.'),
        const SizedBox(height: 18),

        // Apply Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              CreatorApplicationModal.show(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coinGold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.edit_document, size: 18, color: Colors.black),
                SizedBox(width: 8),
                Text('Apply Now', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Icon(icon, color: AppColors.coinGold, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}
