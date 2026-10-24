import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../services/supabase_service.dart';

class AgeConsentModal extends StatefulWidget {
  final VoidCallback onVerified;

  const AgeConsentModal({super.key, required this.onVerified});

  static const String keyAgeVerified = 'baatkry_age_verified_18_plus';
  static const String keyUnderageBlocked = 'baatkry_underage_blocked';
  static const String keyUserAge = 'baatkry_user_age';

  static Future<bool> isBlockedUnderage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyUnderageBlocked) ?? false;
  }

  static Future<bool> isAgeVerified() async {
    final prefs = await SharedPreferences.getInstance();
    final isBlocked = prefs.getBool(keyUnderageBlocked) ?? false;
    if (isBlocked) return false;
    return prefs.getBool(keyAgeVerified) ?? false;
  }

  static Future<void> checkAndShow(
    BuildContext context, {
    required VoidCallback onVerified,
  }) async {
    final isBlocked = await isBlockedUnderage();
    if (isBlocked) {
      if (context.mounted) {
        showUnderageBlockedDialog(context);
      }
      return;
    }

    final verified = await isAgeVerified();
    if (verified) {
      onVerified();
      return;
    }

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AgeConsentModal(onVerified: onVerified),
      );
    }
  }

  static void showUnderageBlockedDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.danger, width: 2),
        ),
        title: const Row(
          children: [
            Icon(Icons.block_flipped, color: AppColors.danger, size: 28),
            SizedBox(width: 10),
            Text(
              'Access Denied (18+)',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Baatkry is an adult platform exclusively for users aged 18 and older.',
              style: TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              'Our zero-tolerance policy strictly prohibits minors from accessing video chatting or purchasing coins. You cannot use this application.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  State<AgeConsentModal> createState() => _AgeConsentModalState();
}

class _AgeConsentModalState extends State<AgeConsentModal> {
  late DateTime _selectedDob;
  late int _calculatedAge;
  bool _confirmedTerms = true;

  @override
  void initState() {
    super.initState();
    // Default to 19 years ago
    final now = DateTime.now();
    _selectedDob = DateTime(now.year - 19, now.month, now.day);
    _calculatedAge = _computeAge(_selectedDob);
  }

  int _computeAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  bool get _isAdult => _calculatedAge >= 18;

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob,
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.brandIndigo,
              onPrimary: Colors.white,
              surface: AppColors.surface,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: AppColors.surface,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _calculatedAge = _computeAge(picked);
      });
    }
  }

  Future<void> _onAcceptAndProceed() async {
    if (!_isAdult) {
      _blockAsUnderage();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AgeConsentModal.keyAgeVerified, true);
    await prefs.setInt(AgeConsentModal.keyUserAge, _calculatedAge);

    await SupabaseService.instance.updateProfile(age: _calculatedAge);

    if (mounted) {
      Navigator.of(context).pop();
      widget.onVerified();
    }
  }

  Future<void> _blockAsUnderage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AgeConsentModal.keyUnderageBlocked, true);
    await prefs.setBool(AgeConsentModal.keyAgeVerified, false);

    if (mounted) {
      Navigator.of(context).pop();
      AgeConsentModal.showUnderageBlockedDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: AppColors.brandIndigo, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Badge Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: _isAdult ? AppColors.primaryGradient : null,
                    color: _isAdult ? null : AppColors.danger,
                    shape: BoxShape.circle,
                  ),
                  child: const Text('🔞', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '18+ Age Verification',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        'Adult Community Consent',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            const Text(
              'Baatkry is an adult platform. You must confirm you are 18 years or older before entering live video chat.',
              style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),

            // Date of birth selection card
            InkWell(
              onTap: _pickDateOfBirth,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isAdult ? AppColors.brandIndigo.withOpacity(0.5) : AppColors.danger,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      color: _isAdult ? AppColors.brandIndigo : AppColors.danger,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your Date of Birth (Tap to change):',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_selectedDob.day}/${_selectedDob.month}/${_selectedDob.year}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isAdult ? AppColors.success.withOpacity(0.2) : AppColors.danger.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _isAdult ? AppColors.success : AppColors.danger),
                      ),
                      child: Text(
                        '$_calculatedAge Years Old',
                        style: TextStyle(
                          color: _isAdult ? AppColors.success : AppColors.danger,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Status feedback banner
            if (!_isAdult)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.danger.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You are under 18 ($_calculatedAge years old). You are not permitted to use Baatkry.',
                        style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.success.withOpacity(0.35)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Age Verified: You meet the 18+ requirement to access Baatkry.',
                        style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // Checkbox for terms
            Row(
              children: [
                Checkbox(
                  value: _confirmedTerms,
                  activeColor: AppColors.brandIndigo,
                  onChanged: (val) => setState(() => _confirmedTerms = val ?? true),
                ),
                const Expanded(
                  child: Text(
                    'I solemnly declare I am 18+ and agree to the Zero-Tolerance Community Standards.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action Buttons
            if (_isAdult)
              Container(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandIndigo.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _confirmedTerms ? _onAcceptAndProceed : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'I am 18+ & Accept Terms',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              )
            else
              ElevatedButton(
                onPressed: _blockAsUnderage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  'I am Under 18 (Exit App)',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
