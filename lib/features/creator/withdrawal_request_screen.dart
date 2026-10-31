import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/creator_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/creator_wallet.dart';
import '../../models/payout_account.dart';
import '../../services/supabase_service.dart';

class WithdrawalRequestScreen extends ConsumerStatefulWidget {
  final CreatorWallet wallet;
  final double minWithdrawal;

  const WithdrawalRequestScreen({
    super.key,
    required this.wallet,
    this.minWithdrawal = 20.00,
  });

  static Future<void> show(BuildContext context, {required CreatorWallet wallet, double minWithdrawal = 20.00}) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WithdrawalRequestScreen(wallet: wallet, minWithdrawal: minWithdrawal),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  ConsumerState<WithdrawalRequestScreen> createState() => _WithdrawalRequestScreenState();
}

class _WithdrawalRequestScreenState extends ConsumerState<WithdrawalRequestScreen> {
  final _amountController = TextEditingController();
  PayoutAccount? _selectedAccount;
  bool _isAddingNewAccount = false;

  // New account form fields
  String _selectedMethod = 'paypal';
  final _titleController = TextEditingController();
  final _numberController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _routingController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Default amount to min withdrawal if balance allows
    if (widget.wallet.availableEarningsUsd >= widget.minWithdrawal) {
      _amountController.text = widget.minWithdrawal.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _titleController.dispose();
    _numberController.dispose();
    _bankNameController.dispose();
    _routingController.dispose();
    super.dispose();
  }

  double get _enteredAmount {
    return double.tryParse(_amountController.text.trim()) ?? 0.0;
  }

  Future<void> _submitWithdrawal() async {
    setState(() => _errorMessage = null);

    final amt = _enteredAmount;
    if (amt < widget.minWithdrawal) {
      setState(() => _errorMessage = 'Minimum payout request is \$${widget.minWithdrawal.toStringAsFixed(2)} USD.');
      return;
    }
    if (amt > widget.wallet.availableEarningsUsd) {
      setState(() => _errorMessage = 'Amount exceeds available balance of \$${widget.wallet.availableEarningsUsd.toStringAsFixed(2)}.');
      return;
    }

    PayoutAccount? targetAccount = _selectedAccount;

    if (_isAddingNewAccount || targetAccount == null) {
      final title = _titleController.text.trim();
      final num = _numberController.text.trim();

      if (title.isEmpty) {
        setState(() => _errorMessage = 'Please enter an account holder name or title.');
        return;
      }
      if (num.isEmpty) {
        setState(() => _errorMessage = 'Please enter your account number, email, or address.');
        return;
      }

      setState(() => _isSubmitting = true);
      try {
        targetAccount = await SupabaseService.instance.saveCreatorPayoutAccount(
          payoutMethod: _selectedMethod,
          accountTitle: title,
          accountNumber: num,
          bankName: _bankNameController.text.trim().isEmpty ? null : _bankNameController.text.trim(),
          routingCode: _routingController.text.trim().isEmpty ? null : _routingController.text.trim(),
          isPrimary: true,
        );
        ref.invalidate(creatorPayoutAccountsProvider);
      } catch (e) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Failed to save payout account: $e';
        });
        return;
      }
    }

    if (targetAccount == null) {
      setState(() => _errorMessage = 'Please select or add a payout beneficiary account.');
      return;
    }

    if (!mounted) return;

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Withdrawal', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Request payout of \$${amt.toStringAsFixed(2)} USD to your ${targetAccount!.methodDisplayName} (${targetAccount.maskedAccountNumber})?',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              'Once submitted, the amount is reserved for processing. You may cancel it at any time before administrator approval.',
              style: TextStyle(color: Colors.white60, fontSize: 11),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPink),
            child: const Text('Confirm Request', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      setState(() => _isSubmitting = false);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await SupabaseService.instance.requestCreatorWithdrawal(
        payoutAccountId: targetAccount.id,
        amountUsd: amt,
      );

      ref.invalidate(creatorWalletProvider);
      ref.invalidate(creatorMyWithdrawalsProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text('Payout request of \$${amt.toStringAsFixed(2)} submitted successfully!'),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Withdrawal request failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(creatorPayoutAccountsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF141424),
        elevation: 0,
        title: const Text(
          'Request Earnings Payout',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Available Balance Hero Card
            _buildBalanceHero(),

            const SizedBox(height: 20),

            // Amount Input & Quick Chips
            const Text(
              'WITHDRAWAL AMOUNT',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              onChanged: (_) => setState(() => _errorMessage = null),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF161626),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixText: '\$ ',
                prefixStyle: const TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold),
                suffixText: 'USD',
                suffixStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),

            const SizedBox(height: 10),

            // Quick Chips
            Row(
              children: [
                _buildQuickChip('Min (\$${widget.minWithdrawal.toStringAsFixed(0)})', widget.minWithdrawal),
                const SizedBox(width: 8),
                if (widget.wallet.availableEarningsUsd >= 50.0) ...[
                  _buildQuickChip('\$50', 50.0),
                  const SizedBox(width: 8),
                ],
                if (widget.wallet.availableEarningsUsd >= 100.0) ...[
                  _buildQuickChip('\$100', 100.0),
                  const SizedBox(width: 8),
                ],
                _buildQuickChip('Max (\$${widget.wallet.availableEarningsUsd.toStringAsFixed(2)})', widget.wallet.availableEarningsUsd),
              ],
            ),

            const SizedBox(height: 24),

            // Payout Account Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PAYOUT BENEFICIARY ACCOUNT',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isAddingNewAccount = !_isAddingNewAccount;
                      _errorMessage = null;
                    });
                  },
                  child: Text(
                    _isAddingNewAccount ? 'Select Existing' : '+ Add New',
                    style: const TextStyle(color: AppColors.brandPink, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),

            if (!_isAddingNewAccount) ...[
              accountsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandPink)),
                error: (err, _) => Text('Error: $err', style: const TextStyle(color: Colors.redAccent)),
                data: (accounts) {
                  if (accounts.isEmpty) {
                    return _buildEmptyAccountsPrompt();
                  }

                  // Default selection if none selected yet
                  _selectedAccount ??= accounts.first;

                  return Column(
                    children: accounts.map((acc) => _buildAccountOption(acc)).toList(),
                  );
                },
              ),
            ] else ...[
              _buildNewAccountForm(),
            ],

            const SizedBox(height: 20),

            // Fee & Net Breakdown Card
            _buildBreakdownCard(),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitWithdrawal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandPink,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Submit Payout Request',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
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

  Widget _buildBalanceHero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF161626),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandPink.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Available Earnings', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                widget.wallet.formattedAvailable,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Text(
              'Min: \$${widget.minWithdrawal.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String label, double amount) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        setState(() {
          _amountController.text = amount.toStringAsFixed(2);
          _errorMessage = null;
        });
      },
      backgroundColor: const Color(0xFF1A1A2E),
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 11),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _buildEmptyAccountsPrompt() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161626),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.account_balance_rounded, color: Colors.white38, size: 36),
          const SizedBox(height: 8),
          const Text('No Payout Accounts Saved', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Add your PayPal or bank account to receive withdrawals.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => setState(() => _isAddingNewAccount = true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPink),
            child: const Text('Add Account Now', style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountOption(PayoutAccount acc) {
    final isSelected = _selectedAccount?.id == acc.id;

    return InkWell(
      onTap: () => setState(() => _selectedAccount = acc),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandPink.withOpacity(0.1) : const Color(0xFF161626),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.brandPink : Colors.white12,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: acc.id,
              groupValue: _selectedAccount?.id,
              onChanged: (_) => setState(() => _selectedAccount = acc),
              activeColor: AppColors.brandPink,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(acc.methodDisplayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      if (acc.isPrimary) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('PRIMARY', style: TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${acc.accountTitle} • ${acc.maskedAccountNumber}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewAccountForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161626),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Payout Method', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedMethod,
            dropdownColor: const Color(0xFF1A1A2E),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF0F0F1A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: const [
              DropdownMenuItem(value: 'paypal', child: Text('PayPal')),
              DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Wire / Transfer')),
              DropdownMenuItem(value: 'iban', child: Text('International IBAN')),
              DropdownMenuItem(value: 'wise', child: Text('Wise Transfer')),
              DropdownMenuItem(value: 'payoneer', child: Text('Payoneer')),
              DropdownMenuItem(value: 'crypto', child: Text('Crypto USDT (TRC20)')),
              DropdownMenuItem(value: 'jazzcash', child: Text('JazzCash')),
              DropdownMenuItem(value: 'easypaisa', child: Text('EasyPaisa')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _selectedMethod = val);
            },
          ),
          const SizedBox(height: 12),
          const Text('Account Beneficiary / Full Name', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'e.g. John Doe',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF0F0F1A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _selectedMethod == 'paypal' || _selectedMethod == 'wise'
                ? 'Email Address'
                : (_selectedMethod == 'crypto' ? 'USDT TRC20 Wallet Address' : 'Account Number / IBAN'),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _numberController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: _selectedMethod == 'paypal' ? 'email@example.com' : 'Account or Wallet ID',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF0F0F1A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          if (_selectedMethod == 'bank_transfer' || _selectedMethod == 'iban') ...[
            const SizedBox(height: 12),
            const Text('Bank Name', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            const SizedBox(height: 6),
            TextField(
              controller: _bankNameController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'e.g. JPMorgan Chase, Standard Chartered',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0F0F1A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdownCard() {
    final amt = _enteredAmount;
    const fee = 0.00; // Zero transfer platform fee
    final net = (amt - fee).clamp(0.0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121220),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Gross Requested', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              Text('\$${amt.toStringAsFixed(2)} USD', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Platform Transfer Fee', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              Text('\$${fee.toStringAsFixed(2)} USD', style: const TextStyle(color: Colors.greenAccent, fontSize: 13)),
            ],
          ),
          const Divider(color: Colors.white12, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Net Payout to You', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              Text('\$${net.toStringAsFixed(2)} USD', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }
}
