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

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      sender: json['sender'] ?? 'Unknown', // Default to 'Unknown' if null
      receiver: json['receiver'] ?? 'Unknown', // Default to 'Unknown' if null
      content: json['content'] ?? '', // Default to an empty string if null
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(), // Default to current timestamp if null
      isGroup: json['isGroup'] ?? false, // Default to false if null
      emojis: json['emojis'] ?? [], // Default to an empty list if null
      fileUrl: json['fileUrl'] ?? '', // Default to an empty string if null
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sender': sender,
      'receiver': receiver,
      'content': content,
      'timestamp': timestamp,
      'isGroup': isGroup,
      'emojis': emojis,
      'fileUrl': fileUrl,
    };
  }
}
