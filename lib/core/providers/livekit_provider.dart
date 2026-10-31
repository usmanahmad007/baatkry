import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../models/chat_message.dart';
import '../../services/livekit_service.dart';

final liveKitServiceProvider = Provider<LiveKitService>((ref) {
  return LiveKitService.instance;
});

/// Streams remote stranger's video track when published
final remoteVideoTrackProvider = StreamProvider<VideoTrack?>((ref) {
  final service = ref.watch(liveKitServiceProvider);
  return service.remoteTrackStream;
});

/// Streams in-call chat messages
final chatMessagesStreamProvider = StreamProvider<ChatMessage>((ref) {
  final service = ref.watch(liveKitServiceProvider);
  return service.chatMessageStream;
});

/// Streams WebRTC call states
final callStateStreamProvider = StreamProvider<CallState>((ref) {
  final service = ref.watch(liveKitServiceProvider);
  return service.callStateStream;
});

/// Streams peer disconnection notifications
final peerDisconnectedStreamProvider = StreamProvider<void>((ref) {
  final service = ref.watch(liveKitServiceProvider);
  return service.peerDisconnectedStream;
});
