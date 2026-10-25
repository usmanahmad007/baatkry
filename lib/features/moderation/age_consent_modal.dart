import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../services/livekit_service.dart';
import '../../services/permission_service.dart';
import '../../services/supabase_service.dart';

class AgeConsentModal extends StatefulWidget {
  final VoidCallback onVerified;
  final bool isGoogleUser;

  const AgeConsentModal({
    super.key,
    required this.onVerified,
    this.isGoogleUser = false,
  });

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

    final isGoogle = SupabaseService.instance.isGoogleUser;

    // If user logged in from Google, verify DOB / eligibility from their Google account
    if (isGoogle) {
      final isEligible = await SupabaseService.instance.verifyGoogleUserEligibility();
      if (!isEligible) {
        if (context.mounted) {
          showUnderageBlockedDialog(context);
        }
        return;
      }
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
        builder: (_) => AgeConsentModal(
          onVerified: onVerified,
          isGoogleUser: isGoogle,
        ),
      );
    }
  }

  static void showUnderageBlockedDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.block_flipped, color: AppColors.danger, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Access Denied (18+)',
                      style: TextStyle(
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Baatkry is strictly an adult community for users 18 and older. Minors are strictly prohibited from video chat.',
                style: TextStyle(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  State<AgeConsentModal> createState() => _AgeConsentModalState();
}

class _AgeConsentModalState extends State<AgeConsentModal> {
  DateTime? _selectedDob;
  int? _calculatedAge;
  bool _confirmedTerms = false;

  @override
  void initState() {
    super.initState();
    _selectedDob = null;
    _calculatedAge = widget.isGoogleUser
        ? (SupabaseService.instance.currentProfile?.age ?? 18)
        : null;
    _confirmedTerms = widget.isGoogleUser;
  }

  int _computeAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  bool get _isAdult => _calculatedAge != null && _calculatedAge! >= 18;
  bool get _isUnderage => _calculatedAge != null && _calculatedAge! < 18;

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initialPickerDate = _selectedDob ?? DateTime(now.year - 18, now.month, now.day);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialPickerDate,
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'BIRTH CERTIFICATE DATE',
      cancelText: 'Cancel',
      confirmText: 'Confirm',
      fieldLabelText: 'Birth Date (DD/MM/YYYY)',
      builder: (context, child) {
        return Theme(
          data: isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppColors.brandIndigo,
                    onPrimary: Colors.white,
                    surface: AppColors.darkSurface,
                    onSurface: Colors.white,
                  ),
                  dialogBackgroundColor: AppColors.darkSurface,
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AppColors.brandIndigo,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: AppColors.lightTextPrimary,
                  ),
                  dialogBackgroundColor: Colors.white,
                ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _calculatedAge = _computeAge(picked);
        _confirmedTerms = true;
      });
    }
  }

  Future<void> _onAcceptAndProceed() async {
    final effectiveAge = widget.isGoogleUser
        ? (_calculatedAge ?? SupabaseService.instance.currentProfile?.age ?? 18)
        : _calculatedAge;

    if (effectiveAge == null || effectiveAge < 18) {
      _blockAsUnderage();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AgeConsentModal.keyAgeVerified, true);
    await prefs.setInt(AgeConsentModal.keyUserAge, effectiveAge);
    await prefs.setBool('eula_accepted', true);

    await SupabaseService.instance.updateProfile(age: effectiveAge);

    // Warm up camera & mic permission directly inside this single modal
    // so no second dialog or repeated permission prompts occur
    try {
      await LiveKitService.instance.startLocalPreview();
    } catch (_) {}
    await PermissionService.instance.markPermissionHandled(granted: true);

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

  Widget _buildConsentBullet({
    required IconData icon,
    required Color color,
    required String text,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              fontSize: 11,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: _isUnderage
              ? AppColors.danger
              : (isDark ? AppColors.darkSurfaceBorder : AppColors.lightSurfaceBorder),
          width: 1.2,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 390),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modern Compact Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: _isUnderage ? null : AppColors.primaryGradient,
                    color: _isUnderage ? AppColors.danger : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.isGoogleUser ? Icons.verified_rounded : Icons.verified_user_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.isGoogleUser
                        ? 'Google Verified Consent'
                        : '18+ Verification & Video Access',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Subtle description
            Text(
              widget.isGoogleUser
                  ? 'Your 18+ eligibility is confirmed from your Google account. Confirm community rules to start chatting.'
                  : 'Enter your birth certificate date of birth to verify 18+ access and enable live video chat.',
              style: TextStyle(
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),

            if (widget.isGoogleUser) ...[
              // Google account verified card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.success.withOpacity(0.5),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.success,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            SupabaseService.instance.googleUserEmail ?? 'Google Verified Account',
                            style: TextStyle(
                              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Text(
                            'Age 18+ Verified via Google',
                            style: TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Eligible 18+ ✓',
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Community Guidelines bullets
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? AppColors.darkSurfaceBorder : AppColors.lightSurfaceBorder,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    _buildConsentBullet(
                      icon: Icons.shield_rounded,
                      color: AppColors.brandIndigo,
                      text: 'Strictly 18+ adults-only community.',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 8),
                    _buildConsentBullet(
                      icon: Icons.block_rounded,
                      color: AppColors.danger,
                      text: 'Zero tolerance for nudity, bullying, harassment, or abuse.',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 8),
                    _buildConsentBullet(
                      icon: Icons.videocam_rounded,
                      color: AppColors.brandCyan,
                      text: 'Camera & mic will be activated for 1-on-1 video calls.',
                      isDark: isDark,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Compact Checkbox row for Google User
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _confirmedTerms,
                      activeColor: AppColors.brandIndigo,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (val) => setState(() => _confirmedTerms = val ?? true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'I agree to the Community Guidelines & Terms of Service and grant camera & mic access.',
                      style: TextStyle(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Action button for Google User
              Container(
                decoration: BoxDecoration(
                  gradient: _confirmedTerms ? AppColors.primaryGradient : null,
                  color: _confirmedTerms
                      ? null
                      : (isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ElevatedButton(
                  onPressed: _confirmedTerms ? _onAcceptAndProceed : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Accept Consent & Start Video Chat',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Sleek Interactive Date Picker Input Card
              InkWell(
                onTap: _pickDateOfBirth,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _selectedDob == null
                          ? (isDark ? AppColors.darkSurfaceBorder : AppColors.lightSurfaceBorder)
                          : (_isAdult ? AppColors.success : AppColors.danger),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        color: _selectedDob == null
                            ? AppColors.brandIndigo
                            : (_isAdult ? AppColors.success : AppColors.danger),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedDob == null
                                  ? 'Date of Birth (Birth Certificate)'
                                  : '${_selectedDob!.day.toString().padLeft(2, '0')}/${_selectedDob!.month.toString().padLeft(2, '0')}/${_selectedDob!.year}',
                              style: TextStyle(
                                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _selectedDob == null
                                  ? 'Tap to select your date of birth'
                                  : 'Age: $_calculatedAge years old',
                              style: TextStyle(
                                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _selectedDob == null
                              ? AppColors.brandIndigo.withOpacity(0.12)
                              : (_isAdult ? AppColors.success : AppColors.danger).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _selectedDob == null
                              ? 'Select'
                              : (_isAdult ? 'Verified 18+ ✓' : 'Under 18 ✕'),
                          style: TextStyle(
                            color: _selectedDob == null
                                ? AppColors.brandIndigo
                                : (_isAdult ? AppColors.success : AppColors.danger),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Underage alert chip if <18
              if (_isUnderage) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 15),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Underage ($_calculatedAge yrs). Minors cannot enter Baatkry.',
                          style: const TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Compact Checkbox row
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _confirmedTerms,
                      activeColor: AppColors.brandIndigo,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: _selectedDob == null
                          ? null
                          : (val) => setState(() => _confirmedTerms = val ?? true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'I certify I am 18+ (birth certificate) and grant camera & mic access.',
                      style: TextStyle(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Action Button
              if (_selectedDob == null)
                Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton(
                    onPressed: _pickDateOfBirth,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 16, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Enter Date of Birth',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_isAdult)
                Container(
                  decoration: BoxDecoration(
                    gradient: _confirmedTerms ? AppColors.primaryGradient : null,
                    color: _confirmedTerms
                        ? null
                        : (isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton(
                    onPressed: _confirmedTerms ? _onAcceptAndProceed : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Confirm & Enter Video Chat (18+)',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white),
                      ],
                    ),
                  ),
                )
              else
                ElevatedButton(
                  onPressed: _blockAsUnderage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Exit App (< 18)',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
