import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/group_item.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import 'group_detail_screen.dart';

class GroupsScreen extends StatefulWidget {
  final AuthSession session;

  const GroupsScreen({super.key, required this.session});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  static const Color redDark = Color(0xFFB71C1C);

  final BackendService _backendService = const BackendService();
  final TextEditingController _nameController = TextEditingController();

  bool _loading = true;
  bool _creating = false;
  String? _error;
  List<GroupItem> _groups = const [];

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final groups = await _backendService.fetchUserGroups(
        widget.session.token,
        userId: widget.session.user.id,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _groups = groups;
        _loading = false;
      });
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

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _creating) {
      return;
    }

    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final group = await _backendService.createGroup(
        token: widget.session.token,
        name: name,
        creatorId: widget.session.user.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _groups = [group, ..._groups];
      });

      final creatorEmail = widget.session.user.email.trim();
      if (creatorEmail.isNotEmpty) {
        try {
          await _backendService.addGroupMember(
            token: widget.session.token,
            groupId: group.id,
            email: creatorEmail,
          );
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Group created. We could not add you as a member yet.',
                ),
              ),
            );
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _creating = false;
        _nameController.clear();
      });
    } catch (err) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = err.toString();
        _creating = false;
      });
    }
  }

  void _openGroup(GroupItem group) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            GroupDetailScreen(session: widget.session, group: group),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Groups',
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.w700,
            color: redDark,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadGroups,
            icon: const Icon(Icons.refresh_rounded),
            color: redDark,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: _CreateGroupCard(
                      controller: _nameController,
                      isCreating: _creating,
                      onCreate: _createGroup,
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _error!,
                          style: GoogleFonts.manrope(
                            color: redDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: _groups.isEmpty
                        ? _EmptyGroupsState(onRetry: _loadGroups)
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                            itemCount: _groups.length,
                            itemBuilder: (context, index) {
                              final group = _groups[index];
                              return _GroupTile(
                                group: group,
                                onTap: () => _openGroup(group),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CreateGroupCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isCreating;
  final VoidCallback onCreate;

  const _CreateGroupCard({
    required this.controller,
    required this.isCreating,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    const redDark = Color(0xFFB71C1C);
    const redSoft = Color(0xFFFFF5F5);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: redSoft),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create a group',
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: redDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You will be added automatically and can invite members next.',
            style: GoogleFonts.manrope(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onCreate(),
            decoration: InputDecoration(
              hintText: 'Group name',
              prefixIcon: const Icon(Icons.group_work_rounded),
              filled: true,
              fillColor: redSoft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isCreating ? null : onCreate,
              style: ElevatedButton.styleFrom(
                backgroundColor: redDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: isCreating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Create',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final GroupItem group;
  final VoidCallback onTap;

  const _GroupTile({required this.group, required this.onTap});

  String _initialsFor(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return '?';
    }

    if (parts.length == 1) {
      final word = parts.first;
      final length = word.length >= 2 ? 2 : word.length;
      return word.substring(0, length).toUpperCase();
    }

    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFF5F5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFFFF5F5),
          foregroundColor: const Color(0xFFB71C1C),
          child: Text(
            _initialsFor(group.name),
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
          ),
        ),
        title: Text(
          group.name,
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _EmptyGroupsState extends StatelessWidget {
  final VoidCallback onRetry;

  const _EmptyGroupsState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No groups yet',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFB71C1C),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first group to start tracking tasks together.',
              style: GoogleFonts.manrope(fontSize: 13, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Refresh')),
          ],
        ),
      ),
    );
  }
}
