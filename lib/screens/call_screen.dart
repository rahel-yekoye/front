// ... all your previous imports
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/socket_service.dart';
import '../services/call_service.dart';

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

  const CallScreen({
    Key? key,
    required this.socketService,
    required this.selfId,
    required this.peerId,
    required this.isCaller,
    required this.voiceOnly,
    required this.callerName,
  }) : super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  CallStatus _callStatus = CallStatus.idle;
  bool _isMuted = false;
  bool _speakerOn = false;
  Timer? _callTimer;
  int _callDurationSeconds = 0;
  late CallService _callService;
  Timer? _callTimeoutTimer;
  bool _hasAnswered = false;

  @override
  void initState() {
    super.initState();
    _initializeRenderers();

    _callService = CallService(
      socket: widget.socketService.socket,
      selfId: widget.selfId,
      onCallDeclined: _onCallDeclined,
      onCallEnded: _onCallEnded,
      onRemoteStream: _onRemoteStreamReceived,
      onLocalStream: _onLocalStreamReceived,
      onCallTimeout: _onCallTimeout,
      onCallConnected: _onCallConnected,
      onIncomingCall: _onIncomingCall,
    );
    

    _callService.onCallEndedUI = () {
      if (mounted) Navigator.of(context).pop();
    };

    _startTimeoutTimer();

    widget.socketService.socket.on('call_ended', (_) {
      if (mounted) Navigator.of(context).pop();
    });

    if (widget.isCaller) {
      _callStatus = CallStatus.outgoing;
      _callService.initiateCall(
        to: widget.peerId,
        voiceOnly: widget.voiceOnly,
        callerName: widget.callerName,
      );
      _startCallTimeoutCountdown();
    } else {
      _callStatus = CallStatus.incoming;
    }
  }

  void _startTimeoutTimer() {
    _callTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (!_hasAnswered) {
        _callService.endCall(to: widget.peerId);
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  Future<void> _initializeRenderers() async {
    await _remoteRenderer.initialize();
    await _localRenderer.initialize();
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _remoteRenderer.dispose();
    _localRenderer.dispose();
    _callService.dispose();
    widget.socketService.socket.off('call_ended');
    super.dispose();
  }

  void _startCallTimeoutCountdown() {
    _callTimer?.cancel();
    _callTimer = Timer(const Duration(seconds: 30), () {
      if (_callStatus == CallStatus.outgoing) {
        _onCallTimeout();
      }
    });
  }

  void _startCallDurationTimer() {
    _callDurationSeconds = 0;
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _callDurationSeconds++;
        });
      }
    });
  }

  void _stopCallDurationTimer() {
    _callTimer?.cancel();
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _onCallDeclined(Map<String, dynamic> _) {
    if (!mounted) return;
    setState(() => _callStatus = CallStatus.declined);
    _showCallEndedDialog('Call Declined');
  }

  void _onCallEnded(Map<String, dynamic> _) {
    if (!mounted) return;
    setState(() => _callStatus = CallStatus.ended);
    _showCallEndedDialog('Call Ended');
  }

  void _onCallTimeout() {
    if (!mounted) return;
    setState(() => _callStatus = CallStatus.timeout);
    _callService.endCall(to: widget.peerId);
    _showCallEndedDialog('No Answer');
    // Add this:
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  void _onCallConnected() {
    if (!mounted) return;
    setState(() => _callStatus = CallStatus.connected);
    _startCallDurationTimer();
  }

  void _onRemoteStreamReceived(MediaStream stream) {
    _remoteRenderer.srcObject = stream;
  }

  void _onLocalStreamReceived(MediaStream stream) {
    _localRenderer.srcObject = stream;
  }

  void _onIncomingCall(String callerId, bool voiceOnly, String callerName) {
    if (!mounted) return;
    if (_callStatus != CallStatus.incoming) {
      setState(() => _callStatus = CallStatus.incoming);
    }
  }

  Future<void> _answerCall() async {
    print('[CallScreen] Answer button pressed');
    _hasAnswered = true;
    _callTimeoutTimer?.cancel();
    await _callService.answerCall();
  }

  void _rejectCall() {
    _callService.declineCall(to: widget.peerId);
    Navigator.pop(context);
  }

  void _endCall() {
    _callService.endCall(to: widget.peerId);
    Navigator.pop(context);
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _callService.toggleMute(_isMuted);
    });
  }

  void _toggleSpeaker() {
    setState(() {
      _speakerOn = !_speakerOn;
      Helper.setSpeakerphoneOn(_speakerOn);
    });
  }

  void _showCallEndedDialog(String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // dialog
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop(); // CallScreen
              }
            },
            child: const Text('OK'),
          )
        ],
      ),
    );
  }

  /// ✅ NEW METHOD: Cancel outgoing call
  void cancelOutgoingCall() {
    if (widget.peerId.isNotEmpty) {
      widget.socketService.socket.emit('call_cancelled', {
        'from': widget.selfId,
        'to': widget.peerId,
      });
      print('[CallScreen] Emitted call_cancelled to ${widget.peerId}');
    }

    _callService.dispose();
    _callTimer?.cancel();
    Navigator.of(context).pop();
  }

  // ------------------- UI -----------------------
  Widget _buildIncomingCallUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Incoming call from ${widget.callerName}',
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

  Widget _buildInCallUI() {
    return Stack(
      children: [
        Positioned.fill(
          child: widget.voiceOnly
              ? const Center(
                  child: Icon(Icons.call, color: Colors.white, size: 100),
                )
              : RTCVideoView(_remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
        ),
        if (!widget.voiceOnly)
          Positioned(
            right: 20,
            bottom: 200,
            width: 120,
            height: 160,
            child: RTCVideoView(_localRenderer,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
          ),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Text(
              'In call with ${widget.callerName}',
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
