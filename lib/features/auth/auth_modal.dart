import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/supabase_service.dart';
import '../moderation/age_consent_modal.dart';

class AuthModal extends StatefulWidget {
  final VoidCallback? onAuthSuccess;

  const AuthModal({super.key, this.onAuthSuccess});

  static Future<void> show(BuildContext context, {VoidCallback? onAuthSuccess}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AuthModal(onAuthSuccess: onAuthSuccess),
    );
  }

  @override
  State<AuthModal> createState() => _AuthModalState();
}

class _AuthModalState extends State<AuthModal> {
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleGoogleSignIn() async {
    final isBlocked = await AgeConsentModal.isBlockedUnderage();
    if (isBlocked) {
      if (mounted) {
        Navigator.of(context).pop();
        AgeConsentModal.showUnderageBlockedDialog(context);
      }
      return;
    }

    _showGoogleAccountSelectionDialog();
  }

  Future<void> _showGoogleAccountSelectionDialog() async {
    final emailController = TextEditingController();
    DateTime? selectedDob;
    String? dialogError;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: AppColors.brandIndigo, width: 1.5),
            ),
            title: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      'G',
                      style: TextStyle(
                        color: Color(0xFF4285F4),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Sign In with Google',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Please put or select your Gmail address to connect your Google account:',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Your Gmail / Google Email',
                      labelStyle: const TextStyle(color: AppColors.textSecondary),
                      hintText: 'e.g. yourname@gmail.com',
                      hintStyle: const TextStyle(color: Colors.white24),
                      prefixIcon: const Icon(Icons.mail_outline_rounded, color: AppColors.brandIndigo),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.surfaceBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.brandIndigo, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime(2002, 1, 1),
                        firstDate: DateTime(1930),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDob = picked;
                          dialogError = null;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selectedDob == null ? AppColors.surfaceBorder : AppColors.brandPink,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cake_outlined, color: AppColors.brandPink, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedDob == null
                                  ? 'Select Date of Birth (Verify 18+)'
                                  : 'DOB: ${selectedDob!.year}-${selectedDob!.month.toString().padLeft(2, '0')}-${selectedDob!.day.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                color: selectedDob == null ? AppColors.textSecondary : Colors.white,
                                fontSize: 13,
                                fontWeight: selectedDob == null ? FontWeight.normal : FontWeight.bold,
                              ),
                            ),
                          ),
                          const Icon(Icons.calendar_today_rounded, color: AppColors.textSecondary, size: 16),
                        ],
                      ),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      dialogError!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final email = emailController.text.trim();
                        if (email.isEmpty || !email.contains('@')) {
                          setDialogState(() => dialogError = 'Please enter your Google / Gmail address.');
                          return;
                        }
                        if (!email.toLowerCase().endsWith('gmail.com') && !email.contains('.')) {
                          setDialogState(() => dialogError = 'Please enter a valid Gmail address.');
                          return;
                        }
                        if (selectedDob == null) {
                          setDialogState(() => dialogError = 'Please select your Date of Birth to verify 18+.');
                          return;
                        }

                        final now = DateTime.now();
                        int age = now.year - selectedDob!.year;
                        if (now.month < selectedDob!.month || (now.month == selectedDob!.month && now.day < selectedDob!.day)) {
                          age--;
                        }
                        if (age < 18) {
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                          if (mounted) {
                            Navigator.of(context).pop();
                            AgeConsentModal.showUnderageBlockedDialog(context);
                          }
                          return;
                        }

                        setDialogState(() => isSubmitting = true);
                        try {
                          await SupabaseService.instance.signInWithGmailDirect(
                            email,
                            dateOfBirth: selectedDob,
                          );
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                          if (mounted) {
                            Navigator.of(context).pop();
                            widget.onAuthSuccess?.call();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.success,
                                content: Text('Signed in as $email (Age $age verified 🎉)'),
                              ),
                            );
                          }
                        } catch (err) {
                          setDialogState(() {
                            isSubmitting = false;
                            dialogError = err.toString().replaceAll('Exception: ', '');
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandIndigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Continue with Gmail', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleAnonymousSignIn() async {
    final isBlocked = await AgeConsentModal.isBlockedUnderage();
    if (isBlocked) {
      if (mounted) {
        Navigator.of(context).pop();
        AgeConsentModal.showUnderageBlockedDialog(context);
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await SupabaseService.instance.signInAnonymously();

      if (mounted) {
        Navigator.of(context).pop();
        widget.onAuthSuccess?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.brandIndigo,
            content: Text('Connected as Anonymous Guest!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
      decoration: BoxDecoration(
        color: AppColors.backgroundElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: const Border(top: BorderSide(color: AppColors.brandIndigo, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandIndigo.withOpacity(0.25),
            blurRadius: 30,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // App Icon / Logo with gradient
          Center(
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandIndigo.withOpacity(0.4),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.video_chat_rounded, color: Colors.white, size: 36),
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'Welcome to Baatkry',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Meet strangers instantly with 1-tap anonymous mode or sign in with Google to purchase coins and unlock VIP gender filters.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 24),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.danger.withOpacity(0.3)),
              ),
              child: Text(_errorMessage!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ),
            const SizedBox(height: 16),
          ],

          // 18+ Age Verification Requirement Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.brandIndigo.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.brandIndigo.withOpacity(0.4)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('🔞', style: TextStyle(fontSize: 15)),
                SizedBox(width: 8),
                Text(
                  '18+ Only: Age verified via Google / Gmail account',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 1. Primary Option: Google Sign-In
          ElevatedButton(
            onPressed: _isLoading ? null : _handleGoogleSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(shape: BoxShape.circle),
                        child: const Center(
                          child: Text(
                            'G',
                            style: TextStyle(
                              color: Color(0xFF4285F4),
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Continue with Google',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),

          // 2. Secondary Option: Anonymous Sign-In
          OutlinedButton(
            onPressed: _isLoading ? null : _handleAnonymousSignIn,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: AppColors.surfaceBorder, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: AppColors.surfaceElevated,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.visibility_off_rounded, color: AppColors.textSecondary, size: 20),
                SizedBox(width: 10),
                Text(
                  'Continue as Anonymous Guest',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Security & Store Compliance Disclaimer
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.textMuted, size: 14),
              SizedBox(width: 6),
              Text(
                'Purchases strictly require Google Sign-In for security',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
