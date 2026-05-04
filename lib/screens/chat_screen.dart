import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/chat_message.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';

class ChatScreen extends StatefulWidget {
  final AuthSession? session;

  const ChatScreen({super.key, this.session});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

enum _ChatMenuAction {
  reset,
  deleteLast,
}

class _ChatScreenState extends State<ChatScreen> {
  static const Color red = Color(0xFFE53935);
  static const Color redDark = Color(0xFFB71C1C);
  static const Color redSoft = Color(0xFFFFF5F5);

  final BackendService _backendService = const BackendService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  AuthSession? _session;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<ChatMessage> _messages = const [];

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    if (_session != null) {
      _loadMessages();
    } else {
      unawaited(_restoreSessionAndLoad());
    }
  }

  Future<void> _restoreSessionAndLoad() async {
    final restored = await AuthService().restoreSession();
    if (!mounted) return;
    setState(() {
      _session = restored;
    });

    if (_session != null) {
      await _loadMessages();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_session == null) throw Exception('Not authenticated');

      final messages = await _backendService.fetchChatMessages(
        _session!.token,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _messages = messages;
        _loading = false;
      });
      _scrollToBottom();
    } catch (err) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_sending) {
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    _controller.clear();

    try {
        if (_session == null) throw Exception('Not authenticated');

        final messages = await _backendService.sendChatMessage(
          token: _session!.token,
          message: text,
        );

      if (!mounted) {
        return;
      }

      setState(() {
        _messages = messages;
      });
      _scrollToBottom();
    } catch (err) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = err.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _resetChat() async {
    final confirm = await _confirmDialog(
      title: 'Reset chat',
      message: 'This will delete all messages in this chat.',
      confirmLabel: 'Reset',
    );

    if (!confirm) {
      return;
    }

    try {
        if (_session == null) throw Exception('Not authenticated');

        await _backendService.deleteChatHistory(_session!.token);
      if (!mounted) {
        return;
      }

      setState(() {
        _messages = const [];
        _error = null;
      });
    } catch (err) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = err.toString();
      });
    }
  }

  Future<void> _deleteLastMessage() async {
    if (_messages.isEmpty) {
      return;
    }

    await _deleteMessage(_messages.last);
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirm = await _confirmDialog(
      title: 'Delete message',
      message: 'Delete this message from the chat history?',
      confirmLabel: 'Delete',
    );

    if (!confirm) {
      return;
    }

    try {
        if (_session == null) throw Exception('Not authenticated');

        await _backendService.deleteChatMessage(
          token: _session!.token,
          id: message.id,
        );

      if (!mounted) {
        return;
      }

      setState(() {
        _messages = _messages.where((item) => item.id != message.id).toList();
      });
    } catch (err) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = err.toString();
      });
    }
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'SHAKIRA',
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.w700,
            color: redDark,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadMessages,
            icon: const Icon(Icons.refresh_rounded),
            color: redDark,
          ),
          PopupMenuButton<_ChatMenuAction>(
            onSelected: (action) {
              switch (action) {
                case _ChatMenuAction.reset:
                  _resetChat();
                  break;
                case _ChatMenuAction.deleteLast:
                  _deleteLastMessage();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ChatMenuAction.reset,
                child: Text('Reset chat'),
              ),
              PopupMenuItem(
                value: _ChatMenuAction.deleteLast,
                child: Text('Delete last message'),
              ),
            ],
            icon: const Icon(Icons.more_vert_rounded),
            color: Colors.white,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? _EmptyChatState(error: _error)
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            return _ChatBubble(
                              message: message,
                              onLongPress: () => _deleteMessage(message),
                            );
                          },
                        ),
            ),
            if (_error != null && _messages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: redDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 5,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Ask SHAKIRA... ',
                        filled: true,
                        fillColor: redSoft,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    width: 48,
                    child: ElevatedButton(
                      onPressed: _sending ? null : _sendMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: redDark,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onLongPress;

  const _ChatBubble({required this.message, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final bubbleColor = isUser ? const Color(0xFFB71C1C) : const Color(0xFFFFF5F5);
    final textColor = isUser ? Colors.white : Colors.black87;
    final border = isUser
        ? null
        : Border.all(color: const Color(0xFFF3DADA));

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: isUser
              ? Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    border: border,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                  ),
                  child: Text(
                    message.message,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: textColor,
                    ),
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Image.asset(
                          'assets/owl.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          border: border,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isUser ? 16 : 4),
                            bottomRight: Radius.circular(isUser ? 4 : 16),
                          ),
                        ),
                        child: Text(
                          message.message,
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  final String? error;

  const _EmptyChatState({this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Start chatting with SHAKIRA',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFB71C1C),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error ??
                  'Send a message and SHAKIRA\'s reply will appear here.',
              style: GoogleFonts.manrope(fontSize: 13, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
