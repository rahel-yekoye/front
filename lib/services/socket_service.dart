import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  late IO.Socket socket;
  bool isListenerSet = false; // Track if the listener is already set

  void connect() {
    socket = IO.io('http://localhost:4000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false, // First set to false
    });

    socket.connect(); // Then connect

    // ✅ Test connection
    socket.onConnect((_) {
      print('Connected to the socket server');
    });
    socket.onDisconnect((_) {
      print('Disconnected from the socket server');
    });
    socket.onConnectError((data) => print('❌ Connect Error: $data'));
    socket.onError((data) => print('❌ General Error: $data'));
  }

  // ✅ Join room
  void registerUser(String username) {
    print('Joining room: $username');
    socket.emit('join_room', username);
  }

  // ✅ Send message
  void sendMessage(Map<String, dynamic> messageData) {
    if (socket.connected) {
      print('📤 Sending message: $messageData');
      socket.emit('send_message', messageData);
    } else {
      print('Socket is not connected');
    }
  }

  // ✅ Listen to messages (only once)
  void onMessageReceived(Function(Map<String, dynamic>) callback) {
    if (!isListenerSet) { // Only set the listener if it hasn't been set
      socket.on('receive_message', (data) {
        print('📨 Message received: $data');
        callback(Map<String, dynamic>.from(data));
      });
      isListenerSet = true; // Mark the listener as set
    }
  }

  void onMessageReceivedWithProcessing(Function(Message) callback) {
    if (!isListenerSet) { // Only set the listener if it hasn't been set
      socket.on('receive_message', (data) {
        print('📨 Message received: $data');
        final newMessage = Message(
          sender: data['sender'] ?? 'Unknown',
          receiver: data['receiver'] ?? 'Unknown',
          content: data['content'] ?? '[No Content]',
          timestamp: data['timestamp'] ?? DateTime.now().toIso8601String(),
          isGroup: data['isGroup'] ?? false,
          emojis: data['emojis'] ?? [],
          fileUrl: data['fileUrl'] ?? '',
        );
        callback(newMessage);
      });
      isListenerSet = true; // Mark the listener as set
    }
  }

  // ✅ Reset the listener (if needed)
  void resetListener() {
    isListenerSet = false; // Reset the listener flag
    socket.off('receive_message'); // Remove the listener to avoid duplication
  }

  // Dispose of the socket and reset listener
  void dispose() {
    socket.dispose();
    resetListener(); // Ensure the listener is reset on dispose
  }
}

class Message {
  final String sender;
  final String receiver;
  final String content;
  final String timestamp;
  final bool isGroup;
  final List<dynamic> emojis;
  final String fileUrl;

  Message({
    required this.sender,
    required this.receiver,
    required this.content,
    required this.timestamp,
    required this.isGroup,
    required this.emojis,
    required this.fileUrl,
  });
}
