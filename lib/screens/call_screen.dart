import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/socket_service.dart';
import '../services/call_service.dart';
import 'package:flutter/foundation.dart'; // for kIsWeb

enum CallStatus {
  idle,
  ringing,
  incoming,
  outgoing,
  connected,
  ended,
  declined,
  timeout,
}

class CallScreen extends StatefulWidget {
  final SocketService socketService;
  final String selfId;
  final String peerId;
  final bool isCaller;
  final bool voiceOnly;
  final String callerName;
  final VoidCallback? onCallScreenClosed;

  const CallScreen({
    super.key,
    required this.socketService,
    required this.selfId,
    required this.peerId,
    required this.isCaller,
    required this.voiceOnly,
    required this.callerName,
    this.onCallScreenClosed,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  CallStatus _callStatus = CallStatus.idle;
  bool _isMuted = false;
  bool _speakerOn = false;
  int _callDurationSeconds = 0;
  late CallService _callService;
  Timer? _callTimeoutTimer;
  bool _hasAnswered = false;
  Timer? _callDurationTimer;
  String _remoteName = "";
  bool _hasExited = false;

  @override
  void initState() {
    super.initState();
    _remoteName = widget.isCaller ? widget.peerId : widget.callerName;
    _initializeRenderers();

    _callService = CallService(
      socket: widget.socketService.socket, // <-- use the socket from the injected SocketService
      selfId: widget.selfId,
      onCallDeclined: _onCallDeclined,
      onCallEnded: _onCallEnded,
      onRemoteStream: _onRemoteStreamReceived,
      onLocalStream: _onLocalStreamReceived,
      onCallTimeout: _onCallTimeout,
      onCallConnected: _onCallConnected,
      onIncomingCall: _onIncomingCall,
      onCallCancelled: _onCallCancelled,
    );

    if (widget.isCaller) {
      _callStatus = CallStatus.outgoing;
      _callService.initiateCall(
        to: widget.peerId,
        voiceOnly: widget.voiceOnly,
        callerName: widget.callerName,
      );
      _startCallTimeoutCountdown();
    } else {
      _callStatus = CallStatus.ringing;
      _startTimeoutTimer();
    }
  }

  Future<void> _initializeRenderers() async {
    await _remoteRenderer.initialize();
    await _localRenderer.initialize();
  }

  @override
  void dispose() {
    _callService.dispose();
    if (widget.onCallScreenClosed != null) {
      widget.onCallScreenClosed!();
    }
    _callTimeoutTimer?.cancel();
    _callDurationTimer?.cancel();
    _remoteRenderer.dispose();
    _localRenderer.dispose();
    super.dispose();
  }

  void _startTimeoutTimer() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (!_hasAnswered) {
        _callService.endCall(to: widget.peerId);
        _exitCallScreen();
      }
    });
  }

  void _startCallTimeoutCountdown() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (_callStatus == CallStatus.outgoing) {
        _onCallTimeout();
      }
    });
  }

  void _startCallDurationTimer() {
    _callDurationSeconds = 0;
    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDurationSeconds++;
        });
      }
    });
  }

  void _stopCallDurationTimer() {
    _callDurationTimer?.cancel();
    _callDurationTimer = null;
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _onCallDeclined([Map<String, dynamic>? _]) {
    if (!mounted) return;
    _stopCallDurationTimer();
    setState(() => _callStatus = CallStatus.declined);
    // Show "Call ended" for 1 second before exiting
    Future.delayed(const Duration(seconds: 1), () {
      _exitCallScreen();
    });
  }

  void _onCallEnded(dynamic _) {
    if (!mounted) return;
    _stopCallDurationTimer();
    setState(() => _callStatus = CallStatus.ended);
    _exitCallScreen();
  }

  void _onCallTimeout() {
    if (!mounted) return;
    _stopCallDurationTimer();
    setState(() => _callStatus = CallStatus.timeout);
    _callService.endCall(to: widget.peerId);
    // Show "Call ended" for 1 second before exiting
    Future.delayed(const Duration(seconds: 1), () {
      _exitCallScreen();
    });
  }

  void _onCallConnected() {
    _callTimeoutTimer?.cancel();
    setState(() {
      _callStatus = CallStatus.connected;
    });
    _startCallDurationTimer();
    _listenPeerConnectionState();
  }

  void _onRemoteStreamReceived(MediaStream stream) {
    _remoteRenderer.srcObject = stream;
  }

  void _onLocalStreamReceived(MediaStream stream) {
    _localRenderer.srcObject = stream;
  }

  void _onIncomingCall(String callerId, bool voiceOnly, String callerName) {
    if (!mounted) return;
    setState(() {
      _callStatus = CallStatus.incoming;
      _remoteName = callerName;
    });
  }

  Future<void> _answerCall() async {
    if (_hasAnswered) return;
    _hasAnswered = true;
    _callTimeoutTimer?.cancel();
    setState(() {
      _callStatus = CallStatus.connected;
    });
    _startCallDurationTimer();
    await _callService.answerCall();
    _listenPeerConnectionState();
  }

  void _rejectCall() {
    _callService.declineCall(to: widget.peerId);
    _exitCallScreen();
  }

  void _endCall() {
    widget.socketService.socket.emit('end_call', {
      'from': widget.selfId,
      'to': widget.peerId,
      'durationSeconds': _callDurationSeconds, // Make sure this is set!
    });
    _callService.endCall(to: widget.peerId);
    _stopCallDurationTimer();
    setState(() => _callStatus = CallStatus.ended);
    _exitCallScreen();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      if (_callService.localStream != null) {
        for (var track in _callService.localStream!.getAudioTracks()) {
          track.enabled = !_isMuted;
        }
      }
    });
  }

  void _toggleSpeaker() {
    setState(() {
      _speakerOn = !_speakerOn;
      if (!kIsWeb) {
        Helper.setSpeakerphoneOn(_speakerOn);
      }
    });
  }

  void _exitCallScreen() {
    if (_hasExited) return;
    _hasExited = true;
    print('[CallScreen] Exiting call screen');
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    });
  }

  void cancelOutgoingCall() {
    if (widget.peerId.isNotEmpty) {
      widget.socketService.socket.emit('call_cancelled', {
        'from': widget.selfId,
        'to': widget.peerId,
      });
    }
    _callService.dispose();
    _callTimeoutTimer?.cancel();
    _stopCallDurationTimer();
    _exitCallScreen();
  }

  void _listenPeerConnectionState() {
    final pc = _callService.peerConnection;
    if (pc == null) return;
    pc.onConnectionState = (state) {
      print('[CallScreen] PeerConnection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _onCallEnded(null);
      }
    };
  }

  void _onCallCancelled([Map<String, dynamic>? data]) {
    if (!mounted) return;
    if (_callStatus == CallStatus.ringing && !_hasAnswered) {
      // Send missed call message to chat
         }
    _exitCallScreen();
  }

  // ------------------- UI -----------------------
  Widget _buildIncomingCallUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Incoming call from $_remoteName',
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _answerCall,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(20),
              ),
              child: const Icon(Icons.call, size: 32),
            ),
            const SizedBox(width: 50),
            ElevatedButton(
              onPressed: _rejectCall,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(20),
              ),
              child: const Icon(Icons.call_end, size: 32),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCallingUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Calling...',
            style: TextStyle(color: Colors.white, fontSize: 24)),
        const SizedBox(height: 20),
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: cancelOutgoingCall,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(20),
          ),
          child: const Icon(Icons.call_end, size: 32),
        ),
      ],
    );
  }

  Widget _buildRingingUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Ringing...',
            style: TextStyle(color: Colors.white, fontSize: 24)),
        const SizedBox(height: 20),
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: cancelOutgoingCall,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(20),
          ),
          child: const Icon(Icons.call_end, size: 32),
        ),
      ],
    );
  }

  Widget _buildInCallUI() {
    return Stack(
      children: [
        Positioned.fill(
          child: RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
        if (widget.voiceOnly)
          const Center(
            child: Icon(Icons.call, color: Colors.white, size: 100),
          ),
        if (!widget.voiceOnly)
          Positioned(
            right: 20,
            bottom: 200,
            width: 120,
            height: 160,
            child: RTCVideoView(
              _localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Text(
              'In call with $_remoteName',
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 60, right: 20),
            child: Text(
              _formatDuration(_callDurationSeconds),
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: _toggleMute,
                  icon: Icon(
                    _isMuted ? Icons.mic_off : Icons.mic,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                IconButton(
                  onPressed: _endCall,
                  icon: const Icon(Icons.call_end, color: Colors.red, size: 36),
                ),
                IconButton(
                  onPressed: _toggleSpeaker,
                  icon: Icon(
                    _speakerOn ? Icons.volume_up : Icons.volume_off,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_callStatus) {
      case CallStatus.ringing:
        body = _buildRingingUI();
        break;
      case CallStatus.incoming:
        body = _buildIncomingCallUI();
        break;
      case CallStatus.outgoing:
        body = _buildCallingUI();
        break;
      case CallStatus.connected:
        body = _buildInCallUI();
        break;
      case CallStatus.ended:
      case CallStatus.declined:
      case CallStatus.timeout:
        body = const Center(
          child: Text('Call ended', style: TextStyle(color: Colors.white, fontSize: 22)),
        );
        break;
      case CallStatus.idle:
      default:
        body = const SizedBox.shrink();
        break;
    }

    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black87,
          child: body,
        ),
      ),
    );
  }
}