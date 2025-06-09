import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:chat_app_flutter/services/socket_service.dart';
import 'package:chat_app_flutter/services/call_service.dart';

class CallScreen extends StatefulWidget {
  final String selfId;
  final String peerId;
  final bool isCaller;
  final bool voiceOnly;
  final String callerName;
  final SocketService socketService;

  const CallScreen({
    super.key,
    required this.selfId,
    required this.peerId,
    required this.isCaller,
    required this.voiceOnly,
    required this.callerName,
    required this.socketService,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late CallService _callService;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _hasPopped = false;

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _initCallService();
  }

  void _initCallService() {
    _callService = CallService(
      socket: widget.socketService.socket,
      selfId: widget.selfId,
      onCallDeclined: (_) => _safePop(),
      onCallEnded: (_) => _safePop(),
      onRemoteStream: (MediaStream remoteStream) {
        _remoteRenderer.srcObject = remoteStream;
        setState(() {}); // Update UI when remote stream is available
      },
    );

    _startCall();
  }

  Future<void> _startCall() async {
    await _callService.setupPeerConnection(
      isCaller: widget.isCaller,
      remoteId: widget.peerId,
      voiceOnly: widget.voiceOnly,
      callerName: widget.callerName,
    );

    final localStream = _callService.localStream;
    if (localStream != null) {
      _localRenderer.srcObject = localStream;
    }
  }

  void _safePop() {
    if (!_hasPopped && mounted) {
      _hasPopped = true;
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _hasPopped = true;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _callService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.voiceOnly ? "Voice" : "Video"} Call with ${widget.peerId}'),
      ),
      body: Stack(
        children: [
          if (!widget.voiceOnly)
            Positioned.fill(
              child: RTCVideoView(_remoteRenderer),
            ),
          if (!widget.voiceOnly)
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 120,
                height: 160,
                child: RTCVideoView(_localRenderer, mirror: true),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: FloatingActionButton(
                backgroundColor: Colors.red,
                child: const Icon(Icons.call_end),
                onPressed: () {
                  _callService.endCall(to :widget.peerId);
                  _safePop();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
