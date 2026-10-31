import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/creator_application.dart';
import '../../services/supabase_service.dart';
import '../auth/auth_modal.dart';

class CreatorApplicationModal extends ConsumerStatefulWidget {
  const CreatorApplicationModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreatorApplicationModal(),
    );
  }

  @override
  ConsumerState<CreatorApplicationModal> createState() => _CreatorApplicationModalState();
}

class _CreatorApplicationModalState extends ConsumerState<CreatorApplicationModal> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  final _countryController = TextEditingController(text: 'Pakistan');
  final _bioController = TextEditingController();
  final _instagramController = TextEditingController();
  final _tiktokController = TextEditingController();
  final _youtubeController = TextEditingController();

  DateTime? _selectedDob;
  IdDocumentType _selectedDocType = IdDocumentType.nationalId;

  // Document photo attachments (URLs or simulated uploads)
  final String _frontDocUrl = 'assets/kyc/front_id_sample.jpg';
  final String _backDocUrl = 'assets/kyc/back_id_sample.jpg';
  final String _selfieUrl = 'assets/kyc/selfie_sample.jpg';

  bool _acceptedTerms = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final profile = SupabaseService.instance.currentProfile;
    if (profile != null) {
      if (profile.nickname != 'Anonymous Explorer') {
        _fullNameController.text = profile.nickname;
      }
      if (profile.country != 'Global (Worldwide)') {
        _countryController.text = profile.country;
      }
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _countryController.dispose();
    _bioController.dispose();
    _instagramController.dispose();
    _tiktokController.dispose();
    _youtubeController.dispose();
    super.dispose();
  }

  int get _computedAge {
    if (_selectedDob == null) return 0;
    final now = DateTime.now();
    int age = now.year - _selectedDob!.year;
    if (now.month < _selectedDob!.month || (now.month == _selectedDob!.month && now.day < _selectedDob!.day)) {
      age--;
    }
    return age;
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initialDate = DateTime(now.year - 20, 1, 1);
    final firstDate = DateTime(now.year - 90, 1, 1);
    final lastDate = DateTime(now.year - 18, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.brandIndigo,
              onPrimary: Colors.white,
              surface: AppColors.darkSurface,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDob = picked);
    }
  }

  Future<void> _handleSubmit() async {
    final isGuest = ref.read(isGuestProvider);
    if (isGuest) {
      Navigator.of(context).pop();
      AuthModal.show(context, onAuthSuccess: () => CreatorApplicationModal.show(context));
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_selectedDob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Please select your Date of Birth. Creators must be 18+ years old.'),
        ),
      );
      return;
    }

    if (_computedAge < 18) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('You must be at least 18 years old to become an approved creator.'),
        ),
      );
      return;
    }

    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.warning,
          content: Text('Please accept the Creator Agreement to proceed.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final socialLinks = <String, dynamic>{};
      if (_instagramController.text.trim().isNotEmpty) {
        socialLinks['instagram'] = _instagramController.text.trim();
      }
      if (_tiktokController.text.trim().isNotEmpty) {
        socialLinks['tiktok'] = _tiktokController.text.trim();
      }
      if (_youtubeController.text.trim().isNotEmpty) {
        socialLinks['youtube'] = _youtubeController.text.trim();
      }

      await SupabaseService.instance.submitCreatorApplication(
        fullName: _fullNameController.text.trim(),
        dateOfBirth: _selectedDob!,
        country: _countryController.text.trim(),
        idDocumentType: _selectedDocType,
        idDocumentFrontUrl: _frontDocUrl,
        idDocumentBackUrl: _selectedDocType != IdDocumentType.passport ? _backDocUrl : null,
        selfieUrl: _selfieUrl,
        socialMediaLinks: socialLinks,
        bio: _bioController.text.trim(),
      );

      // Invalidate provider so UI reacts immediately
      ref.invalidate(myCreatorApplicationProvider);

      if (mounted) {
        setState(() => _isSubmitting = false);
        Navigator.of(context).pop();
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Application submission failed: $e'),
          ),
        );
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: AppColors.brandIndigo, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
            SizedBox(width: 12),
            Text('Application Received!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thank you for applying to the Baatkry Creator Program!',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Our verification team is reviewing your ID documents and eligibility. Reviews typically take between 12 to 48 hours.\n\nOnce approved, you will earn 70% commission on all virtual gifts and unlock real-money bank withdrawals.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandIndigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Got It', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = ref.watch(isGuestProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
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
      child: Form(
        key: _formKey,
        child: Column(
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
                  child: const Icon(Icons.verified_user_rounded, color: Colors.black, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Creator KYC Application',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Earn 70% cash commission on every gift you receive',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.coinGold,
                          fontWeight: FontWeight.bold,
                        ),
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
            const SizedBox(height: 14),

            // Scrollable Form Fields
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Benefits Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.brandIndigo.withOpacity(0.2),
                            AppColors.brandPink.withOpacity(0.12),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.brandIndigo.withOpacity(0.4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 24),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '70% Creator Earnings • 30% Platform',
                                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Minimum withdrawal: \$20.00 USD directly to your local bank account, JazzCash, or EasyPaisa.',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Section 1: Personal Details
                    const Text(
                      '1. Legal Identity',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),

                    // Full Legal Name
                    TextFormField(
                      controller: _fullNameController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: _inputDecoration('Full Legal Name', Icons.person_rounded, 'As shown on government ID'),
                      validator: (val) => (val == null || val.trim().length < 3) ? 'Enter your full legal name' : null,
                    ),
                    const SizedBox(height: 12),

                    // Date of Birth & Age
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _pickDateOfBirth,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: AppColors.darkSurface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.surfaceBorder),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.cake_rounded, color: AppColors.brandIndigo, size: 20),
                                  const SizedBox(width: 10),
                                  Text(
                                    _selectedDob == null
                                        ? 'Select Date of Birth'
                                        : '${_selectedDob!.year}-${_selectedDob!.month.toString().padLeft(2, '0')}-${_selectedDob!.day.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      color: _selectedDob == null ? Colors.white54 : Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_selectedDob != null) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: _computedAge >= 18 ? AppColors.success.withOpacity(0.15) : AppColors.danger.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _computedAge >= 18 ? AppColors.success : AppColors.danger),
                            ),
                            child: Text(
                              '$_computedAge yrs • ${_computedAge >= 18 ? "18+ Adult" : "Underage"}',
                              style: TextStyle(
                                color: _computedAge >= 18 ? AppColors.success : AppColors.danger,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Country
                    TextFormField(
                      controller: _countryController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: _inputDecoration('Country of Residence', Icons.public_rounded, 'e.g. Pakistan, United States'),
                      validator: (val) => (val == null || val.trim().isEmpty) ? 'Country is required' : null,
                    ),
                    const SizedBox(height: 18),

                    // Section 2: ID Document Verification
                    const Text(
                      '2. Government ID Document',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),

                    // ID Type Segmented Switcher
                    Row(
                      children: IdDocumentType.values.map((type) {
                        final isSelected = _selectedDocType == type;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: InkWell(
                              onTap: () => setState(() => _selectedDocType = type),
                              borderRadius: BorderRadius.circular(12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  gradient: isSelected ? AppColors.primaryGradient : null,
                                  color: isSelected ? null : AppColors.darkSurface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? Colors.white30 : AppColors.surfaceBorder,
                                  ),
                                ),
                                child: Text(
                                  type.displayName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? Colors.white : Colors.white70,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),

                    // Document Photo Uploads
                    Row(
                      children: [
                        Expanded(
                          child: _buildUploadCard(
                            title: 'Front of ID',
                            subtitle: 'Clear, unblurred',
                            icon: Icons.document_scanner_rounded,
                            isUploaded: true,
                          ),
                        ),
                        if (_selectedDocType != IdDocumentType.passport) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildUploadCard(
                              title: 'Back of ID',
                              subtitle: 'Barcode & text',
                              icon: Icons.flip_to_back_rounded,
                              isUploaded: true,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildUploadCard(
                            title: 'Selfie with ID',
                            subtitle: 'Face verification',
                            icon: Icons.face_retouching_natural_rounded,
                            isUploaded: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Section 3: Creator Bio & Social Channels
                    const Text(
                      '3. Creator Profile & Socials',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),

                    TextFormField(
                      controller: _bioController,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _inputDecoration('Bio / About Me', Icons.description_rounded, 'Tell your fans about yourself...'),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _instagramController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: _inputDecoration('Instagram', Icons.camera_alt_rounded, '@username'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _tiktokController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: _inputDecoration('TikTok', Icons.play_circle_rounded, '@username'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Agreement Checkbox
                    InkWell(
                      onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
                      borderRadius: BorderRadius.circular(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _acceptedTerms,
                            activeColor: AppColors.brandIndigo,
                            onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                          ),
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: Text(
                                'I certify that I am at least 18 years old, all submitted documents belong to me, and I agree to the Creator Program terms & 70% commission policy.',
                                style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Submit Button
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: AppColors.vipGoldGradient,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.coinGold.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _handleSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.send_rounded, color: Colors.black, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            isGuest ? 'Sign In to Submit' : 'Submit Creator Application',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, String hint) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
      prefixIcon: Icon(icon, color: AppColors.brandIndigo, size: 20),
      filled: true,
      fillColor: AppColors.darkSurface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.surfaceBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.surfaceBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.brandIndigo, width: 1.5)),
    );
  }

  Widget _buildUploadCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isUploaded,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isUploaded ? AppColors.success.withOpacity(0.5) : AppColors.surfaceBorder),
      ),
      child: Column(
        children: [
          Icon(isUploaded ? Icons.check_circle_rounded : icon, color: isUploaded ? AppColors.success : Colors.white70, size: 24),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(isUploaded ? 'Attached' : subtitle, style: TextStyle(color: isUploaded ? AppColors.success : AppColors.textSecondary, fontSize: 9)),
        ],
      ),
    );
  }
}
