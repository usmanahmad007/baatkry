import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import '../core/config/app_config.dart';
import '../models/chat_message.dart';
import '../models/gift_transaction.dart';
import 'permission_service.dart';

enum CallState { idle, connecting, connected, disconnected, failed }

class LiveKitService {
  static final LiveKitService instance = LiveKitService._internal();
  LiveKitService._internal();

  Room? _room;
  EventsListener<RoomEvent>? _listener;

  LocalVideoTrack? _previewTrack;
  VideoTrack? _remoteVideoTrack;
  CameraPosition _cameraPosition = CameraPosition.front;
  bool _isMicMuted = false;
  bool _isVideoMuted = false;

  bool _isDisconnecting = false;

  final _callStateController = StreamController<CallState>.broadcast();
  final _remoteTrackController = StreamController<VideoTrack?>.broadcast();
  final _chatMessageController = StreamController<ChatMessage>.broadcast();
  final _giftEventController = StreamController<GiftEvent>.broadcast();
  final _peerDisconnectedController = StreamController<void>.broadcast();

  Stream<CallState> get callStateStream => _callStateController.stream;
  Stream<VideoTrack?> get remoteTrackStream => _remoteTrackController.stream;
  Stream<ChatMessage> get chatMessageStream => _chatMessageController.stream;
  Stream<GiftEvent> get giftEventStream => _giftEventController.stream;
  Stream<void> get peerDisconnectedStream => _peerDisconnectedController.stream;

  Room? get room => _room;
  LocalVideoTrack? get previewTrack => _previewTrack;
  VideoTrack? get remoteVideoTrack => _remoteVideoTrack;
  bool get isMicMuted => _isMicMuted;
  bool get isVideoMuted => _isVideoMuted;
  CameraPosition get cameraPosition => _cameraPosition;

  /// Start a standalone camera preview before entering a call (for Home Screen)
  /// Uses cached permissions to avoid repeated permission prompts
  Future<LocalVideoTrack?> startLocalPreview() async {
    // If preview track is already active and running, reuse it!
    if (_previewTrack != null && !_previewTrack!.isDisposed) {
      return _previewTrack;
    }

    try {
      if (_previewTrack != null) {
        final old = _previewTrack;
        _previewTrack = null;
        try {
          await old?.stop();
        } catch (_) {}
        try {
          await old?.dispose();
        } catch (_) {}
      }
      _previewTrack = await LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(
          cameraPosition: _cameraPosition,
          params: kIsWeb ? VideoParametersPresets.h720_169 : VideoParametersPresets.h540_169,
          maxFrameRate: 30,
        ),
      );
      // Mark permission granted once
      await PermissionService.instance.markPermissionHandled(granted: true);
      return _previewTrack;
    } catch (e) {
      debugPrint('[LiveKitService] Preview camera start error: $e');
      return null;
    }
  }

  Future<void> stopLocalPreview() async {
    if (_previewTrack != null) {
      final old = _previewTrack;
      _previewTrack = null;
      try {
        await old?.stop();
      } catch (e) {
        debugPrint('[LiveKitService] stopLocalPreview stop note: $e');
      }
      try {
        await old?.dispose();
      } catch (e) {
        debugPrint('[LiveKitService] stopLocalPreview dispose note: $e');
      }
    }
  }

  /// Connect to a LiveKit Room using WebRTC SFU
  Future<void> connect({
    required String roomName,
    required String token,
    String? serverUrl,
  }) async {
    final url = serverUrl ?? AppConfig.liveKitWsUrl;
    _callStateController.add(CallState.connecting);

    try {
      // 1. Clean up previous room if any
      await disconnect();

      // 2. Fully stop and release standalone local preview camera BEFORE room attempts
      // to capture hardware camera, preventing camera locking/stucking on mobile and web
      await stopLocalPreview();

      if (!AppConfig.isLiveKitConfigured) {
        // Mock connection for development & UI prototyping without LiveKit keys
        debugPrint('[LiveKitService] LiveKit credentials not set. Running in mock video mode.');
        _callStateController.add(CallState.connected);
        return;
      }

      final room = Room(
        roomOptions: RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioCaptureOptions: const AudioCaptureOptions(
            stopAudioCaptureOnMute: false,
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          ),
          defaultCameraCaptureOptions: CameraCaptureOptions(
            cameraPosition: _cameraPosition,
            params: kIsWeb ? VideoParametersPresets.h720_169 : VideoParametersPresets.h540_169,
            maxFrameRate: 30,
          ),
          defaultVideoPublishOptions: const VideoPublishOptions(
            simulcast: !kIsWeb,
            videoCodec: 'VP8',
          ),
        ),
      );

      _room = room;
      _listener = room.createListener();

      _setupRoomListeners(_listener!);

      await room.connect(url, token);

      // If on Web and permissions haven't been pre-granted, request audio+video combined
      if (kIsWeb && !PermissionService.instance.isGranted) {
        await PermissionService.instance.requestCombinedPermissions();
      }

      // Publish local camera and mic respecting user's mute state
      await room.localParticipant?.setCameraEnabled(!_isVideoMuted);
      await room.localParticipant?.setMicrophoneEnabled(
        !_isMicMuted,
        audioCaptureOptions: const AudioCaptureOptions(
          stopAudioCaptureOnMute: false,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        ),
      );

      // If mic was previously muted, ensure all published audio tracks are muted and disabled
      if (_isMicMuted && room.localParticipant != null) {
        for (final pub in room.localParticipant!.audioTrackPublications) {
          await pub.mute(stopOnMute: false);
          try {
            await pub.track?.disable();
            pub.track?.mediaStreamTrack.enabled = false;
          } catch (_) {}
        }
      }

      // Ensure permission is recorded as handled
      await PermissionService.instance.markPermissionHandled(granted: true);

      _callStateController.add(CallState.connected);

      // Check if remote participants already exist in room
      for (final p in room.remoteParticipants.values) {
        for (final pub in p.videoTrackPublications) {
          if (pub.track != null) {
            _remoteVideoTrack = pub.track as VideoTrack?;
            _remoteTrackController.add(_remoteVideoTrack);
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('[LiveKitService] Connect error: $e');
      _callStateController.add(CallState.failed);
      rethrow;
    }
  }

  void _setupRoomListeners(EventsListener<RoomEvent> listener) {
    listener
      ..on<TrackSubscribedEvent>((event) {
        if (event.track is VideoTrack) {
          _remoteVideoTrack = event.track as VideoTrack;
          _remoteTrackController.add(_remoteVideoTrack);
        }
      })
      ..on<TrackPublishedEvent>((event) {
        if (event.publication.track is VideoTrack) {
          _remoteVideoTrack = event.publication.track as VideoTrack;
          _remoteTrackController.add(_remoteVideoTrack);
        }
      })
      ..on<ParticipantConnectedEvent>((event) {
        debugPrint('[LiveKitService] Remote participant connected: ${event.participant.identity}');
        for (final pub in event.participant.videoTrackPublications) {
          if (pub.track != null && pub.track is VideoTrack) {
            _remoteVideoTrack = pub.track as VideoTrack;
            _remoteTrackController.add(_remoteVideoTrack);
            break;
          }
        }
      })
      ..on<TrackUnsubscribedEvent>((event) {
        if (event.track is VideoTrack) {
          _remoteVideoTrack = null;
          _remoteTrackController.add(null);
        }
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        debugPrint('[LiveKitService] Remote participant disconnected: ${event.participant.identity}');
        _remoteVideoTrack = null;
        _remoteTrackController.add(null);
        _peerDisconnectedController.add(null);
      })
      ..on<DataReceivedEvent>((event) {
        try {
          final str = utf8.decode(event.data);
          final map = jsonDecode(str) as Map<String, dynamic>;
          final type = map['type'] as String?;
          if (type == 'gift_event' || type == 'gift') {
            final giftEvent = GiftEvent.fromMap(map);
            _giftEventController.add(giftEvent);
          } else {
            final msg = ChatMessage.fromMap(map, myId: _room?.localParticipant?.identity ?? '');
            _chatMessageController.add(msg);
          }
        } catch (e) {
          debugPrint('[LiveKitService] Data message parse error: $e');
        }
      })
      ..on<RoomDisconnectedEvent>((event) {
        _callStateController.add(CallState.disconnected);
      });
  }

  /// Flip between front and rear cameras
  Future<void> flipCamera() async {
    _cameraPosition = _cameraPosition == CameraPosition.front
        ? CameraPosition.back
        : CameraPosition.front;

    final captureOptions = CameraCaptureOptions(
      cameraPosition: _cameraPosition,
      params: kIsWeb ? VideoParametersPresets.h720_169 : VideoParametersPresets.h540_169,
      maxFrameRate: 30,
    );

    if (_room?.localParticipant != null) {
      final videoTrack = _room!.localParticipant!.videoTrackPublications.firstOrNull?.track;
      if (videoTrack != null) {
        try {
          await videoTrack.restartTrack(captureOptions);
        } catch (e) {
          debugPrint('[LiveKitService] flipCamera room restartTrack error: $e');
        }
      }
    }
    if (_previewTrack != null && !_previewTrack!.isDisposed) {
      try {
        await _previewTrack!.restartTrack(captureOptions);
      } catch (e) {
        debugPrint('[LiveKitService] flipCamera preview restartTrack error: $e');
      }
    }
  }

  /// Toggle Microphone Mute with guaranteed WebRTC track silence across mobile and web
  Future<void> toggleMicrophone() async {
    _isMicMuted = !_isMicMuted;
    try {
      if (_room?.localParticipant != null) {
        final participant = _room!.localParticipant!;
        await participant.setMicrophoneEnabled(
          !_isMicMuted,
          audioCaptureOptions: const AudioCaptureOptions(
            stopAudioCaptureOnMute: false,
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          ),
        );
        for (final pub in participant.audioTrackPublications) {
          if (_isMicMuted) {
            await pub.mute(stopOnMute: false);
            try {
              await pub.track?.disable();
              pub.track?.mediaStreamTrack.enabled = false;
            } catch (_) {}
          } else {
            await pub.unmute(stopOnMute: false);
            try {
              await pub.track?.enable();
              pub.track?.mediaStreamTrack.enabled = true;
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[LiveKitService] toggleMicrophone error: $e');
    }
  }

  /// Toggle Camera Video with hardware stream preservation
  Future<void> toggleVideo() async {
    _isVideoMuted = !_isVideoMuted;
    try {
      if (_room?.localParticipant != null) {
        final participant = _room!.localParticipant!;
        await participant.setCameraEnabled(!_isVideoMuted);
        for (final pub in participant.videoTrackPublications) {
          if (_isVideoMuted) {
            await pub.mute(stopOnMute: false);
            try {
              await pub.track?.disable();
              pub.track?.mediaStreamTrack.enabled = false;
            } catch (_) {}
          } else {
            await pub.unmute(stopOnMute: false);
            try {
              await pub.track?.enable();
              pub.track?.mediaStreamTrack.enabled = true;
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[LiveKitService] toggleVideo error: $e');
    }
  }

  /// Send text chat message over WebRTC reliable data channel
  Future<void> sendChatMessage(String text, {required String myId, required String myName}) async {
    final msg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: myId,
      senderName: myName,
      text: text,
      timestamp: DateTime.now(),
      isMe: true,
    );

    // Notify local UI
    _chatMessageController.add(msg);

    if (_room?.localParticipant != null) {
      try {
        final payload = jsonEncode(msg.toMap());
        final bytes = utf8.encode(payload);
        await _room!.localParticipant!.publishData(bytes, reliable: true);
      } catch (e) {
        debugPrint('[LiveKitService] Send chat message error: $e');
      }
    }
  }

  /// Send virtual gift event over WebRTC reliable data channel
  Future<void> sendGiftEvent(GiftEvent giftEvent) async {
    // Notify local UI immediately
    _giftEventController.add(giftEvent);

    if (_room?.localParticipant != null) {
      try {
        final payload = jsonEncode(giftEvent.toMap());
        final bytes = utf8.encode(payload);
        await _room!.localParticipant!.publishData(bytes, reliable: true);
      } catch (e) {
        debugPrint('[LiveKitService] Send gift event error: $e');
      }
    }
  }

  /// Disconnect and cleanup room resources cleanly without emitting on disposed listeners
  Future<void> disconnect() async {
    if (_isDisconnecting) return;
    _isDisconnecting = true;

    try {
      _remoteVideoTrack = null;
      if (!_remoteTrackController.isClosed) {
        _remoteTrackController.add(null);
      }

      final currentRoom = _room;
      final currentListener = _listener;
      _room = null;
      _listener = null;

      if (currentRoom != null) {
        try {
          await currentRoom.disconnect();
        } catch (e) {
          debugPrint('[LiveKitService] room.disconnect note: $e');
        }
        try {
          await currentRoom.dispose();
        } catch (e) {
          debugPrint('[LiveKitService] room.dispose note: $e');
        }
      }

      if (currentListener != null) {
        try {
          await currentListener.dispose();
        } catch (e) {
          debugPrint('[LiveKitService] listener.dispose note: $e');
        }
      }
    } finally {
      if (!_callStateController.isClosed) {
        _callStateController.add(CallState.idle);
      }
      _isDisconnecting = false;
    }
  }
}
