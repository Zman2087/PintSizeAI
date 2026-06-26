import 'dart:typed_data';

enum AttachmentType { image, video, file, generatedImage, generatedVideo }

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.type,
    required this.name,
    this.localPath,
    this.sizeBytes,
    this.thumbnailBytes,
    this.mimeType,
    this.width,
    this.height,
    this.durationSeconds,
    this.generationPrompt,
  });

  final String id;
  final AttachmentType type;
  final String name;
  final String? localPath;
  final int? sizeBytes;
  final Uint8List? thumbnailBytes;
  final String? mimeType;
  final int? width;
  final int? height;
  final double? durationSeconds;
  final String? generationPrompt;

  bool get isImage =>
      type == AttachmentType.image || type == AttachmentType.generatedImage;
  bool get isVideo =>
      type == AttachmentType.video || type == AttachmentType.generatedVideo;
  bool get isFile => type == AttachmentType.file;
  bool get isGenerated =>
      type == AttachmentType.generatedImage ||
      type == AttachmentType.generatedVideo;

  String get displaySize {
    if (sizeBytes == null) return '';
    if (sizeBytes! < 1024) return '${sizeBytes}B';
    if (sizeBytes! < 1024 * 1024) {
      return '${(sizeBytes! / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
