class Message {
  final String id; // <-- Add this
  final String sender;
  final String receiver;
  final String content;
  final String timestamp;
  final bool isGroup;
  final List<String> emojis;
  final String fileUrl;
  final String? type;
  final String? direction;
  final int? duration;
  final List<String> readBy; // Already added

  Message({
    required this.id, // <-- include in constructor
    required this.sender,
    required this.receiver,
    required this.content,
    required this.timestamp,
    required this.isGroup,
    required this.emojis,
    required this.fileUrl,
    this.type,
    this.direction,
    this.duration,
    required this.readBy,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['_id'] ?? '', // <--- Map MongoDB _id to id
      sender: json['sender'] ?? '',
      receiver: json['receiver'] ?? '',
      content: json['content'] ?? '',
      timestamp: json['timestamp'] ?? '',
      isGroup: json['isGroup'] ?? false,
      emojis: (json['emojis'] as List<dynamic>?)?.cast<String>() ?? [],
      fileUrl: json['fileUrl'] ?? '',
      type: json['type'],
      direction: json['direction'],
      duration: json['duration'] is int
          ? json['duration']
          : int.tryParse(json['duration']?.toString() ?? ''),
      readBy: (json['readBy'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}
