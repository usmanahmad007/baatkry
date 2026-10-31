import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/virtual_gift.dart';
import '../../services/supabase_service.dart';

/// Provider for active virtual gifts catalog
final activeGiftsProvider = FutureProvider<List<VirtualGift>>((ref) async {
  return SupabaseService.instance.fetchActiveGifts();
});
