class Message {
  final String id;
  final String sender;
  final String receiver;
  final String content;
  final String timestamp;
  final bool isGroup;
  final List<String> emojis;
  final String fileUrl;
  final List<String> readBy;
  final String? type;
  final String? direction;
  final int? duration;
  final bool isFile;
  final bool deleted;
  final bool edited;

  Message({
    required this.id,
    required this.sender,
    required this.receiver,
    required this.content,
    required this.timestamp,
    required this.isGroup,
    required this.emojis,
    required this.fileUrl,
    required this.readBy,
    this.type,
    this.direction,
    this.duration,
    this.isFile = false,
    this.deleted = false,
    this.edited = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    String idString;

    final idValue = json['id'];
    if (idValue == null) {
      idString = '';
    } else if (idValue is String) {
      idString = idValue;
    } else {
      // Handle cases like ObjectId("...")
      final raw = idValue.toString();
      final match = RegExp(r'ObjectId\("?(.*?)"?\)').firstMatch(raw);
      idString = match != null ? match.group(1)! : raw;
    }

    return Message(
      id: idString,
      sender: json['sender'] ?? 'Unknown',
      receiver: json['receiver'] ?? 'Unknown',
      content: json['content'] ?? '',
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
      isGroup: json['isGroup'] ?? false,
      emojis: (json['emojis'] as List<dynamic>?)?.cast<String>() ?? [],
      fileUrl: json['fileUrl'] ?? '',
      readBy: (json['readBy'] as List<dynamic>?)?.cast<String>() ?? [],
      type: json['type'],
      direction: json['direction'],
      duration: json['duration'] is int
          ? json['duration']
          : int.tryParse(json['duration']?.toString() ?? ''),
      isFile: json['fileUrl'] != null && json['fileUrl'] != '',
      deleted: json['deleted'] ?? false,
      edited: json['edited'] ?? false,
    );
  }
}
