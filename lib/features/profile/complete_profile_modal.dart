import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../../services/supabase_service.dart';

class CompleteProfileModal extends StatefulWidget {
  final UserProfile? initialProfile;
  final bool dismissible;

  const CompleteProfileModal({
    super.key,
    this.initialProfile,
    this.dismissible = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    UserProfile? initialProfile,
    bool dismissible = false,
  }) {
    final profile = initialProfile ?? SupabaseService.instance.currentProfile;
    if (profile != null && !profile.isAnonymous && !profile.needsProfileCompletion) {
      return Future.value(true);
    }
    return showDialog<bool>(
      context: context,
      barrierDismissible: dismissible,
      builder: (_) => CompleteProfileModal(
        initialProfile: initialProfile,
        dismissible: dismissible,
      ),
    );
  }

  @override
  State<CompleteProfileModal> createState() => _CompleteProfileModalState();
}

class _CompleteProfileModalState extends State<CompleteProfileModal> {
  final TextEditingController _usernameController = TextEditingController();
  Timer? _debounceTimer;

  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String _usernameStatusMessage = '';

  DateTime? _selectedDob;
  int? _calculatedAge;
  bool _isAgeValid = false;

  String? _selectedGender;
  bool _needsGenderSelection = false;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile ?? SupabaseService.instance.currentProfile;
    if (profile?.username != null && profile!.username!.isNotEmpty) {
      _usernameController.text = profile.username!.replaceAll('@', '');
      _checkAvailability(_usernameController.text);
    }
    if (profile?.birthDate != null && profile!.birthDate!.isNotEmpty) {
      try {
        final parsed = DateTime.parse(profile.birthDate!);
        _setDob(parsed);
      } catch (_) {}
    }
    if (profile != null && profile.isGenderSet) {
      _selectedGender = profile.gender;
      _needsGenderSelection = false;
    } else {
      _needsGenderSelection = true;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _usernameController.dispose();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    _debounceTimer?.cancel();
    final clean = value.trim().toLowerCase().replaceAll('@', '');

    if (clean.isEmpty) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = null;
        _usernameStatusMessage = '';
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _checkAvailability(clean);
    });
  }

  Future<void> _checkAvailability(String clean) async {
    try {
      final res = await SupabaseService.instance.checkUsernameAvailability(clean);
      if (!mounted) return;

      final isAvailable = res['available'] == true;
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = isAvailable;
        _usernameStatusMessage = res['message']?.toString() ??
            (isAvailable ? 'Username is available' : 'Username already taken');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameStatusMessage = 'Error checking username';
      });
    }
  }

  void _setDob(DateTime date) {
    final now = DateTime.now();
    int age = now.year - date.year;
    if (now.month < date.month || (now.month == date.month && now.day < date.day)) {
      age--;
    }
    setState(() {
      _selectedDob = date;
      _calculatedAge = age;
      _isAgeValid = age >= 18;
      _errorMessage = null;
    });
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initialDate = _selectedDob ?? DateTime(now.year - 20, now.month, now.day);
    final firstDate = DateTime(1920);
    final lastDate = now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'SELECT YOUR DATE OF BIRTH',
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppColors.brandPink,
                    onPrimary: Colors.white,
                    surface: Color(0xFF1E1E34),
                    onSurface: Colors.white,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AppColors.brandIndigo,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black87,
                  ),
                ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      _setDob(picked);
    }
  }

  Future<void> _handleSubmit() async {
    final cleanUsername = _usernameController.text.trim().toLowerCase().replaceAll('@', '');
    if (cleanUsername.isEmpty) {
      setState(() => _errorMessage = 'Please enter a username.');
      return;
    }
    if (_isUsernameAvailable != true) {
      setState(() => _errorMessage = 'Please choose an available username.');
      return;
    }
    if (_selectedDob == null) {
      setState(() => _errorMessage = 'Please select your date of birth.');
      return;
    }
    if (!_isAgeValid) {
      setState(() => _errorMessage = 'You must be at least 18 years old.');
      return;
    }
    if (_needsGenderSelection && (_selectedGender == null || _selectedGender!.isEmpty)) {
      setState(() => _errorMessage = 'Please select your gender.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await SupabaseService.instance.setUsernameAndDob(
        username: cleanUsername,
        dateOfBirth: _selectedDob!,
        gender: _selectedGender,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Profile completed successfully! Welcome to Baatkry 🎉'),
              ],
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1B1B2F) : Colors.white;
    final cardBg = isDark ? const Color(0xFF262640) : const Color(0xFFF8FAFC);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF64748B);

    final canSubmit = (_isUsernameAvailable == true) &&
        (_selectedDob != null) &&
        _isAgeValid &&
        (!_needsGenderSelection || (_selectedGender != null && _selectedGender!.isNotEmpty)) &&
        !_isSubmitting;

    return PopScope(
      canPop: widget.dismissible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !widget.dismissible && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppColors.danger,
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              content: Text(
                'Username and Date of Birth are mandatory to use Baatkry.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: dialogBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.12) : Colors.black12,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.badge_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Complete Your Profile',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Choose your unique @username and verify your age (18+) to unlock friend requests, video chats, and gifting.',
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.dismissible)
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: subtitleColor,
                          size: 20,
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.brandPink.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.brandPink.withOpacity(0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded, size: 12, color: AppColors.brandPink),
                            SizedBox(width: 4),
                            Text(
                              'Required',
                              style: TextStyle(
                                color: AppColors.brandPink,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 20),

              // Username Section
              Text(
                'Unique Username',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _usernameController,
                onChanged: _onUsernameChanged,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  prefixIcon: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    child: Text(
                      '@',
                      style: TextStyle(
                        color: isDark ? AppColors.brandPink : AppColors.brandIndigo,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 0),
                  suffixIcon: _isCheckingUsername
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.brandPink,
                            ),
                          ),
                        )
                      : (_isUsernameAvailable == true
                          ? const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20)
                          : (_isUsernameAvailable == false
                              ? const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 20)
                              : null)),
                  hintText: 'your_username',
                  hintStyle: TextStyle(color: subtitleColor, fontSize: 14),
                  filled: true,
                  fillColor: cardBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _isUsernameAvailable == null
                          ? (isDark ? Colors.white10 : Colors.black12)
                          : (_isUsernameAvailable! ? AppColors.success : AppColors.danger),
                      width: _isUsernameAvailable == null ? 1.0 : 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _isUsernameAvailable == false ? AppColors.danger : AppColors.brandPink,
                      width: 1.8,
                    ),
                  ),
                ),
              ),

              // Live Status Under Username Field
              if (_usernameStatusMessage.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Row(
                    children: [
                      Icon(
                        _isUsernameAvailable == true
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                        size: 14,
                        color: _isUsernameAvailable == true
                            ? AppColors.success
                            : AppColors.danger,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _usernameStatusMessage,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _isUsernameAvailable == true
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'ℹ️ Usernames can only be changed once every 7 days.',
                    style: TextStyle(fontSize: 11, color: subtitleColor),
                  ),
                ),
              ],
              const SizedBox(height: 18),

              // Date of Birth Section
              Text(
                'Date of Birth (18+ Verification)',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickDateOfBirth,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _selectedDob == null
                          ? (isDark ? Colors.white10 : Colors.black12)
                          : (_isAgeValid ? AppColors.success : AppColors.danger),
                      width: _selectedDob == null ? 1.0 : 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        color: isDark ? AppColors.brandPink : AppColors.brandIndigo,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedDob != null
                              ? '${_selectedDob!.year}-${_selectedDob!.month.toString().padLeft(2, '0')}-${_selectedDob!.day.toString().padLeft(2, '0')}'
                              : 'Select Date of Birth (YYYY-MM-DD)',
                          style: TextStyle(
                            color: _selectedDob != null ? textColor : subtitleColor,
                            fontSize: 14,
                            fontWeight: _selectedDob != null ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (_calculatedAge != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isAgeValid
                                ? AppColors.success.withOpacity(0.15)
                                : AppColors.danger.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Age: $_calculatedAge ${_isAgeValid ? "✓ 18+" : "✕ Under 18"}',
                            style: TextStyle(
                              color: _isAgeValid ? AppColors.success : AppColors.danger,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              if (_selectedDob != null && !_isAgeValid) ...[
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.danger),
                      SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'You must be at least 18 years old to use Baatkry.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Gender Selection Section (Required on first setup if not previously set)
              if (_needsGenderSelection) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      'Your Gender',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(Locked once saved)',
                      style: TextStyle(fontSize: 11, color: subtitleColor),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildGenderOption('men', '👨 Male', isDark)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildGenderOption('women', '👩 Female', isDark)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildGenderOption('transgender', '⚧ Other', isDark)),
                  ],
                ),
              ],

              // Error Display
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action Button
              ElevatedButton(
                onPressed: canSubmit ? _handleSubmit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandPink,
                  disabledBackgroundColor: isDark ? Colors.white12 : Colors.black12,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: subtitleColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: canSubmit ? 4 : 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_rounded, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Save & Continue',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildGenderOption(String value, String label, bool isDark) {
    final isSelected = _selectedGender == value;
    return InkWell(
      onTap: () => setState(() {
        _selectedGender = value;
        _errorMessage = null;
      }),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandPink.withOpacity(0.18)
              : (isDark ? const Color(0xFF262640) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.brandPink
                : (isDark ? Colors.white10 : Colors.black12),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? AppColors.brandPink : (isDark ? Colors.white : Colors.black87),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
