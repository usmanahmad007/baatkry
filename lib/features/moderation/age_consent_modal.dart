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
  DateTime? _selectedDob;
  int? _calculatedAge;
  bool _confirmedTerms = false;

  @override
  void initState() {
    super.initState();
    // Do NOT pre-fill date of birth. User must enter it according to their birth certificate.
    _selectedDob = null;
    _calculatedAge = null;
    _confirmedTerms = false;
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
    // Default initial date picker position to 18 years ago for easy selection
    final initialPickerDate = _selectedDob ?? DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialPickerDate,
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'ENTER DATE OF BIRTH (BIRTH CERTIFICATE)',
      cancelText: 'Cancel',
      confirmText: 'Confirm',
      fieldLabelText: 'Birth Date (DD/MM/YYYY)',
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
        _confirmedTerms = true;
      });
    }
  }

  Future<void> _onAcceptAndProceed() async {
    if (_calculatedAge == null || !_isAdult) {
      _blockAsUnderage();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AgeConsentModal.keyAgeVerified, true);
    await prefs.setInt(AgeConsentModal.keyUserAge, _calculatedAge!);
    await prefs.setBool('eula_accepted', true);

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
        side: BorderSide(
          color: _isUnderage ? AppColors.danger : AppColors.brandIndigo,
          width: 1.5,
        ),
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
                    gradient: _isUnderage ? null : AppColors.primaryGradient,
                    color: _isUnderage ? AppColors.danger : null,
                    shape: BoxShape.circle,
                  ),
                  child: const Text('🔞', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '18+ Age Verification',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        _selectedDob == null
                            ? 'Official Birth Certificate Required'
                            : (_isAdult ? 'Adult Community Verified' : 'Underage Restricted (<18)'),
                        style: TextStyle(
                          fontSize: 12,
                          color: _isUnderage ? AppColors.danger : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            const Text(
              'Baatkry is an adult platform. You must enter your exact Date of Birth according to your official birth certificate before you can proceed.',
              style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),

            // Date of birth selection card
            InkWell(
              onTap: _pickDateOfBirth,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _selectedDob == null
                        ? AppColors.brandIndigo
                        : (_isAdult ? AppColors.success : AppColors.danger),
                    width: 1.5,
                  ),
                  boxShadow: _selectedDob == null
                      ? [
                          BoxShadow(
                            color: AppColors.brandIndigo.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _selectedDob == null
                            ? AppColors.brandIndigo.withOpacity(0.15)
                            : (_isAdult ? AppColors.success : AppColors.danger).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _selectedDob == null
                            ? Icons.calendar_month_rounded
                            : (_isAdult ? Icons.verified_user_rounded : Icons.cancel_rounded),
                        color: _selectedDob == null
                            ? AppColors.brandPink
                            : (_isAdult ? AppColors.success : AppColors.danger),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedDob == null
                                ? 'Date of Birth (Birth Certificate):'
                                : 'Birth Certificate Date (Tap to change):',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _selectedDob == null
                                ? 'Tap to enter your birth date'
                                : '${_selectedDob!.day.toString().padLeft(2, '0')}/${_selectedDob!.month.toString().padLeft(2, '0')}/${_selectedDob!.year}',
                            style: TextStyle(
                              color: _selectedDob == null ? AppColors.brandPrimary : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: _selectedDob == null ? 14 : 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedDob == null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Enter',
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 11),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: (_isAdult ? AppColors.success : AppColors.danger).withOpacity(0.2),
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
            if (_selectedDob == null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.brandIndigo.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.brandIndigo.withOpacity(0.35)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.brandIndigo, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Step 1: Enter your birth date above as recorded on your official birth certificate.',
                        style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                      ),
                    ),
                  ],
                ),
              )
            else if (_isUnderage)
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
                        'Underage Restricted: You are $_calculatedAge years old according to your birth certificate. You cannot enter Baatkry.',
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
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Age Verified: You are $_calculatedAge years old and meet the 18+ requirement.',
                        style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600),
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
                  onChanged: _selectedDob == null
                      ? null
                      : (val) => setState(() => _confirmedTerms = val ?? true),
                ),
                const Expanded(
                  child: Text(
                    'I certify this date of birth matches my official birth certificate and I am 18+.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action Buttons
            if (_selectedDob == null)
              ElevatedButton(
                onPressed: _pickDateOfBirth,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surfaceElevated,
                  side: const BorderSide(color: AppColors.brandIndigo, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.edit_calendar_rounded, color: AppColors.brandPink, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Enter Date of Birth to Proceed',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              )
            else if (_isAdult)
              Container(
                decoration: BoxDecoration(
                  gradient: _confirmedTerms ? AppColors.primaryGradient : null,
                  color: _confirmedTerms ? null : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: _confirmedTerms
                      ? [
                          BoxShadow(
                            color: AppColors.brandIndigo.withOpacity(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: ElevatedButton(
                  onPressed: _confirmedTerms ? _onAcceptAndProceed : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text(
                    'I am 18+ & Accept Terms (Proceed)',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
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
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
