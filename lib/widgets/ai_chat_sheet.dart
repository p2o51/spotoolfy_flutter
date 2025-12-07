import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/gemini_chat_service.dart';
import '../services/notification_service.dart';
import '../l10n/app_localizations.dart';

/// Chat message model
class ChatMessage {
  final String content;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.content,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'content': content,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        content: json['content'] as String,
        isUser: json['isUser'] as bool,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

/// Cache for chat conversations
class _ChatCache {
  static final Map<String, List<ChatMessage>> _cache = {};

  static String _buildKey(ChatContext context) {
    final type = context.type.name;
    final track = context.trackTitle;
    final artist = context.artistName;
    final lyrics = context.selectedLyrics?.hashCode.toString() ?? '';
    return '$type|$track|$artist|$lyrics';
  }

  static List<ChatMessage> get(ChatContext context) {
    final key = _buildKey(context);
    return _cache[key] ?? [];
  }

  static void save(ChatContext context, List<ChatMessage> messages) {
    final key = _buildKey(context);
    _cache[key] = List.from(messages);
  }

  static void clear(ChatContext context) {
    final key = _buildKey(context);
    _cache.remove(key);
  }
}

/// Reusable AI chat sheet widget
class AIChatSheet extends StatefulWidget {
  final ChatContext context;
  final String? initialAnalysis;
  final VoidCallback? onClose;

  const AIChatSheet({
    super.key,
    required this.context,
    this.initialAnalysis,
    this.onClose,
  });

  /// Show the chat sheet as a modal bottom sheet
  static Future<void> show({
    required BuildContext context,
    required ChatContext chatContext,
    String? initialAnalysis,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AIChatSheet(
        context: chatContext,
        initialAnalysis: initialAnalysis,
      ),
    );
  }

  @override
  State<AIChatSheet> createState() => _AIChatSheetState();
}

class _AIChatSheetState extends State<AIChatSheet>
    with TickerProviderStateMixin {
  final GeminiChatService _chatService = GeminiChatService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  bool _isLoading = false;
  String? _error;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _shimmerController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _shimmerAnimation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _shimmerController,
      curve: Curves.easeInOut,
    ));

    // Load cached messages first
    final cachedMessages = _ChatCache.get(widget.context);
    if (cachedMessages.isNotEmpty) {
      _messages.addAll(cachedMessages);
    }
    // Add initial analysis as first AI message if provided and no cache
    else if (widget.initialAnalysis != null &&
        widget.initialAnalysis!.isNotEmpty) {
      _messages.add(ChatMessage(
        content: widget.initialAnalysis!,
        isUser: false,
      ));
    }
  }

  @override
  void dispose() {
    // Save messages to cache before disposing
    if (_messages.isNotEmpty) {
      _ChatCache.save(widget.context, _messages);
    }
    _controller.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startLoadingAnimation() {
    _pulseController.repeat(reverse: true);
    _shimmerController.repeat();
    _startVibrationCycle();
  }

  void _stopLoadingAnimation() {
    _pulseController.stop();
    _shimmerController.stop();
  }

  void _startVibrationCycle() {
    final vibrationPattern = [
      (Duration(milliseconds: 400), HapticFeedback.heavyImpact),
      (Duration(milliseconds: 200), HapticFeedback.lightImpact),
      (Duration(milliseconds: 200), HapticFeedback.selectionClick),
      (Duration(milliseconds: 300), HapticFeedback.mediumImpact),
      (Duration(milliseconds: 600), HapticFeedback.lightImpact),
    ];
    int patternIndex = 0;

    void performVibration() {
      if (mounted && _isLoading) {
        final (delay, vibration) = vibrationPattern[patternIndex];
        vibration();
        patternIndex = (patternIndex + 1) % vibrationPattern.length;
        Future.delayed(delay, performVibration);
      }
    }

    performVibration();
  }

  Future<void> _sendMessage(String message) async {
    if (message.isEmpty || _isLoading) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _messages.add(ChatMessage(content: message, isUser: true));
      _isLoading = true;
      _error = null;
      _controller.clear();
    });

    _scrollToBottom();
    _startLoadingAnimation();

    try {
      // Build conversation history for API
      final history = _messages
          .map((m) => {
                'role': m.isUser ? 'user' : 'model',
                'content': m.content,
              })
          .toList();

      // Remove last user message from history (it's the current message)
      if (history.isNotEmpty) {
        history.removeLast();
      }

      final response = await _chatService.chat(
        message: message,
        context: widget.context,
        conversationHistory: history,
      );

      if (mounted) {
        HapticFeedback.lightImpact();
        setState(() {
          _isLoading = false;
          _messages.add(ChatMessage(content: response, isUser: false));
        });
        _stopLoadingAnimation();
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
        _stopLoadingAnimation();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.85;

    return Container(
      height: maxHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          _buildHeader(context, theme, l10n),

          const Divider(height: 1),

          // Chat area
          Expanded(
            child: _messages.isEmpty && !_isLoading
                ? _buildEmptyState(context, theme, l10n)
                : ListView.builder(
                    controller: _scrollController,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _isLoading) {
                        return _buildThinkingIndicator(context, theme, l10n);
                      }
                      return _buildMessageBubble(context, _messages[index]);
                    },
                  ),
          ),

          // Error message
          if (_error != null) _buildErrorMessage(context, theme),

          // Input area
          _buildInputArea(context, theme, l10n),
        ],
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, ThemeData theme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            color: theme.colorScheme.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.askMoreAboutTrack,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.context.selectedLyrics != null)
                  Text(
                    '"${_truncateText(widget.context.selectedLyrics!, 30)}"',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _messages.clear();
                  _ChatCache.clear(widget.context);
                });
              },
              tooltip: 'Clear chat',
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              widget.onClose?.call();
              Navigator.pop(context);
            },
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context, ThemeData theme, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.askFollowUpHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            if (widget.context.selectedLyrics != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.format_quote_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '选中的歌词',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.context.selectedLyrics!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                      ),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingIndicator(
      BuildContext context, ThemeData theme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_pulseController, _shimmerController]),
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: _pulseAnimation.value,
                      child: ShaderMask(
                        shaderCallback: (bounds) {
                          return LinearGradient(
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.tertiary,
                              theme.colorScheme.primary,
                            ],
                            stops: [
                              (_shimmerAnimation.value - 0.3).clamp(0.0, 1.0),
                              _shimmerAnimation.value.clamp(0.0, 1.0),
                              (_shimmerAnimation.value + 0.3).clamp(0.0, 1.0),
                            ],
                          ).createShader(bounds);
                        },
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l10n.followUpThinking,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage message) {
    final theme = Theme.of(context);
    final isUser = message.isUser;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isUser)
                    Text(
                      message.content,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  else
                    MarkdownBody(
                      data: message.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          height: 1.5,
                        ),
                        h1: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                        h2: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                        h3: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                        code: theme.textTheme.bodySmall?.copyWith(
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHigh,
                          fontFamily: 'monospace',
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        blockquote: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                        listBullet: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                        strong: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                        em: theme.textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  if (!isUser) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Clipboard.setData(
                                ClipboardData(text: message.content));
                            Provider.of<NotificationService>(context,
                                    listen: false)
                                .showSnackBar(l10n.copiedToClipboard(''));
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.copy_rounded,
                              size: 16,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildErrorMessage(BuildContext context, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: theme.colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(
      BuildContext context, ThemeData theme, AppLocalizations l10n) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + (keyboardHeight > 0 ? keyboardHeight : bottomPadding),
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: l10n.askFollowUpHint,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              suffixIcon: IconButton(
                icon: Icon(
                  Icons.send_rounded,
                  color: _isLoading
                      ? theme.colorScheme.outline
                      : theme.colorScheme.primary,
                ),
                onPressed:
                    _isLoading ? null : () => _sendMessage(_controller.text.trim()),
              ),
            ),
            textInputAction: TextInputAction.send,
            enabled: !_isLoading,
            onSubmitted: _isLoading ? null : _sendMessage,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.poweredByGoogleSearch,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}
