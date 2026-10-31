import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/gift_transaction.dart';
import '../../models/virtual_gift.dart';
import '../../services/livekit_service.dart';
import '../../services/supabase_service.dart';
import '../auth/auth_modal.dart';
import '../shop/shop_modal.dart';
import '../wallet/wallet_screen.dart';

class GiftModal extends ConsumerStatefulWidget {
  final String peerId;
  final String peerName;
  final String? roomId;

  const GiftModal({
    super.key,
    required this.peerId,
    required this.peerName,
    this.roomId,
  });

  static Future<void> show(
    BuildContext context, {
    required String peerId,
    required String peerName,
    String? roomId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GiftModal(
        peerId: peerId,
        peerName: peerName,
        roomId: roomId,
      ),
    );
  }

  @override
  ConsumerState<GiftModal> createState() => _GiftModalState();
}

class _GiftModalState extends ConsumerState<GiftModal> {
  VirtualGift? _selectedGift;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Default select first gift
    _selectedGift = VirtualGift.defaultGifts.first;
  }

  Future<void> _handleSendGift(VirtualGift gift) async {
    final isGuest = ref.read(isGuestProvider);
    if (isGuest) {
      Navigator.of(context).pop();
      AuthModal.show(
        context,
        onAuthSuccess: () => GiftModal.show(
          context,
          peerId: widget.peerId,
          peerName: widget.peerName,
          roomId: widget.roomId,
        ),
      );
      return;
    }

    final userCoins = ref.read(userCoinsProvider);
    if (userCoins < gift.coinPrice) {
      Navigator.of(context).pop();
      ShopModal.show(context);
      return;
    }

    setState(() => _isSending = true);

    try {
      final myProfile = SupabaseService.instance.currentProfile;
      final myId = myProfile?.id ?? 'me';
      final myName = myProfile?.nickname ?? 'Friend';

      // 1. Atomic backend stored procedure / ledger debit
      final res = await SupabaseService.instance.sendVirtualGift(
        gift: gift,
        receiverId: widget.peerId,
        receiverName: widget.peerName,
        roomId: widget.roomId,
      );

      // 2. Transmit real-time event across LiveKit WebRTC Data Channel
      final giftEvent = GiftEvent(
        giftId: gift.id,
        giftName: gift.name,
        coins: gift.coinPrice,
        senderId: myId,
        senderName: myName,
        receiverId: widget.peerId,
        receiverName: widget.peerName,
        emoji: gift.emoji,
        transactionId: res['gift_transaction_id']?.toString(),
        timestamp: DateTime.now(),
      );

      await LiveKitService.instance.sendGiftEvent(giftEvent);

      if (mounted) {
        setState(() => _isSending = false);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Failed to send gift: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userCoins = ref.watch(userCoinsProvider);
    final isGuest = ref.watch(isGuestProvider);
    final giftsAsync = ref.watch(activeGiftsProvider);

    final selected = _selectedGift ?? VirtualGift.defaultGifts.first;
    final canAfford = !isGuest && userCoins >= selected.coinPrice;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.backgroundElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: const Border(top: BorderSide(color: AppColors.brandPink, width: 2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPink.withOpacity(0.2),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('🎁', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Send Gift to ${widget.peerName}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Shows live animated celebration on screen',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Coin Balance Pill & Top up
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  WalletScreen.show(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.coinGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.coinGold.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.circle, color: AppColors.coinGold, size: 10),
                      const SizedBox(width: 6),
                      Text(
                        isGuest ? '0 Coins' : '$userCoins',
                        style: const TextStyle(
                          color: AppColors.coinGold,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.add_circle_outline_rounded, color: AppColors.coinGold, size: 14),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Gifts Grid
          Flexible(
            child: giftsAsync.when(
              data: (gifts) => _buildGiftsGrid(gifts.isNotEmpty ? gifts : VirtualGift.defaultGifts),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(color: AppColors.brandPink),
                ),
              ),
              error: (_, __) => _buildGiftsGrid(VirtualGift.defaultGifts),
            ),
          ),
          const SizedBox(height: 16),

          // Action Button
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: canAfford ? AppColors.vipGoldGradient : AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: (canAfford ? AppColors.coinGold : AppColors.brandPink).withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isSending
                  ? null
                  : () {
                      if (isGuest) {
                        Navigator.of(context).pop();
                        AuthModal.show(context);
                      } else if (!canAfford) {
                        Navigator.of(context).pop();
                        ShopModal.show(context);
                      } else {
                        _handleSendGift(selected);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: _isSending
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isGuest
                              ? 'Sign In with Google to Send'
                              : !canAfford
                                  ? 'Get Coins (${selected.coinPrice - userCoins} More Needed)'
                                  : 'Send ${selected.emoji} ${selected.name} (${selected.coinPrice} Coins)',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: canAfford ? Colors.black : Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          canAfford ? Icons.send_rounded : Icons.add_shopping_cart_rounded,
                          size: 18,
                          color: canAfford ? Colors.black : Colors.white,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGiftsGrid(List<VirtualGift> gifts) {
    return GridView.builder(
      shrinkWrap: true,
      itemCount: gifts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, index) {
        final gift = gifts[index];
        final isSelected = _selectedGift?.id == gift.id;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedGift = gift;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.brandPink.withOpacity(0.3),
                        AppColors.brandIndigo.withOpacity(0.2),
                      ],
                    )
                  : AppColors.darkCardGradient,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AppColors.coinGold : AppColors.surfaceBorder,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.coinGold.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (gift.badge != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      gradient: AppColors.vipGoldGradient,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      gift.badge!,
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 12),
                Text(
                  gift.emoji,
                  style: const TextStyle(fontSize: 28),
                ),
                const SizedBox(height: 4),
                Text(
                  gift.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.circle, size: 6, color: AppColors.coinGold),
                    const SizedBox(width: 3),
                    Text(
                      '${gift.coinPrice}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.coinGold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
