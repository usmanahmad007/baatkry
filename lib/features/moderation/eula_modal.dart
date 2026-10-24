import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';

class EulaModal extends StatelessWidget {
  final VoidCallback onAccepted;

  const EulaModal({super.key, required this.onAccepted});

  static Future<bool> checkAndShow(BuildContext context, {required VoidCallback onAccepted}) async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool('eula_accepted') ?? false;
    if (accepted) {
      onAccepted();
      return true;
    }

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => EulaModal(
          onAccepted: () async {
            await prefs.setBool('eula_accepted', true);
            onAccepted();
          },
        ),
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.security_rounded, color: AppColors.danger, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Safety & Community Rules',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zero Tolerance Policy',
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.brandIndigo, fontSize: 14),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'To maintain a safe community, our platform enforces zero tolerance for objectionable content and abusive users.\n\n'
                      '• Must be 18+ or age of majority in your jurisdiction.\n'
                      '• Strictly NO nudity, sexually suggestive behavior, or pornography.\n'
                      '• NO harassment, hate speech, bullying, or threats.\n'
                      '• Violators will be banned immediately and reported to authorities if appropriate.\n'
                      '• You can report and block any user at any time using the flag icon.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onAccepted();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('I Agree & Accept Terms', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
