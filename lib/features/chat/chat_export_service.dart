import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'chat_message.dart';

/// Exports conversations and generated media to shareable files.
class ChatExportService {
  /// Builds a PDF of [messages] and opens the share sheet.
  Future<void> shareAsPdf(List<ChatMessage> messages, String title) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(title,
                style: pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text('Exported from PintSize AI',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          pw.SizedBox(height: 16),
          ...messages.expand((m) {
            final isUser = m.isUser;
            return [
              pw.Container(
                alignment:
                    isUser ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
                margin: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: isUser ? PdfColors.blue50 : PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(isUser ? 'You' : 'AI',
                          style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey700)),
                      pw.SizedBox(height: 3),
                      pw.Text(m.content, style: const pw.TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ];
          }),
        ],
      ),
    );

    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final safe = title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    final file = File('${dir.path}/$safe.pdf');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles([XFile(file.path)], subject: title);
  }

  /// Saves [imageBytes] to a temp file and opens the share sheet.
  Future<void> shareImage(Uint8List imageBytes, {String name = 'image'}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name.png');
    await file.writeAsBytes(imageBytes);
    await Share.shareXFiles([XFile(file.path)]);
  }
}
