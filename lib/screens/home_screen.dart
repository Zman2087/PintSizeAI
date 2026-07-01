import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../features/attachments/attachment.dart';
import '../features/chat/chat_message.dart';
import '../features/chat/chat_providers.dart';
import '../features/device_recommender/model_catalogue.dart';
import '../features/image_gen/image_gen_providers.dart';
import '../features/image_gen/image_gen_service.dart';
import '../features/image_gen/sd_model_catalogue.dart';
import '../features/llm/llama_runner.dart';
import '../features/llm/llm_providers.dart';
import '../features/models/model_download_service.dart';
import '../features/models/model_providers.dart';
import '../features/models/custom_models_service.dart';
import '../features/settings/settings_providers.dart';
import '../features/media/media_service.dart';
import '../features/voice/voice_providers.dart';
import '../features/voice/voice_service.dart';
import '../features/web_search/web_search_service.dart';
import '../features/web_search/url_fetch_service.dart';
import '../features/web_search/stock_service.dart';
import '../features/documents/document_retrieval_service.dart';
import '../features/diagnostics/diag_log.dart';
import '../widgets/stock_chart_card.dart';
import '../theme/app_widgets.dart';
import '../theme/theme.dart';
import 'history_drawer.dart';
import 'image_gen_screen.dart';
import 'models_screen.dart';
import 'settings_screen.dart';
import 'voice_mode_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Slash commands
// ─────────────────────────────────────────────────────────────────────────────

class _Cmd {
  const _Cmd({
    required this.name,
    required this.description,
    required this.icon,
    this.argHint,
    this.color,
  });
  final String name;
  final String description;
  final IconData icon;
  final String? argHint;
  final Color? color;
}

const _kCommands = [
  _Cmd(
    name: 'image',
    description: 'Generate an image locally',
    icon: Icons.auto_awesome_outlined,
    argHint: '<prompt>',
    color: AppColors.accentGreen,
  ),
  _Cmd(
    name: 'video',
    description: 'Generate a short video locally',
    icon: Icons.smart_display_outlined,
    argHint: '<prompt>',
    color: Color(0xFFEF5350),
  ),
  _Cmd(
    name: 'new',
    description: 'Start a new chat',
    icon: Icons.add_circle_outline,
    color: Color(0xFF4FC3F7),
  ),
  _Cmd(
    name: 'model',
    description: 'Switch AI model',
    icon: Icons.memory_outlined,
    color: Color(0xFFFFB74D),
  ),
  _Cmd(
    name: 'clear',
    description: 'Clear current chat history',
    icon: Icons.delete_sweep_outlined,
    color: Color(0xFFE57373),
  ),
  _Cmd(
    name: 'help',
    description: 'Show all available commands',
    icon: Icons.help_outline,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _imagePicker = ImagePicker();
  final List<ChatAttachment> _pendingAttachments = [];
  List<_Cmd> _commandSuggestions = [];
  bool _webSearchEnabled = false;
  bool _isListening = false;
  StreamSubscription<VoiceEvent>? _voiceSub;
  final _webSearch = WebSearchService();
  final _urlFetch = UrlFetchService();
  final _docRetrieval = DocumentRetrievalService();
  final _stock = StockService();
  final _media = MediaService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoLoad());
    _inputCtrl.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    final text = _inputCtrl.text;
    if (text.startsWith('/')) {
      final query = text.substring(1).toLowerCase().split(' ').first;
      final matches = _kCommands.where((c) => c.name.startsWith(query)).toList();
      setState(() => _commandSuggestions = matches);
    } else if (_commandSuggestions.isNotEmpty) {
      setState(() => _commandSuggestions = []);
    }
  }

  Future<void> _autoLoad() async {
    final lastId = await ref.read(settingsServiceProvider).getLastModelId();
    if (lastId == null || !mounted) return;

    // Look in both the built-in catalogue and user-imported (HF) models.
    var model = kModelCatalogue.where((m) => m.id == lastId).firstOrNull;
    model ??= ref.read(customModelsProvider).where((m) => m.id == lastId).firstOrNull;
    if (model == null) return;

    final storage = ref.read(modelStorageProvider);
    if (!await storage.isDownloaded(lastId)) return;

    if (mounted && ref.read(activeModelProvider) == null) {
      ref.read(modelActionsProvider).loadModel(model);
    }
  }

  @override
  @override
  void dispose() {
    _voiceSub?.cancel();
    _inputCtrl.removeListener(_onInputChanged);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _selectCommand(_Cmd cmd) {
    // Fill the input with the command, ready for an argument if needed
    final text = cmd.argHint != null ? '/${cmd.name} ' : '/${cmd.name}';
    _inputCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    // If no argument needed, execute immediately
    if (cmd.argHint == null) {
      _send();
    }
  }

  void _send() {
    final text = _inputCtrl.text.trim();
    final attachments = List<ChatAttachment>.from(_pendingAttachments);
    if (text.isEmpty && attachments.isEmpty) return;
    HapticFeedback.lightImpact();
    _inputCtrl.clear();
    setState(() {
      _pendingAttachments.clear();
      _commandSuggestions = [];
    });

    // ── Slash commands ────────────────────────────────────────────────────────
    if (text.startsWith('/')) {
      final parts = text.substring(1).split(RegExp(r'\s+'));
      final cmd = parts.first.toLowerCase();
      final arg = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';

      switch (cmd) {
        case 'image':
          if (arg.isEmpty) {
            _showImageGenDialog(originalText: text);
          } else {
            _generateImage(prompt: arg, userText: text);
          }
          return;

        case 'video':
          if (arg.isEmpty) {
            _showVideoGenDialog(originalText: text);
          } else {
            _generateImage(prompt: arg, userText: text, isVideo: true);
          }
          return;

        case 'new':
          ref.read(chatControllerProvider.notifier).newChat();
          return;

        case 'model':
          ModelsScreen.open(context);
          return;

        case 'clear':
          ref.read(chatControllerProvider.notifier).newChat();
          return;

        case 'help':
          _showHelpMessage();
          return;

        default:
          // Unknown command — fall through and send as plain text
          break;
      }
    }

    // ── Natural language intent detection ────────────────────────────────────
    if (_isImageGenIntent(text)) {
      _generateImage(
          prompt: _extractGenPrompt(text, _imageGenTriggers), userText: text);
      return;
    }
    if (_isVideoGenIntent(text)) {
      _generateImage(
          prompt: _extractGenPrompt(text, _videoGenTriggers),
          userText: text,
          isVideo: true);
      return;
    }

    _sendEnriched(text, attachments: attachments);
    _scrollToBottom();
  }

  Future<void> _sendEnriched(String text,
      {List<ChatAttachment> attachments = const []}) async {
    // img2img auto-detect: if message sounds like an image edit + image attached
    final hasImage = attachments.any((a) => a.isImage);
    if (hasImage && _isImageEditRequest(text)) {
      final imgAtt = attachments.firstWhere((a) => a.isImage);
      if (imgAtt.thumbnailBytes != null) {
        _generateImg2Img(imgAtt.thumbnailBytes!, text);
        return;
      }
    }

    // Real multimodal vision: if a vision-capable model is loaded and an image
    // is attached, hand the raw image straight to the model instead of relying
    // on the Vision-framework OCR/scene description.
    final runner = ref.read(llamaRunnerProvider);
    if (hasImage && runner.hasVision) {
      final imgAtt = attachments.firstWhere((a) => a.isImage);
      if (imgAtt.thumbnailBytes != null) {
        ref.read(chatControllerProvider.notifier).send(
              text,
              attachments: attachments,
              imageBytes: imgAtt.thumbnailBytes,
            );
        return;
      }
    }

    // Live stock lookup: if the message looks like a price question, fetch a
    // real quote and show a price + chart card.
    if (StockService.looksLikeStockQuery(text)) {
      _showSnack('Fetching live market data…');
      final quote = await _stock.lookup(text);
      DiagLog.log('stock query="$text" → ${quote == null ? "NO QUOTE" : "${quote.symbol} ${quote.price}"}');
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (quote != null) {
        ref.read(chatControllerProvider.notifier).addUserMessage(text);
        final card =
            '${StockChartCard.startMarker}${jsonEncode(quote.toJson())}${StockChartCard.endMarker}';
        ref
            .read(chatControllerProvider.notifier)
            .replyWithText('$card\n\n${quote.summary}');
        _scrollToBottom();
        return;
      }
    }

    // URL fetch: if message contains a bare URL, fetch and inject its content
    String enriched = text;
    final url = UrlFetchService.extractUrl(text);
    if (url != null) {
      _showSnack('Fetching page content…');
      final pageText = await _urlFetch.fetch(url);
      if (pageText != null) {
        enriched = '[Page content from $url]\n$pageText\n\nUser: $text';
      }
    }

    // Enrich with Vision analysis / PDF text
    enriched = await _enrichWithMedia(enriched, attachments);

    // Optionally also add web search context
    if (_webSearchEnabled) {
      _showSnack('Searching the web…');
      final webCtx = await _webSearch.search(text);
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (webCtx != null) {
        enriched = '$webCtx\n\n$enriched';
      } else {
        _showSnack('No web results found');
      }
    }

    final displayText = enriched == text ? null : text;
    ref
        .read(chatControllerProvider.notifier)
        .send(enriched, displayText: displayText, attachments: attachments);
  }

  static bool _isImageEditRequest(String text) {
    final lower = text.toLowerCase();
    const editKeywords = [
      'make', 'change', 'turn', 'remove', 'replace', 'swap',
      'edit', 'modify', 'adjust', 'convert', 'transform',
      'white', 'black', 'red', 'blue', 'green', 'yellow',
      'background', 'color', 'colour', 'shirt', 'hair', 'sky',
    ];
    return editKeywords.any(lower.contains);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// Shows the downloaded models so the user can re-answer the last prompt
  /// with a different model.
  Future<void> _showRegenerateModelChooser() async {
    final storage = ref.read(modelStorageProvider);
    final active = ref.read(activeModelProvider);
    final downloaded = <ModelVariant>[];
    for (final m in kModelCatalogue) {
      if (await storage.isDownloaded(m.id)) downloaded.add(m);
    }
    if (!mounted) return;
    if (downloaded.isEmpty) {
      _showSnack('No downloaded models. Install one from the model picker.');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceSidebar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Re-answer with…',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            for (final m in downloaded)
              ListTile(
                leading: Icon(_iconData(m.family),
                    color: _iconColor(m.family), size: 22),
                title: Text(m.displayName,
                    style: TextStyle(color: AppColors.textPrimary)),
                subtitle: Text(
                    '${m.parametersBillions}B · ${m.quant.label}',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                trailing: m.id == active?.id
                    ? const Icon(Icons.check, color: AppColors.accentGreen, size: 18)
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  ref.read(chatControllerProvider.notifier).regenerateWithModel(m);
                  _scrollToBottom();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Color _iconColor(ModelFamily f) => switch (f) {
        ModelFamily.llama => AppColors.modelWhite,
        ModelFamily.phi => AppColors.modelBlue,
        ModelFamily.gemma => AppColors.modelGreen,
        ModelFamily.mistral => AppColors.modelPurple,
        ModelFamily.qwen => AppColors.modelPurple,
        ModelFamily.deepseek => AppColors.modelBlue,
        ModelFamily.smollm => AppColors.modelSurface,
      };

  IconData _iconData(ModelFamily f) => switch (f) {
        ModelFamily.llama => Icons.memory,
        ModelFamily.phi => Icons.hexagon_outlined,
        ModelFamily.gemma => Icons.diamond_outlined,
        ModelFamily.mistral => Icons.bolt,
        ModelFamily.qwen => Icons.waves,
        ModelFamily.deepseek => Icons.psychology_outlined,
        ModelFamily.smollm => Icons.bubble_chart_outlined,
      };

  Future<void> _generateImg2Img(Uint8List sourceBytes, String prompt) async {
    await _ensureSdModelLoaded();
    final sdService = ref.read(imageGenProvider);
    _showSnack('Generating edited image…');
    try {
      final result = await sdService.editImage(
        imageBytes: sourceBytes,
        prompt: prompt,
        strength: 0.7,
      );
      if (result != null && mounted) {
        ref.read(chatControllerProvider.notifier).send(
          prompt,
          attachments: [
            ChatAttachment(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              type: AttachmentType.image,
              name: 'edited_image.png',
              thumbnailBytes: result,
            ),
          ],
        );
      }
    } catch (e) {
      _showSnack('Image edit failed: $e');
    }
  }

  /// Builds an enriched message text by prepending Vision analysis and PDF
  /// text for any attached images/PDFs so the LLM has visual context.
  Future<String> _enrichWithMedia(
      String text, List<ChatAttachment> attachments) async {
    final extra = StringBuffer();

    for (final att in attachments) {
      if (att.isImage && att.thumbnailBytes != null) {
        final desc = await _media.analyzeImage(att.thumbnailBytes!);
        if (desc != null) extra.writeln(desc);
      }
      if (att.isFile && att.generationPrompt != null) {
        // For long documents, retrieve only the passages relevant to the
        // question instead of dumping the whole thing into the context window.
        final docText = att.generationPrompt!;
        final relevant = text.trim().isEmpty
            ? docText
            : _docRetrieval.relevantContext(docText, text);
        extra.writeln('[Document: ${att.name}]\n$relevant');
      }
    }

    if (extra.isEmpty) return text;
    return '${extra.toString().trim()}\n\nUser: $text';
  }

  void _showHelpMessage() {
    ref.read(chatControllerProvider.notifier).addUserMessage('/help');
    final lines = StringBuffer('Here are the available slash commands:\n\n');
    for (final c in _kCommands) {
      final usage = c.argHint != null ? '/${c.name} ${c.argHint}' : '/${c.name}';
      lines.writeln('$usage — ${c.description}');
    }
    lines.write('\nYou can also speak naturally — try "make an image of a sunset" or "draw a cat".');
    ref.read(chatControllerProvider.notifier).replyWithText(lines.toString());
    _scrollToBottom();
  }

  // ── Generation intent detection ─────────────────────────────────────────────

  static const _imageGenTriggers = [
    // Explicit requests with "of"
    'make an image of', 'generate an image of', 'create an image of',
    'make me an image of', 'show me an image of', 'give me an image of',
    'make a picture of', 'generate a picture of', 'create a picture of',
    'make a photo of', 'generate a photo of', 'create a photo of',
    'make an illustration of', 'generate an illustration of',
    // Without "of"
    'make an image', 'generate an image', 'create an image', 'make me an image',
    'make a picture', 'generate a picture', 'create a picture',
    // Draw / paint
    'draw me ', 'draw a ', 'draw an ', 'draw me a ', 'draw me an ',
    'paint me ', 'paint a ', 'paint an ', 'paint me a ', 'paint me an ',
    // Imagine
    '/imagine ', 'imagine ',
    // Photo
    'take a photo of', 'show a photo of',
    // Loose "image" phrases
    'image of ', 'picture of ', 'photo of ',
    'create image', 'generate image', 'make image',
  ];

  static const _videoGenTriggers = [
    'make a video of', 'generate a video of', 'create a video of',
    'make me a video of', 'show me a video of', 'give me a video of',
    'make a video', 'generate a video', 'create a video', 'make me a video',
    'animate ', 'create an animation of', 'make an animation of',
    'create an animation', 'make an animation',
    'video of ',
  ];

  // ── Image gen availability guard ─────────────────────────────────────────


  bool _isImageGenIntent(String text) {
    final lower = text.toLowerCase();
    return _imageGenTriggers.any((t) => lower.contains(t));
  }

  bool _isVideoGenIntent(String text) {
    final lower = text.toLowerCase();
    return _videoGenTriggers.any((t) => lower.contains(t));
  }

  String _extractGenPrompt(String text, List<String> triggers) {
    final lower = text.toLowerCase();
    // Sort longest trigger first so more specific ones match before shorter ones
    final sorted = [...triggers]..sort((a, b) => b.length.compareTo(a.length));
    for (final trigger in sorted) {
      if (lower.contains(trigger)) {
        final idx = lower.indexOf(trigger) + trigger.length;
        final extracted = text.substring(idx).trim();
        if (extracted.isNotEmpty) return extracted;
      }
    }
    return text; // fallback: use the full message as the prompt
  }

  void _stop() {
    ref.read(chatControllerProvider.notifier).stopGeneration();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showAttachmentPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AttachmentPickerSheet(
        onPickPhoto: () {
          Navigator.pop(context);
          _pickImage(ImageSource.gallery);
        },
        onTakePhoto: () {
          Navigator.pop(context);
          _pickImage(ImageSource.camera);
        },
        onPickVideo: () {
          Navigator.pop(context);
          _pickVideo();
        },
        onPickFile: () {
          Navigator.pop(context);
          _pickFile();
        },
        onGenerateImage: () {
          Navigator.pop(context);
          _showImageGenDialog();
        },
        onGenerateVideo: () {
          Navigator.pop(context);
          _showVideoGenDialog();
        },
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        // Multi-select from gallery
        final files = await _imagePicker.pickMultiImage(
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );
        if (files.isEmpty) return;
        final attachments = await Future.wait(files.map((file) async {
          final bytes = await file.readAsBytes();
          return ChatAttachment(
            id: '${DateTime.now().microsecondsSinceEpoch}_${file.name}',
            type: AttachmentType.image,
            name: file.name,
            localPath: file.path,
            thumbnailBytes: bytes,
            sizeBytes: bytes.length,
            mimeType: 'image/jpeg',
          );
        }));
        setState(() => _pendingAttachments.addAll(attachments));
      } else {
        // Camera — single shot
        final file = await _imagePicker.pickImage(
          source: source,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );
        if (file == null) return;
        final bytes = await file.readAsBytes();
        setState(() {
          _pendingAttachments.add(ChatAttachment(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            type: AttachmentType.image,
            name: file.name,
            localPath: file.path,
            thumbnailBytes: bytes,
            sizeBytes: bytes.length,
            mimeType: 'image/jpeg',
          ));
        });
      }
    } catch (e) {
      _showError('Could not pick image: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (file == null) return;
      final stat = await File(file.path).stat();
      setState(() {
        _pendingAttachments.add(ChatAttachment(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: AttachmentType.video,
          name: file.name,
          localPath: file.path,
          sizeBytes: stat.size,
          mimeType: 'video/mp4',
        ));
      });
    } catch (e) {
      _showError('Could not pick video: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
        withData: false,
        withReadStream: false,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      final ext = (f.extension ?? '').toLowerCase();

      const textExts = {'pdf', 'txt', 'csv', 'tsv', 'md', 'json', 'rtf', 'docx', 'doc', 'html', 'htm'};
      const audioExts = {'m4a', 'mp3', 'wav', 'caf', 'aac', 'aif', 'aiff'};
      String? extractedText;

      if (textExts.contains(ext) && f.path != null) {
        try {
          extractedText = ext == 'pdf'
              ? await _media.extractPDF(f.path!)
              : await _media.extractText(f.path!);

          if (extractedText != null) {
            HapticFeedback.lightImpact();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${ext.toUpperCase()} text extracted (${(extractedText.length / 1000).toStringAsFixed(0)}k chars)'),
                duration: const Duration(seconds: 2),
              ));
            }
            _inputCtrl.text = '[${ext.toUpperCase()}: ${f.name}]\n';
          }
        } catch (_) {}
      } else if (audioExts.contains(ext) && f.path != null) {
        // Transcribe audio file
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Transcribing audio…'),
            duration: Duration(seconds: 30),
          ));
        }
        try {
          final transcript = await _media.transcribeAudio(f.path!);
          if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
          if (transcript != null) {
            HapticFeedback.lightImpact();
            extractedText = transcript;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Audio transcribed (${transcript.split(' ').length} words)'),
                duration: const Duration(seconds: 2),
              ));
            }
            _inputCtrl.text = transcript;
            _send();
            return;
          }
        } catch (_) {
          if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
      }

      setState(() {
        _pendingAttachments.add(ChatAttachment(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: AttachmentType.file,
          name: f.name,
          localPath: f.path,
          sizeBytes: f.size,
          mimeType: audioExts.contains(ext) ? 'audio/$ext' : (ext == 'pdf' ? 'application/pdf' : 'application/$ext'),
          generationPrompt: extractedText,
        ));
      });
    } catch (e) {
      _showError('Could not pick file: $e');
    }
  }

  void _showImageGenDialog({String originalText = '/image'}) {
    final ctrl = TextEditingController();
    var variations = false;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surfaceOverlay,
          title: Text('Generate Image',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: AppTypography.messageBody,
                decoration: InputDecoration(
                  hintText: 'Describe what to generate…',
                  hintStyle: AppTypography.placeholder,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.borderDefault),
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: variations,
                    activeColor: AppColors.accentGreen,
                    onChanged: (v) =>
                        setDlgState(() => variations = v ?? false),
                  ),
                  Text('Generate 4 variations',
                      style: TextStyle(color: AppColors.textMuted,
                          fontSize: 13)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final prompt = ctrl.text.trim();
                if (prompt.isEmpty) return;
                Navigator.pop(context);
                if (variations) {
                  _generateVariations(prompt: prompt);
                } else {
                  _generateImage(prompt: prompt, userText: '/image $prompt');
                }
              },
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateVariations({required String prompt}) async {
    ref.read(chatControllerProvider.notifier).addUserMessage(
        '/image $prompt (×4 variations)');
    _scrollToBottom();

    await _ensureSdModelLoaded();
    final gen = ref.read(imageGenProvider);
    final results = <Uint8List>[];

    ref.read(imageGenStatusProvider.notifier).state = ImageGenStatus.generating;
    ref.read(imageGenProgressProvider.notifier).state = 0.0;

    for (var i = 0; i < 4; i++) {
      try {
        final result = await gen.generate(prompt);
        results.add(result.imageBytes);
      } catch (_) {}
      if (mounted) {
        ref.read(imageGenProgressProvider.notifier).state = (i + 1) / 4;
      }
    }

    if (!mounted) return;
    ref.read(imageGenStatusProvider.notifier).state = ImageGenStatus.done;

    if (results.isEmpty) {
      _showError('All variations failed to generate');
      return;
    }

    // Show pick grid
    _showVariationPicker(prompt, results);
  }

  void _showVariationPicker(String prompt, List<Uint8List> images) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceSidebar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Pick a variation',
                  style: AppTypography.modelName.copyWith(fontSize: 15)),
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: images.asMap().entries.map((e) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    HapticFeedback.lightImpact();
                    final attachment = ChatAttachment(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      type: AttachmentType.generatedImage,
                      name: 'variation_${e.key + 1}.png',
                      thumbnailBytes: e.value,
                      sizeBytes: e.value.length,
                      generationPrompt: prompt,
                    );
                    ref.read(chatControllerProvider.notifier)
                        .sendGeneratedAttachment(
                          caption: '',
                          attachment: attachment,
                        );
                    _scrollToBottom();
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(e.value, fit: BoxFit.cover),
                        Positioned(
                          bottom: 4, right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('${e.key + 1}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showVideoGenDialog({String originalText = '/video'}) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceOverlay,
        title: Text('Generate Video',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              style: AppTypography.messageBody,
              decoration: InputDecoration(
                hintText: 'Describe the video to generate…',
                hintStyle: AppTypography.placeholder,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.borderDefault),
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            Text(
              'Generates 4 frames as animated APNG on-device. '
              'Requires iPhone 15 Pro or newer for best speed.',
              style: AppTypography.userMeta,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final prompt = ctrl.text.trim();
              if (prompt.isEmpty) return;
              Navigator.pop(context);
              _generateImage(
                  prompt: prompt,
                  userText: '/video $prompt',
                  isVideo: true);
            },
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  /// Ensures a downloaded Core ML image model is loaded into memory. If the
  /// model is downloaded but not yet loaded, it is loaded automatically so the
  /// user never has to do it manually. Returns true if a real model is ready.
  Future<bool> _ensureSdModelLoaded() async {
    final status = ref.read(sdModelProvider);
    if (status.state == SDModelState.loaded) return true;
    if (status.state == SDModelState.ready && status.loadedModelId != null) {
      SDModel? model;
      for (final m in kSDModelCatalogue) {
        if (m.id == status.loadedModelId) {
          model = m;
          break;
        }
      }
      if (model == null) return false;
      if (mounted) _showSnack('Loading image model…');
      await ref.read(sdModelProvider.notifier).loadModel(model);
      return ref.read(sdModelProvider).state == SDModelState.loaded;
    }
    return false;
  }

  Future<void> _generateImage({
    required String prompt,
    required String userText,
    bool isVideo = false,
  }) async {
    // Show exactly what the user typed
    ref.read(chatControllerProvider.notifier).addUserMessage(userText);
    _scrollToBottom();

    // Auto-load a downloaded Core ML model so generation "just works".
    final isReal = await _ensureSdModelLoaded();

    // If no real SD model installed, show a one-time nudge but still generate
    if (!isReal && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Preview — go to Settings › Image Generation to install a real model'),
            action: SnackBarAction(
              label: 'Install',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ImageGenScreen()),
              ),
            ),
            duration: const Duration(seconds: 4),
            backgroundColor: const Color(0xFF1E3A5F),
          ),
        );
    }

    final gen = ref.read(imageGenProvider);
    try {
      ref.read(imageGenStatusProvider.notifier).state =
          ImageGenStatus.generating;
      ref.read(imageGenProgressProvider.notifier).state = 0.0;

      gen.progressStream.listen((p) {
        if (mounted) {
          ref.read(imageGenProgressProvider.notifier).state = p;
        }
      });

      final result = isVideo && isReal
          ? await (gen as dynamic).generate(prompt, steps: 15, frameCount: 4)
          : await gen.generate(prompt);

      if (mounted) {
        ref.read(imageGenStatusProvider.notifier).state = ImageGenStatus.done;
        final attachment = ChatAttachment(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: isVideo
              ? AttachmentType.generatedVideo
              : AttachmentType.generatedImage,
          name: isVideo ? 'generated_video.apng' : 'generated_image.png',
          thumbnailBytes: result.imageBytes,
          sizeBytes: result.imageBytes.length,
          generationPrompt: prompt,
          width: result.width,
          height: result.height,
        );
        // Empty caption — the image speaks for itself
        ref.read(chatControllerProvider.notifier).sendGeneratedAttachment(
          caption: isReal ? '' : 'Preview — install a model for real AI generation',
          attachment: attachment,
        );
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ref.read(imageGenStatusProvider.notifier).state = ImageGenStatus.error;
        _showError('Generation failed: $e');
      }
    }
  }

  // ── Voice input ─────────────────────────────────────────────────────────────

  void _toggleVoice() {
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  void _startListening() {
    final svc = ref.read(voiceServiceProvider);
    setState(() {
      _isListening = true;
      _inputCtrl.clear();
    });

    svc.startListening();

    _voiceSub?.cancel();
    _voiceSub = svc.events.listen(
      (evt) {
        if (evt is VoiceTranscriptEvent) {
          _inputCtrl.text = evt.text;
          _inputCtrl.selection = TextSelection.collapsed(
              offset: _inputCtrl.text.length);
          if (evt.isFinal) {
            _stopListening();
            if (evt.text.trim().isNotEmpty) _send();
          }
        } else if (evt is VoiceListeningStoppedEvent) {
          setState(() => _isListening = false);
        }
      },
      onError: (_) => setState(() => _isListening = false),
      onDone: () => setState(() => _isListening = false),
    );
  }

  void _stopListening() {
    _voiceSub?.cancel();
    _voiceSub = null;
    setState(() => _isListening = false);
    ref.read(voiceServiceProvider).stopListening();
  }

  // ── Message editing ──────────────────────────────────────────────────────────

  void _showEditDialog(String messageId, String currentText) {
    HapticFeedback.mediumImpact();
    final ctrl = TextEditingController(text: currentText);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceSidebar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit message',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: null,
              style: AppTypography.messageBody,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceBase,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderDefault),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderDefault),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.accentGreen),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final newText = ctrl.text.trim();
                if (newText.isEmpty) return;
                Navigator.pop(ctx);
                HapticFeedback.lightImpact();
                ref
                    .read(chatControllerProvider.notifier)
                    .editAndRegenerate(messageId, newText);
              },
              child: const Text('Resend'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Background removal ───────────────────────────────────────────────────────

  Future<void> _removeBackground(int attachmentIndex) async {
    final attachment = _pendingAttachments[attachmentIndex];
    if (attachment.thumbnailBytes == null) return;

    try {
      final result = await _media.removeBackground(attachment.thumbnailBytes!);
      setState(() {
        _pendingAttachments[attachmentIndex] = ChatAttachment(
          id: attachment.id,
          type: attachment.type,
          name: '${attachment.name} (no bg)',
          localPath: attachment.localPath,
          thumbnailBytes: result,
          sizeBytes: result.length,
          mimeType: 'image/png',
        );
      });
    } catch (e) {
      _showError('Background removal failed: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF7F1D1D),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider);
    final isGenerating = ref.watch(isGeneratingProvider);
    final activeModel = ref.watch(activeModelProvider);
    final llamaStatus = ref.watch(llamaStatusProvider);
    final error = ref.watch(chatErrorProvider);
    final genStatus = ref.watch(imageGenStatusProvider);
    final genProgress = ref.watch(imageGenProgressProvider);
    final downloads = ref.watch(downloadStatesProvider);

    ref.listen(messagesProvider, (_, __) => _scrollToBottom());

    final modelLoaded = llamaStatus == LlamaStatus.ready ||
        llamaStatus == LlamaStatus.generating;

    // Check if the starter model is being auto-downloaded
    final starterDl = downloads[kStarterModelId];
    final isAutoDownloading = starterDl != null &&
        (starterDl.status == DownloadStatus.downloading ||
         llamaStatus == LlamaStatus.loading && activeModel == null);

    final isIPad = MediaQuery.sizeOf(context).shortestSide >= 600;

    final chatBody = Column(
      children: [
        const _PrivacyBar(),
        const _ModelStatusBanner(),
        if (error != null) _ErrorBar(error: error),
        Expanded(
          child: messages.isEmpty && !modelLoaded
              ? isAutoDownloading
                  ? _AutoDownloadView(
                      progress: starterDl.progress,
                      isLoading: llamaStatus == LlamaStatus.loading,
                      receivedMb: starterDl.receivedBytes / 1e6,
                      totalMb: (starterDl.totalBytes == 0 ? 1 : starterDl.totalBytes) / 1e6,
                    )
                  : _WelcomeView(onModelTap: () => ModelsScreen.open(context))
              : _MessageList(
                  messages: messages,
                  activeModel: activeModel,
                  scrollCtrl: _scrollCtrl,
                  genStatus: genStatus,
                  genProgress: genProgress,
                  onEditMessage: _showEditDialog,
                  onRegenerateWithModel: _showRegenerateModelChooser,
                ),
        ),
        if (ref.watch(contextUsageProvider) > 0.85)
          _ContextWarningBar(usage: ref.watch(contextUsageProvider)),
        if (_commandSuggestions.isNotEmpty)
          _CommandSuggestionBar(
            suggestions: _commandSuggestions,
            onSelect: _selectCommand,
          ),
        _ChatInput(
          controller: _inputCtrl,
          isGenerating: isGenerating,
          modelLoaded: modelLoaded,
          pendingAttachments: _pendingAttachments,
          onSend: _send,
          onStop: _stop,
          onAddTap: _showAttachmentPicker,
          webSearchEnabled: _webSearchEnabled,
          onToggleWebSearch: () =>
              setState(() => _webSearchEnabled = !_webSearchEnabled),
          isListening: _isListening,
          onToggleVoice: _toggleVoice,
          onRemoveAttachment: (i) =>
              setState(() => _pendingAttachments.removeAt(i)),
          onRemoveBackgroundTap: _pendingAttachments.any((a) => a.isImage)
              ? () {
                  final idx = _pendingAttachments.indexWhere((a) => a.isImage);
                  if (idx >= 0) _removeBackground(idx);
                }
              : null,
        ),
      ],
    );

    if (isIPad) {
      // iPad: side-by-side history panel + chat
      return Scaffold(
        backgroundColor: AppColors.surfaceBase,
        appBar: _AppBar(
          activeModel: activeModel,
          llamaStatus: llamaStatus,
          showMenuButton: false,
          onModelTap: () => ModelsScreen.open(context),
          onSettingsTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
          onVoiceModeTap: () => VoiceModeScreen.open(context),
          onNewChat: () =>
              ref.read(chatControllerProvider.notifier).newChat(),
        ),
        body: Row(
          children: [
            SizedBox(
              width: 280,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceSidebar,
                  border: Border(right: BorderSide(color: AppColors.borderDefault)),
                ),
                child: const HistoryDrawer(embedded: true),
              ),
            ),
            Expanded(child: chatBody),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      drawer: const HistoryDrawer(),
      appBar: _AppBar(
        activeModel: activeModel,
        llamaStatus: llamaStatus,
        onModelTap: () => ModelsScreen.open(context),
        onSettingsTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
        onVoiceModeTap: () => VoiceModeScreen.open(context),
        onNewChat: () =>
            ref.read(chatControllerProvider.notifier).newChat(),
      ),
      body: chatBody,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppBar
// ─────────────────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppBar({
    required this.activeModel,
    required this.llamaStatus,
    required this.onModelTap,
    required this.onSettingsTap,
    required this.onVoiceModeTap,
    required this.onNewChat,
    this.showMenuButton = true,
  });

  final ModelVariant? activeModel;
  final LlamaStatus llamaStatus;
  final VoidCallback onModelTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onVoiceModeTap;
  final VoidCallback onNewChat;
  final bool showMenuButton;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 0,
      leading: showMenuButton
          ? Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu, size: 20),
                onPressed: () => Scaffold.of(context).openDrawer(),
                tooltip: 'History',
              ),
            )
          : null,
      title: GestureDetector(
        onTap: onModelTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (llamaStatus == LlamaStatus.loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              ModelIcon(
                color: _iconColor(activeModel?.family),
                icon: _iconData(activeModel?.family),
                size: 24,
              ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                activeModel?.displayName ?? 'Choose model',
                style: AppTypography.navTitle,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.expand_more, size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.record_voice_over_outlined, size: 20),
          tooltip: 'Voice conversation',
          onPressed: onVoiceModeTap,
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          tooltip: 'New chat',
          onPressed: onNewChat,
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 20),
          tooltip: 'Settings',
          onPressed: onSettingsTap,
        ),
      ],
    );
  }

  Color _iconColor(ModelFamily? f) => switch (f) {
        ModelFamily.llama => AppColors.modelWhite,
        ModelFamily.phi => AppColors.modelBlue,
        ModelFamily.gemma => AppColors.modelGreen,
        ModelFamily.mistral => AppColors.modelPurple,
        ModelFamily.qwen => AppColors.modelPurple,
        ModelFamily.deepseek => AppColors.modelBlue,
        ModelFamily.smollm => AppColors.modelSurface,
        null => AppColors.modelSurface,
      };

  IconData _iconData(ModelFamily? f) => switch (f) {
        ModelFamily.llama => Icons.memory,
        ModelFamily.phi => Icons.hexagon_outlined,
        ModelFamily.gemma => Icons.diamond_outlined,
        ModelFamily.mistral => Icons.bolt,
        ModelFamily.qwen => Icons.waves,
        ModelFamily.deepseek => Icons.psychology_outlined,
        ModelFamily.smollm => Icons.bubble_chart_outlined,
        null => Icons.memory_outlined,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Privacy bar
// ─────────────────────────────────────────────────────────────────────────────

class _PrivacyBar extends StatelessWidget {
  const _PrivacyBar();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Center(child: OnDeviceChip()),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error bar
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBar extends ConsumerWidget {
  const _ErrorBar({required this.error});
  final String error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3B0F0F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF7F1D1D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Color(0xFFFCA5A5)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(error,
                style: AppTypography.modelDesc
                    .copyWith(color: const Color(0xFFFCA5A5))),
          ),
          GestureDetector(
            onTap: () =>
                ref.read(chatControllerProvider.notifier).clearError(),
            child: const Icon(Icons.close, size: 16, color: Color(0xFFFCA5A5)),
          ),
        ],
      ),
    );
  }
}

/// Thin banner shown while a model is downloading or loading into memory, so
/// the user always knows why a reply is delayed.
class _ModelStatusBanner extends ConsumerWidget {
  const _ModelStatusBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadStatesProvider);
    final llamaStatus = ref.watch(llamaStatusProvider);

    // Find an in-progress download, if any.
    MapEntry<String, DownloadState>? active;
    for (final e in downloads.entries) {
      if (e.value.status == DownloadStatus.downloading) {
        active = e;
        break;
      }
    }

    String? label;
    double? progress;
    if (active != null) {
      String? modelName;
      for (final m in kModelCatalogue) {
        if (m.id == active.key) { modelName = m.displayName; break; }
      }
      final pct = (active.value.progress * 100).toStringAsFixed(0);
      label = 'Downloading ${modelName ?? 'model'}…  $pct%';
      progress = active.value.progress;
    } else if (llamaStatus == LlamaStatus.loading) {
      label = 'Loading model into memory…';
    }

    if (label == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppColors.accentGreen),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: AppTypography.userMeta
                    .copyWith(color: AppColors.textMuted)),
          ),
          if (progress != null && progress > 0)
            SizedBox(
              width: 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: AppColors.surfaceActive,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.accentGreen),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ContextWarningBar extends StatelessWidget {
  const _ContextWarningBar({required this.usage});
  final double usage;

  @override
  Widget build(BuildContext context) {
    final pct = (usage * 100).clamp(0, 999).toStringAsFixed(0);
    final over = usage >= 1.0;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2E0B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF8A6D1B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_toggle_off,
              size: 15, color: Color(0xFFFCD34D)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              over
                  ? 'Conversation exceeds the model\'s memory ($pct%). Oldest messages are being dropped — start a new chat for best results.'
                  : 'Approaching the model\'s memory limit ($pct%). Older messages may soon be forgotten.',
              style: AppTypography.userMeta
                  .copyWith(color: const Color(0xFFFCD34D)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auto-download progress view
// ─────────────────────────────────────────────────────────────────────────────

class _AutoDownloadView extends StatelessWidget {
  const _AutoDownloadView({
    required this.progress,
    required this.isLoading,
    required this.receivedMb,
    required this.totalMb,
  });

  final double progress;
  final bool isLoading;
  final double receivedMb;
  final double totalMb;

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).toInt();
    final label = isLoading
        ? 'Loading model into memory…'
        : totalMb > 0
            ? 'Downloading SmolLM2 135M… ${receivedMb.toStringAsFixed(0)} / ${totalMb.toStringAsFixed(0)} MB  ($pct%)'
            : 'Downloading SmolLM2 135M…';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bubble_chart_outlined,
                size: 48, color: AppColors.accentGreen),
            const SizedBox(height: 20),
            Text(
              'Setting up your first model',
              style: AppTypography.sheetTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'SmolLM2 135M — fast, private, runs entirely on your device',
              style: AppTypography.modelDesc,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: isLoading ? null : (progress > 0 ? progress : null),
                minHeight: 4,
                backgroundColor: AppColors.surfaceActive,
                valueColor: const AlwaysStoppedAnimation(AppColors.accentGreen),
              ),
            ),
            const SizedBox(height: 12),
            Text(label, style: AppTypography.userMeta),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Welcome / empty state
// ─────────────────────────────────────────────────────────────────────────────

class _WelcomeView extends StatelessWidget {
  const _WelcomeView({required this.onModelTap});
  final VoidCallback onModelTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.memory,
                color: AppColors.surfaceSidebar, size: 30),
          ),
          const SizedBox(height: 20),
          Text('PintSizeAi', style: AppTypography.wordmark),
          const SizedBox(height: 8),
          Text(
            'Private AI, always on-device',
            style: AppTypography.userMeta,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: const [
              _FeatureChip(icon: Icons.lock_outline, label: 'No internet needed'),
              _FeatureChip(icon: Icons.mic_none, label: 'Siri integration'),
              _FeatureChip(icon: Icons.speed, label: 'Runs on-chip'),
              _FeatureChip(icon: Icons.attach_file, label: 'Photos & files'),
              _FeatureChip(icon: Icons.image_outlined, label: 'AI image gen'),
              _FeatureChip(icon: Icons.visibility_off_outlined, label: 'Fully private'),
            ],
          ),
          const SizedBox(height: 40),
          FilledButton.icon(
            onPressed: onModelTap,
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Choose a model to get started'),
          ),
          const SizedBox(height: 16),
          Text(
            'You can also say "Hey Siri, Ask PintSizeAi…" to use voice.',
            style: AppTypography.sidebarSubtitle,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(label, style: AppTypography.badge),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message list
// ─────────────────────────────────────────────────────────────────────────────

class _MessageList extends ConsumerWidget {
  const _MessageList({
    required this.messages,
    required this.activeModel,
    required this.scrollCtrl,
    required this.genStatus,
    required this.genProgress,
    required this.onEditMessage,
    required this.onRegenerateWithModel,
  });

  final List<ChatMessage> messages;
  final ModelVariant? activeModel;
  final ScrollController scrollCtrl;
  final ImageGenStatus genStatus;
  final double genProgress;
  final void Function(String id, String content) onEditMessage;
  final VoidCallback onRegenerateWithModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGeneratingImage = genStatus == ImageGenStatus.generating;
    final extraItems = isGeneratingImage ? 1 : 0;

    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      itemCount: messages.length + extraItems,
      itemBuilder: (context, i) {
        // Generation progress row at the end
        if (i == messages.length && isGeneratingImage) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _ImageGenProgressRow(
              progress: genProgress,
              modelIcon: _modelIcon(activeModel, size: 28),
              onCancel: () {
                ref.read(imageGenProvider).cancel();
                ref.read(imageGenStatusProvider.notifier).state =
                    ImageGenStatus.idle;
              },
            ),
          );
        }
        final msg = messages[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: msg.isUser
              ? UserMessage(
                  text: msg.content,
                  attachments: msg.attachments,
                  onEdit: () => onEditMessage(msg.id, msg.content),
                )
              : msg.isStreaming && msg.content.isEmpty
                  ? TypingIndicator(
                      modelIcon: _modelIcon(activeModel, size: 28),
                    )
                  : AssistantMessage(
                      text: msg.content,
                      modelIcon: _modelIcon(activeModel, size: 28),
                      attachments: msg.attachments,
                      tokensPerSec: msg.tokensPerSec,
                      elapsedMs: msg.elapsedMs,
                      rating: msg.rating,
                      onRate: (r) {
                        ref
                            .read(chatControllerProvider.notifier)
                            .rateMessage(msg.id, r);
                        if (r == -1) {
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(const SnackBar(
                              content: Text(
                                  'Thanks — I\'ll remember this and try to do better.'),
                              duration: Duration(seconds: 2),
                            ));
                        }
                      },
                      onRegenerate: i > 0 && messages[i - 1].isUser
                          ? () {
                              final prev = messages[i - 1];
                              ref
                                  .read(chatControllerProvider.notifier)
                                  .editAndRegenerate(prev.id, prev.content);
                            }
                          : null,
                      // Only offer "try another model" on the last message.
                      onRegenerateWithModel:
                          i == messages.length - 1 && i > 0 && messages[i - 1].isUser
                              ? onRegenerateWithModel
                              : null,
                      onBranch: () {
                        ref
                            .read(chatControllerProvider.notifier)
                            .branchAt(i);
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(const SnackBar(
                            content: Text('Branched into a new chat'),
                            duration: Duration(seconds: 2),
                          ));
                      },
                    ),
        );
      },
    );
  }

  Widget _modelIcon(ModelVariant? model, {double size = 28}) {
    final color = switch (model?.family) {
      ModelFamily.llama => AppColors.modelWhite,
      ModelFamily.phi => AppColors.modelBlue,
      ModelFamily.gemma => AppColors.modelGreen,
      ModelFamily.mistral => AppColors.modelPurple,
      ModelFamily.qwen => AppColors.modelPurple,
      ModelFamily.deepseek => AppColors.modelBlue,
      ModelFamily.smollm => AppColors.modelSurface,
      null => AppColors.modelSurface,
    };
    final icon = switch (model?.family) {
      ModelFamily.llama => Icons.memory,
      ModelFamily.phi => Icons.hexagon_outlined,
      ModelFamily.gemma => Icons.diamond_outlined,
      ModelFamily.mistral => Icons.bolt,
      ModelFamily.qwen => Icons.waves,
      ModelFamily.deepseek => Icons.psychology_outlined,
      ModelFamily.smollm => Icons.bubble_chart_outlined,
      null => Icons.memory_outlined,
    };
    return ModelIcon(color: color, icon: icon, size: size);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image generation progress row
// ─────────────────────────────────────────────────────────────────────────────

class _ImageGenProgressRow extends StatelessWidget {
  const _ImageGenProgressRow({
    required this.progress,
    required this.modelIcon,
    this.onCancel,
  });
  final double progress;
  final Widget modelIcon;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).toInt();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        modelIcon,
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceOverlay,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(AppColors.accentGreen),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Generating image${pct > 0 ? '  $pct%' : '…'}',
                      style: AppTypography.modelDesc,
                    ),
                    const Spacer(),
                    if (onCancel != null)
                      GestureDetector(
                        onTap: onCancel,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.borderDefault),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('Stop',
                              style: AppTypography.userMeta
                                  .copyWith(color: AppColors.textMuted)),
                        ),
                      ),
                  ],
                ),
                if (progress > 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: AppColors.surfaceActive,
                      valueColor: const AlwaysStoppedAnimation(AppColors.accentGreen),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat input wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.isGenerating,
    required this.modelLoaded,
    required this.pendingAttachments,
    required this.onSend,
    required this.onStop,
    required this.onAddTap,
    required this.onRemoveAttachment,
    this.webSearchEnabled = false,
    this.onToggleWebSearch,
    this.isListening = false,
    this.onToggleVoice,
    this.onRemoveBackgroundTap,
  });

  final TextEditingController controller;
  final bool isGenerating;
  final bool modelLoaded;
  final List<ChatAttachment> pendingAttachments;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onAddTap;
  final ValueChanged<int> onRemoveAttachment;
  final bool webSearchEnabled;
  final VoidCallback? onToggleWebSearch;
  final bool isListening;
  final VoidCallback? onToggleVoice;
  final VoidCallback? onRemoveBackgroundTap;

  @override
  Widget build(BuildContext context) {
    return ChatInputBox(
      controller: controller,
      isGenerating: isGenerating,
      onSend: onSend,
      onStop: onStop,
      onAddTap: onAddTap,
      pendingAttachments: pendingAttachments,
      onRemoveAttachment: onRemoveAttachment,
      webSearchEnabled: webSearchEnabled,
      onToggleWebSearch: onToggleWebSearch,
      isListening: isListening,
      onToggleVoice: onToggleVoice,
      onRemoveBackgroundTap: onRemoveBackgroundTap,
      placeholder: modelLoaded ? 'Message' : 'Message  ·  /image  ·  /video',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Command suggestion bar
// ─────────────────────────────────────────────────────────────────────────────

class _CommandSuggestionBar extends StatelessWidget {
  const _CommandSuggestionBar({
    required this.suggestions,
    required this.onSelect,
  });

  final List<_Cmd> suggestions;
  final ValueChanged<_Cmd> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOverlay,
        border: Border(
          top: BorderSide(color: AppColors.borderDefault),
        ),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        reverse: true,
        itemCount: suggestions.length,
        itemBuilder: (_, i) {
          final cmd = suggestions[i];
          return InkWell(
            onTap: () => onSelect(cmd),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: (cmd.color ?? AppColors.textMuted).withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      cmd.icon,
                      size: 16,
                      color: cmd.color ?? AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '/${cmd.name}',
                                style: AppTypography.modelName.copyWith(
                                  color: cmd.color ?? AppColors.textDefault,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              if (cmd.argHint != null)
                                TextSpan(
                                  text: ' ${cmd.argHint}',
                                  style: AppTypography.modelDesc,
                                ),
                            ],
                          ),
                        ),
                        Text(cmd.description, style: AppTypography.userMeta),
                      ],
                    ),
                  ),
                  Icon(Icons.keyboard_tab,
                      size: 14, color: AppColors.textDim),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Attachment picker sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AttachmentPickerSheet extends StatelessWidget {
  const _AttachmentPickerSheet({
    required this.onPickPhoto,
    required this.onTakePhoto,
    required this.onPickVideo,
    required this.onPickFile,
    required this.onGenerateImage,
    required this.onGenerateVideo,
  });

  final VoidCallback onPickPhoto;
  final VoidCallback onTakePhoto;
  final VoidCallback onPickVideo;
  final VoidCallback onPickFile;
  final VoidCallback onGenerateImage;
  final VoidCallback onGenerateVideo;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.borderDefault,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Attach or Create',
                style: AppTypography.sheetTitle),
            const SizedBox(height: 16),

            // Grid of options
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.15,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                _PickerOption(
                  icon: Icons.photo_library_outlined,
                  label: 'Photo Library',
                  color: const Color(0xFF4FC3F7),
                  onTap: onPickPhoto,
                ),
                _PickerOption(
                  icon: Icons.camera_alt_outlined,
                  label: 'Camera',
                  color: const Color(0xFF4DB6AC),
                  onTap: onTakePhoto,
                ),
                _PickerOption(
                  icon: Icons.video_library_outlined,
                  label: 'Video',
                  color: const Color(0xFF9575CD),
                  onTap: onPickVideo,
                ),
                _PickerOption(
                  icon: Icons.folder_outlined,
                  label: 'Files',
                  color: const Color(0xFFFFB74D),
                  onTap: onPickFile,
                ),
                _PickerOption(
                  icon: Icons.auto_awesome_outlined,
                  label: 'Generate Image',
                  color: AppColors.accentGreen,
                  onTap: onGenerateImage,
                ),
                _PickerOption(
                  icon: Icons.smart_display_outlined,
                  label: 'Generate Video',
                  color: const Color(0xFFEF5350),
                  onTap: onGenerateVideo,
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _PickerOption extends StatelessWidget {
  const _PickerOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceOverlay,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: AppTypography.badge,
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}
