import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';
import '../models/message.dart' as models;
import '../screens/call_screen.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  String? _selfId;

  IO.Socket get socket {
    if (_socket == null) {
      throw Exception('Socket not initialized. Call connect() first.');
    }
    return _socket!;
  }

  bool _isPrivateListenerSet = false;
  bool _isGroupListenerSet = false;
  bool _isCallListenerSet = false;
  bool _isCallSignalListenerSet = false;
  bool _isEndCallListenerSet = false;

  Future<void> connect({required String userId}) async {
    print('SocketService instance hash (connect): ${identityHashCode(this)}');
    if (_socket != null && _socket!.connected && _selfId == userId) {
      print('🔁 Socket already connected for user: $userId');
      return;
    }

    _selfId = userId;

    try {
      _socket?.dispose();
    } catch (_) {}

    resetListeners();

    final completer = Completer<void>();

    _socket = IO.io('http://192.168.137.145:4000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    _socket!.onConnect((_) {
      print('✅ Connected to the socket server');
      if (_selfId != null) {
        print('[SOCKET] Emitting register_user: $_selfId');
        _socket!.emit('register_user', _selfId);
        print('🧑‍💻 Registered user for signaling: $_selfId');
      }
      completer.complete();
    });

    _socket!.onDisconnect((_) {
      print('🔌 Disconnected from the socket server');
    });

    _socket!.onConnectError((data) => print('❌ Connect Error: $data'));
    _socket!.onError((data) => print('❌ General Error: $data'));

    _socket!.connect();

    return completer.future;
  }

  void disconnect() {
    if (_socket != null && _socket!.connected) {
      _socket!.disconnect();
    }
  }

  // -------------------
  // Private chat
  // -------------------

  void registerUser(String username) {
    print('🧑‍💻 Registering user: $username');
    _socket?.emit('join_room', username);
  }

  void joinRoom(String roomId) {
    if (_socket == null) {
      print('❌ Socket not initialized.');
      return;
    }

    _socket!.off('connect');

    if (_socket!.connected) {
      _socket!.emit('join_room', roomId);
      print('✅ Immediately joined room: $roomId');
    } else {
      _socket!.on('connect', (_) {
        print('🔁 Socket connected later. Now joining room: $roomId');
        _socket!.emit('join_room', roomId);
      });

      if (!_socket!.connected && !_socket!.active) {
        print('⚙️ Connecting socket...');
        _socket!.connect();
      }
    }
  }
void onMessagesRead(Function(Map<String, dynamic>) callback) {
  _socket?.off('messages_read');
  _socket?.on('messages_read', (data) {
    print('📩 messages_read event received: $data');
    if (data is Map<String, dynamic>) {
      callback(data);
    } else if (data is Map) {
      // Some dart:io socket.io versions may not cast perfectly
      callback(Map<String, dynamic>.from(data));
    }
  });
}

  void sendMessage(Map<String, dynamic> messageData) {
    if (_socket != null && _socket!.connected) {
      print('📤 Sending private message: $messageData');
      _socket!.emit('send_message', messageData);
    } else {
      print('❌ Socket not connected');
    }
  }

  void onMessageReceived(Function(models.Message) callback) {
    if (_socket != null) {
      _socket!.off('receive_message');
      _socket!.on('receive_message', (data) {
        print('📨 Private message received: $data');
        final msg = _processRawMessage(data);
        callback(msg);
      });
    }
  }

  // -------------------
  // Group chat
  // -------------------

  void joinGroups(List<String> groupIds) {
    if (_socket != null) {
      print('👥 Joining groups: $groupIds');
      _socket!.emit('join_groups', groupIds);
    }
  }

  void sendGroupMessage(Map<String, dynamic> messageData) {
    if (_socket != null && _socket!.connected) {
      print('📤 Sending group message: $messageData');
      _socket!.emit('send_group_message', messageData);
    } else {
      print('❌ Socket not connected');
    }
  }

  void onGroupMessageReceived(Function(models.Message) callback) {
    if (!_isGroupListenerSet && _socket != null) {
      _socket!.on('group_message', (data) {
        print('📨 Group message received: $data');
        final msg = _processRawMessage(data);
        callback(msg);
      });
      _isGroupListenerSet = true;
    }
  }

  // -------------------
  // Call signaling
  // -------------------

  void onCallMade(Function(Map<String, dynamic>) handler) {
    if (!_isCallListenerSet && _socket != null) {
      _socket!.on('call_made', (data) {
        if (data is Map) {
          print('📞 Call made signaling data: $data');
          handler(Map<String, dynamic>.from(data));
        }
      });
      _isCallListenerSet = true;
    }
  }

  void sendCallSignal(Map<String, dynamic> signalData) {
    if (_socket != null && _socket!.connected) {
      print('📤 Sending call signaling data: $signalData');
      _socket!.emit('call_signal', signalData);
    } else {
      print('❌ Socket not connected');
    }
  }

  void onCallSignalReceived(Function(Map<String, dynamic>) handler) {
    if (!_isCallSignalListenerSet && _socket != null) {
      _socket!.on('call_signal', (data) {
        if (data is Map) {
          print('📞 Call signaling data received: $data');
          handler(Map<String, dynamic>.from(data));
        }
      });
      _isCallSignalListenerSet = true;
    }
  }

  void sendEndCall(Map<String, dynamic> callEndData) {
    if (_socket != null && _socket!.connected) {
      print('📤 Sending end call signal: $callEndData');
      _socket!.emit('end_call', callEndData);
    }
  }

  void onEndCallReceived(Function(Map<String, dynamic>) handler) {
    if (!_isEndCallListenerSet && _socket != null) {
      _socket!.on('end_call', (data) {
        if (data is Map) {
          print('📞 End call signal received: $data');
          handler(Map<String, dynamic>.from(data));
        }
      });
      _isEndCallListenerSet = true;
    }
  }

  // Incoming call listener with callback style
  void onIncomingCall(void Function(Map<String, dynamic>) callback) {
    if (_socket != null) {
      _socket!.off('incoming_call');
      _socket!.on('incoming_call', (data) {
        print('[SOCKET] incoming_call event data: $data');
        if (data is Map) {
          callback(Map<String, dynamic>.from(data));
        }
      });
    }
  }

  /// Initialize socket listeners for incoming calls and other call events.
  /// This method should be called after connection to setup navigation to CallScreen on incoming call.
  void initializeSocketListeners({
    required BuildContext context,
    required String selfId,
  }) {
    if (_socket == null) {
      print('❌ Socket not initialized.');
      return;
    }

    _socket!.off('incoming_call');

    _socket!.on('incoming_call', (data) {
      print('[SOCKET] incoming_call event received: $data');

      if (data is! Map) {
        print('❌ Invalid data for incoming_call event');
        return;
      }

      final Map<String, dynamic> callData = Map<String, dynamic>.from(data);

      final callerId = callData['from'];
      final callerName = callData['callerName'];
      final voiceOnly = callData['voiceOnly'] ?? false;

      if (callerId == null) {
        print('❌ incoming_call missing callerId');
        return;
      }

      // Navigate to CallScreen passing all needed parameters
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            selfId: selfId,
            peerId: callerId,
            isCaller: false,
            voiceOnly: voiceOnly,
            callerName: callerName,
            socketService: this,
          ),
        ),
      );
    });
  }

  void declineCall(String to) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('decline_call', {
        'from': _selfId,
        'to': to,
      });
      print('📞 Declined call from $to');
    }
  }

  // -------------------
  // Helpers
  // -------------------

  models.Message _processRawMessage(dynamic data) {
    return models.Message.fromJson(Map<String, dynamic>.from(data));
  }

  void resetListeners() {
    _isPrivateListenerSet = false;
    _isGroupListenerSet = false;
    _isCallListenerSet = false;
    _isCallSignalListenerSet = false;
    _isEndCallListenerSet = false;

    _socket?.off('receive_message');
    _socket?.off('group_message');
    _socket?.off('call_made');
    _socket?.off('call_signal');
    _socket?.off('end_call');
    _socket?.off('incoming_call');
  }

  void dispose() {
    resetListeners();
    _socket?.dispose();
  }

  void offMessageReceived() {
    _socket?.off('receive_message');
  }

  void offIncomingCall() {
    socket.off('incoming_call');
  }
}
