import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class CallService {
  final IO.Socket socket;
  final String selfId;
  final void Function(Map<String, dynamic>) onCallDeclined;
  final void Function(Map<String, dynamic>) onCallEnded;
  final void Function(MediaStream) onRemoteStream;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  bool _hasHandledOffer = false;
  bool _remoteDescriptionSet = false;
  bool _isInCall = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  CallService({
    required this.socket,
    required this.selfId,
    required this.onCallDeclined,
    required this.onCallEnded,
    required this.onRemoteStream,
  }) {
    print('[CallService] Initializing CallService for user $selfId');
    _initializeSocketListeners();
  }

  void _initializeSocketListeners() {
    socket.on('call_offer', (data) async {
      print('[CallService] Received call_offer from ${data['from']}');
      if (_isInCall) {
        print('[CallService] Already in a call, ignoring incoming offer.');
        return;
      }
      try {
        print('[CallService] Handling incoming offer...');
        await _handleIncomingOffer(
          offerData: data['offer'],
          fromId: data['from'],
          voiceOnly: data['voiceOnly'] ?? false,
          callerName: data['callerName'] ?? '',
        );
        print('[CallService] Incoming offer handled successfully.');
      } catch (e) {
        print('[CallService] Error handling call_offer: $e');
      }
    });

    socket.on('answer_made', (data) async {
      print('[CallService] Received answer_made from ${data['from']}');
      try {
        final answer = RTCSessionDescription(
          data['answer']['sdp'],
          data['answer']['type'],
        );
        print('[CallService] Setting remote description with answer...');
        await _peerConnection?.setRemoteDescription(answer);
        _remoteDescriptionSet = true;

        if (_pendingCandidates.isNotEmpty) {
          print('[CallService] Adding ${_pendingCandidates.length} pending ICE candidates...');
        }
        for (final candidate in _pendingCandidates) {
          await _peerConnection?.addCandidate(candidate);
        }
        _pendingCandidates.clear();
        print('[CallService] Remote description set and pending ICE candidates added.');
      } catch (e) {
        print('[CallService] Error setting remote description from answer: $e');
      }
    });

    socket.on('ice_candidate', (data) async {
      try {
        final candidate = RTCIceCandidate(
          data['candidate']['candidate'],
          data['candidate']['sdpMid'],
          data['candidate']['sdpMLineIndex'],
        );
        print('[CallService] Received ICE candidate from ${data['from']}');
        if (_remoteDescriptionSet) {
          print('[CallService] Adding ICE candidate immediately.');
          await _peerConnection?.addCandidate(candidate);
        } else {
          print('[CallService] Remote description not set yet, queueing ICE candidate.');
          _pendingCandidates.add(candidate);
        }
      } catch (e) {
        print('[CallService] Error adding ICE candidate: $e');
      }
    });

    socket.on('call_declined', (data) {
      print('[CallService] Call declined by ${data['from']}');
      onCallDeclined(data);
      _cleanup();
    });

    socket.on('call_ended', (data) {
      print('[CallService] Call ended by ${data['from']}');
      onCallEnded(data);
      _cleanup();
    });
  }

  void initiateCall({
    required String to,
    required bool voiceOnly,
    required String callerName,
  }) {
    if (_isInCall) {
      print('[CallService] Cannot initiate call: already in call.');
      return;
    }
    print('[CallService] Initiating call to $to (voiceOnly: $voiceOnly, callerName: $callerName)');
    _isInCall = true;
    socket.emit('call_initiate', {
      'from': selfId,
      'to': to,
      'voiceOnly': voiceOnly,
      'callerName': callerName,
    });
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
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'voiceOnly': voiceOnly,
      'callerName': callerName,
    });
  }

  Future<void> sendAnswer({
    required String to,
    required RTCSessionDescription answer,
  }) async {
    print('[CallService] Sending answer to $to');
    socket.emit('make_answer', {
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
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    });
  }

  void declineCall({required String to}) {
    print('[CallService] Declining call from $to');
    socket.emit('decline_call', {
      'from': selfId,
      'to': to,
    });
    _cleanup();
  }

  void endCall({required String to}) {
    print('[CallService] Ending call with $to');
    socket.emit('end_call', {
      'from': selfId,
      'to': to,
    });
    _cleanup();
  }

  Future<void> setupPeerConnection({
    required bool isCaller,
    required String remoteId,
    required bool voiceOnly,
    required String callerName,
  }) async {
    print('[CallService] Setting up peer connection (isCaller: $isCaller) for call with $remoteId');
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };

    try {
      _peerConnection = await createPeerConnection(configuration);
      print('[CallService] PeerConnection created');

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': !voiceOnly,
      });
      print('[CallService] Obtained local media stream (audio: true, video: ${!voiceOnly})');

      // Add tracks to peer connection
      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
        print('[CallService] Added local track of kind ${track.kind} to peer connection');
      });

      _peerConnection?.onIceCandidate = (candidate) {
        if (candidate != null) {
          print('[CallService] onIceCandidate triggered');
          sendIceCandidate(to: remoteId, candidate: candidate);
        }
      };

      _peerConnection?.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          print('[CallService] onTrack triggered - remote stream received');
          onRemoteStream(_remoteStream!);
        }
      };

      if (isCaller) {
        print('[CallService] Creating offer as caller...');
        final offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);
        print('[CallService] Local description set with offer, sending to $remoteId');
        await sendOffer(
          to: remoteId,
          offer: offer,
          voiceOnly: voiceOnly,
          callerName: callerName,
        );
      }
    } catch (e) {
      print('[CallService] setupPeerConnection error: $e');
      _cleanup();
    }
  }

  Future<void> _handleIncomingOffer({
    required Map<String, dynamic> offerData,
    required String fromId,
    required bool voiceOnly,
    required String callerName,
  }) async {
    print('[CallService] Handling incoming call offer from $fromId');
    if (_hasHandledOffer) {
      print('[CallService] Offer already handled, ignoring duplicate.');
      return;
    }
    _hasHandledOffer = true;
    _isInCall = true;

    try {
      final offer = RTCSessionDescription(
        offerData['sdp'],
        offerData['type'],
      );

      print('[CallService] Setting up peer connection as callee...');
      await setupPeerConnection(
        isCaller: false,
        remoteId: fromId,
        voiceOnly: voiceOnly,
        callerName: callerName,
      );

      print('[CallService] Setting remote description with received offer...');
      await _peerConnection?.setRemoteDescription(offer);
      _remoteDescriptionSet = true;

      if (_pendingCandidates.isNotEmpty) {
        print('[CallService] Adding ${_pendingCandidates.length} queued ICE candidates...');
      }
      for (final candidate in _pendingCandidates) {
        await _peerConnection?.addCandidate(candidate);
      }
      _pendingCandidates.clear();

      print('[CallService] Creating and sending answer...');
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      await sendAnswer(to: fromId, answer: answer);

      print('[CallService] Incoming call offer processed successfully.');
    } catch (e) {
      print('[CallService] Error handling offer: $e');
      _cleanup();
    }
  }

  void _cleanup() {
    print('[CallService] Cleaning up call state...');
    _localStream?.getTracks().forEach((track) {
      print('[CallService] Stopping local track of kind ${track.kind}');
      track.stop();
    });
    _localStream?.dispose();
    _peerConnection?.close();

    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;

    _hasHandledOffer = false;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    _isInCall = false;
    print('[CallService] Call state cleaned up.');
  }

  void dispose() {
    print('[CallService] Disposing CallService...');
    _cleanup();
  }

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  RTCPeerConnection? get peerConnection => _peerConnection;
}
