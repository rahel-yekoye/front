import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';

class CallService {
  final IO.Socket socket;
  final String selfId;
  Timer? _callTimer;

  final void Function(Map<String, dynamic>) onCallDeclined;
  final void Function(Map<String, dynamic>) onCallEnded;
  final void Function(MediaStream) onRemoteStream;
  final void Function(MediaStream stream)? onLocalStream;
  final void Function()? onCallConnected;
  final void Function(String fromId, bool voiceOnly, String callerName) onIncomingCall;
  final void Function() onCallTimeout;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _remoteSocketId;

  bool _hasHandledOffer = false;
  bool _remoteDescriptionSet = false;
  bool _isInCall = false;

  final List<RTCIceCandidate> _pendingCandidates = [];
  Timer? _callTimeoutTimer;
  String? _currentCallPartnerId;
  Function()? onCallEndedUI;
  Map<String, dynamic>? _remoteOffer; // Store offer for answering

  CallService({
    required this.socket,
    required this.selfId,
    required this.onCallDeclined,
    required this.onCallEnded,
    required this.onRemoteStream,
    required this.onIncomingCall,
    required this.onCallTimeout,
    this.onCallConnected,
    this.onLocalStream,
  }) {
    print('[CallService] Initializing CallService for user $selfId');
    _initializeSocketListeners();
    socket.emit('register_user', selfId);
  }

  void _initializeSocketListeners() {
    socket.on('incoming_call', (data) {
      final fromId = data['from'] as String;
      final voiceOnly = data['voiceOnly'] ?? false;
      final callerName = data['callerName'] ?? 'Unknown';
      print('[SOCKET EVENT] incoming_call: $data');
      _currentCallPartnerId = fromId;
      if (onIncomingCall != null) {
        onIncomingCall!(fromId, voiceOnly, callerName);
      }
    });

    socket.on('call_offer', (data) async {
      final fromId = data['from'] as String;
      print('[SOCKET EVENT] call_offer: $data');

      if (_isInCall) {
        print('[CallService] Already in a call, sending call_declined automatically.');
        socket.emit('call_declined', {'from': selfId, 'to': fromId});
        return;
      }

      // Defensive: always ensure type is a string
      final offerType = (data['type'] is String && data['type'] != null) ? data['type'] : 'offer';
      _remoteOffer = {
        'sdp': data['offer'],
        'type': offerType,
      };
      _currentCallPartnerId = fromId;

      onIncomingCall(fromId, data['voiceOnly'] ?? false, data['callerName'] ?? '');
    });

    socket.on('answer_made', (data) async {
      print('[DEBUG] answer_made event received: $data');
      final fromId = data['from'] as String;
      print('[CallService] Received answer_made from $fromId');

      if (!_isInCall || fromId != _currentCallPartnerId) {
        print('[CallService] Not in call or wrong partner, ignoring answer.');
        return;
      }

      try {
        final answer = RTCSessionDescription(
          data['answer']['sdp'],
          data['answer']['type'] ?? 'answer',
        );
        print('[CallService] Setting remote description with answer...');
        await _peerConnection!.setRemoteDescription(answer);

        // --- Add all queued ICE candidates now ---
        _remoteDescriptionSet = true;
        for (final c in _pendingCandidates) {
          await _peerConnection?.addCandidate(c);
        }
        _pendingCandidates.clear();
        // ----------------------------------------

        if (onCallConnected != null) {
          onCallConnected!();
        }
      } catch (e) {
        print('[CallService] Error setting remote description from answer: $e');
      }
    });

    socket.on('ice_candidate', (data) async {
      final fromId = data['from'] as String?;
      final candidateData = data['candidate'];
      if (candidateData == null) {
        print('[CallService] ICE candidate data is null!');
        return;
      }

      final rawCandidate = candidateData['candidate'];
      final rawSdpMid = candidateData['sdpMid'];
      final rawSdpMLineIndex = candidateData['sdpMLineIndex'];

      print('DEBUG: candidate=$rawCandidate (${rawCandidate.runtimeType}), sdpMid=$rawSdpMid (${rawSdpMid.runtimeType}), sdpMLineIndex=$rawSdpMLineIndex (${rawSdpMLineIndex.runtimeType})');

      if (rawCandidate == null || rawSdpMid == null || rawSdpMLineIndex == null) {
        print('DEBUG: One of the ICE candidate fields is null, skipping!');
        return;
      }

      final candidate = RTCIceCandidate(
        rawCandidate.toString(),
        rawSdpMid.toString(),
        rawSdpMLineIndex is int ? rawSdpMLineIndex : int.tryParse(rawSdpMLineIndex.toString()) ?? 0,
      );

      // Accept candidates if in call and from the right partner, or if waiting for answer
      if ((_isInCall && fromId == _currentCallPartnerId) || (!_isInCall && fromId == _currentCallPartnerId)) {
        if (_remoteDescriptionSet && _peerConnection != null) {
          print('[CallService] Adding ICE candidate immediately.');
          await _peerConnection?.addCandidate(candidate);
        } else {
          print('[CallService] Remote description not set yet, queueing ICE candidate.');
          _pendingCandidates.add(candidate);
        }
      } else {
        print('[CallService] ICE candidate received before call is accepted, queueing.');
        _pendingCandidates.add(candidate);
      }
    });

    socket.on('call_declined', (data) {
      final fromId = data['from'] as String;
      print('[CallService] Call declined by $fromId');
      if (_currentCallPartnerId != fromId) {
        print('[CallService] Decline from unrelated user, ignoring.');
        return;
      }
      onCallDeclined(data);
      _cleanup();
    });

    socket.on('call_ended', (data) {
      final fromId = data['from'] as String;
      print('[CallService] Call ended by $fromId');
      if (_currentCallPartnerId != fromId) {
        print('[CallService] End call from unrelated user, ignoring.');
        return;
      }
      onCallEnded(data);
      _cleanup();
      if (onCallEndedUI != null) {
        onCallEndedUI!();
      }
    });

    socket.on('call_cancelled', (data) {
      final fromId = data['from'] as String;
      print('[CallService] Call cancelled by $fromId');
      if (_currentCallPartnerId != fromId) {
        print('[CallService] Cancel from unrelated user, ignoring.');
        return;
      }
      _cleanup();
      if (onCallEndedUI != null) {
        onCallEndedUI!();
      }
    });

    socket.on('call_missed', (data) {
      final fromId = data['from'] as String;
      print('[CallService] Call missed from $fromId');
      if (_currentCallPartnerId != fromId) {
        print('[CallService] Missed call from unrelated user, ignoring.');
        return;
      }
      onCallDeclined(data);
      _cleanup();
    });
  }

  Future<void> initiateCall({
    required String to,
    required bool voiceOnly,
    required String callerName,
  }) async {
    if (_isInCall) {
      print('[CallService] Cannot initiate call: already in call.');
      return;
    }

    print('[CallService] Initiating call to $to (voiceOnly: $voiceOnly, callerName: $callerName)');
    _isInCall = true;
    _currentCallPartnerId = to;
    _remoteSocketId = to;

    final config = {
      'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'}, // STUN
        {
          'urls': 'turn:global.relay.twilio.com:3478?transport=udp', // TURN (for testing)
          'username': 'test',
          'credential': 'test'
        },
      ]
    };

    try {
      _peerConnection = await createPeerConnection(config);

      _localStream = await getUserMedia(voiceOnly: voiceOnly);
      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });

      _peerConnection?.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          print('[CallService] Received remote stream');
          _remoteStream = event.streams[0];
          onRemoteStream(_remoteStream!);
        } else {
          print('[CallService] onTrack triggered, but no streams in event');
        }
      };

      if (onLocalStream != null && _localStream != null) {
        onLocalStream!(_localStream!);
      }

      _peerConnection?.onConnectionState = (state) {
        print('[CallService] Connection state changed: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          if (onCallConnected != null) {
            onCallConnected!();
          }
        }
      };

      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      socket.emit('call_offer', {
        'from': selfId,
        'to': to,
        'offer': offer.sdp,
        'type': offer.type,
        'voiceOnly': voiceOnly,
        'callerName': callerName,
      });

      _startCallTimeout();
    } catch (e) {
      print('[CallService] Error during call setup: $e');
      _cleanup();
    }
  }

  Future<MediaStream> getUserMedia({required bool voiceOnly}) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': voiceOnly
          ? false
          : {
              'facingMode': 'user',
            },
    };

    try {
      final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      return stream;
    } catch (e) {
      print('[CallService] Error getting user media: $e');
      rethrow;
    }
  }

  Future<void> sendOffer({
    required String to,
    required RTCSessionDescription offer,
    required bool voiceOnly,
    required String callerName,
  }) async {
    print('[CallService] Sending offer to $to');
    socket.emit('call_offer', {
      'from': selfId,
      'to': to,
      'offer': offer.sdp,
      'type': offer.type,
      'voiceOnly': voiceOnly,
      'callerName': callerName,
    });
  }

  Future<void> sendAnswer({
    required String to,
    required RTCSessionDescription answer,
  }) async {
    print('[CallService] Sending answer to $to');
    socket.emit('answer_made', {
      'from': selfId,
      'to': to,
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });
  }

  Future<void> sendIceCandidate({
    required String to,
    required RTCIceCandidate candidate,
  }) async {
    print('[CallService] Sending ICE candidate to $to');
    socket.emit('ice_candidate', {
      'from': selfId,
      'to': to,
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid?.toString(),
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    });
  }
Future<void> answerCall() async {
  if (_currentCallPartnerId == null || _remoteOffer == null) {
    print('[CallService] No call partner ID or offer to answer call.');
    return;
  }

  // Set this early so ICE candidates are not ignored
  _isInCall = true;

  print('[CallService] _remoteOffer: $_remoteOffer'); // Debug print

  try {
    print('[CallService] Creating peer connection for answering call...');
    await _createPeerConnection();

    final offerSdp = (_remoteOffer!['sdp'] is String && _remoteOffer!['sdp'] != null && _remoteOffer!['sdp'] != '')
        ? _remoteOffer!['sdp']
        : '';

    final offerType = (_remoteOffer!['type'] is String && _remoteOffer!['type'] != null && _remoteOffer!['type'] != '')
        ? _remoteOffer!['type']
        : 'offer';

    final offer = RTCSessionDescription(
      offerSdp,
      offerType,
    );
    await _peerConnection?.setRemoteDescription(offer);

    // --- Add all queued ICE candidates now ---
    _remoteDescriptionSet = true;
    for (final c in _pendingCandidates) {
      await _peerConnection?.addCandidate(c);
    }
    _pendingCandidates.clear();
    // ----------------------------------------

    print('[CallService] Creating answer...');
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    print('[CallService] Sending answer to $_currentCallPartnerId...');
    socket.emit('make_answer', {
      'to': _currentCallPartnerId,
      'from': selfId,
      'answer': {
        'sdp': answer.sdp,
        'type': answer.type,
      },
    });

    socket.emit('call_answered', {
      'from': selfId,
      'to': _currentCallPartnerId,
    });

    // _isInCall = true; // Already set above
  } catch (e) {
    print('[CallService] Error answering call: $e');
  }
}

  void dispose() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream = null;
    _peerConnection?.close();
    _peerConnection = null;
    _remoteStream?.getTracks().forEach((track) => track.stop());
    _remoteStream = null;
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
  }

  void declineCall({required String to}) {
    print('[CallService] Declining call from $to');
    socket.emit('call_declined', {
      'from': selfId,
      'to': to,
    });
    _cleanup();
  }

  void endCall({required String to}) {
    print('[CallService] Ending call with $to');
    socket.emit('call_ended', {
      'from': selfId,
      'to': to,
    });
    _cleanup();
    if (onCallEndedUI != null) {
      onCallEndedUI!();
    }
  }

  void _startCallTimeout() {
    _callTimeoutTimer = Timer(Duration(seconds: 30), () {
      print('[CallService] Call timeout. No answer received.');
      onCallTimeout();
      socket.emit('call_missed', {
        'from': selfId,
        'to': _currentCallPartnerId,
      });
      _cleanup();
    });
  }

  void _cancelCallTimeout() {
    if (_callTimeoutTimer != null && _callTimeoutTimer!.isActive) {
      _callTimeoutTimer?.cancel();
      print('[CallService] Call timeout canceled');
    }
  }

  int _callSeconds = 0;
  void toggleMute(bool muted) {
    if (_localStream != null) {
      for (var track in _localStream!.getAudioTracks()) {
        track.enabled = !muted;
      }
    }
  }

  void _startCallDurationTimer(void Function(int seconds) onTick) {
    _callSeconds = 0;
    _callTimer?.cancel();
    _callTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _callSeconds++;
      onTick(_callSeconds);
    });
  }

  void stopCallDurationTimer() {
    _callTimer?.cancel();
    _callTimer = null;
    _callSeconds = 0;
  }

  void switchCamera() {
    final MediaStreamTrack? videoTrack = _localStream!.getVideoTracks().firstWhere(
      (track) => track.kind == 'video',
      orElse: () => null as MediaStreamTrack,
    );
    if (videoTrack != null) {
      Helper.switchCamera(videoTrack);
    }
  }

  void toggleSpeaker(bool enabled) {
    Helper.setSpeakerphoneOn(enabled);
  }

  void _cleanup() {
    print('[CallService] Cleaning up call state...');
    _isInCall = false;
    _remoteDescriptionSet = false;
    _hasHandledOffer = false;
    _currentCallPartnerId = null;
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    try {
      _peerConnection?.close();
    } catch (e) {
      print('[CallService] Error closing peer connection: $e');
    }
    _peerConnection = null;
    try {
      _localStream?.getTracks().forEach((t) => t.stop());
    } catch (e) {
      print('[CallService] Error stopping local stream: $e');
    }
    _localStream = null;
    try {
      _remoteStream?.getTracks().forEach((t) => t.stop());
    } catch (e) {
      print('[CallService] Error stopping remote stream: $e');
    }
    _remoteStream = null;
    _pendingCandidates.clear();
  }

  Future<void> _createPeerConnection() async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        print('[CallService] Sending ICE candidate to $_currentCallPartnerId');
        socket.emit('ice_candidate', {
          'to': _currentCallPartnerId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid?.toString(),
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        });
      }
    };

    _peerConnection?.onAddStream = (MediaStream stream) {
      print('[CallService] Received remote stream');
      onRemoteStream(stream);
    };

    if (_localStream != null) {
      _peerConnection?.addStream(_localStream!);
    }
  }

  bool get isInCall => _isInCall;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
}