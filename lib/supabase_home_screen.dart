import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'backend/backend_models.dart';
import 'backend/jpay_repository.dart';
import 'backend/supabase_jpay_repository.dart';
import 'network_status.dart';
import 'supabase_group_details_screen.dart';
import 'supabase_profile_screen.dart';
import 'widgets/group_name_dialog.dart';

class SupabaseHomeScreen extends StatefulWidget {
  final JpayRepository? repository;
  final String? userEmail;

  const SupabaseHomeScreen({super.key, this.repository, this.userEmail});

  @override
  State<SupabaseHomeScreen> createState() => _SupabaseHomeScreenState();
}

class _SupabaseHomeScreenState extends State<SupabaseHomeScreen> {
  late final JpayRepository _repository;
  final _searchController = TextEditingController();
  final Set<String> _hiddenGroupIds = {};
  String _query = '';
  String? _profilePhotoUrl;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? SupabaseJpayRepository(Supabase.instance.client);
    _loadProfilePicture();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final name = await _showNameDialog(title: 'New group');
    if (name == null) return;
    try {
      await _repository.createGroup(name);
    } catch (error) {
      _showError(error, 'create this group');
    }
  }

  Future<void> _loadProfilePicture() async {
    try {
      final profile = await _repository.getProfile();
      final photoUrl = await _repository.createProfilePictureUrl(
        profile.photoPath,
      );
      if (!mounted) return;
      setState(() => _profilePhotoUrl = photoUrl);
    } catch (_) {
      // Keep the initial fallback when the profile or image is unavailable.
    }
  }

  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupabaseProfileScreen(repository: _repository),
      ),
    );
    if (!mounted) return;
    await _loadProfilePicture();
  }

  Future<void> _renameGroup(GroupRecord group) async {
    final name = await _showNameDialog(
      title: 'Rename group',
      initialValue: group.name,
    );
    if (name == null || name == group.name) return;
    try {
      await _repository.renameGroup(group.id, name);
    } catch (error) {
      _showError(error, 'rename this group');
    }
  }

  Future<void> _deleteGroup(GroupRecord group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text(
          'Delete “${group.name}” and all of its expense history? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppPalette.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _hiddenGroupIds.add(group.id));
    try {
      await _repository.deleteGroup(group.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${group.name} deleted')));
    } catch (error) {
      if (mounted) setState(() => _hiddenGroupIds.remove(group.id));
      _showError(error, 'delete this group');
    }
  }

  Future<String?> _showNameDialog({
    required String title,
    String initialValue = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => GroupNameDialog(
        title: title,
        initialValue: initialValue,
        actionLabel: initialValue.isEmpty ? 'Create' : 'Save',
      ),
    );
  }

  void _openGroup(GroupRecord group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupabaseGroupDetailsScreen(
          groupId: group.id,
          initialName: group.name,
          repository: _repository,
        ),
      ),
    );
  }

  void _openGroupManager() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ManageGroupsScreen(
          repository: _repository,
          onOpen: _openGroup,
          onRename: _renameGroup,
          onDelete: _deleteGroup,
        ),
      ),
    );
  }

  void _showError(Object error, String action) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(networkAwareErrorMessage(error, action: action))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email =
        widget.userEmail ??
        Supabase.instance.client.auth.currentUser?.email ??
        '';
    final now = DateTime.now();
    final monthYear = '${_monthName(now.month)} ${now.year}';
    final profilePhotoUrl = _profilePhotoUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          monthYear,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            letterSpacing: -0.3,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.grid_view_rounded),
          tooltip: 'Manage groups',
          onPressed: _openGroupManager,
        ),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: _openProfile,
            icon: CircleAvatar(
              radius: 18,
              backgroundColor: AppPalette.surfaceElevated,
              foregroundImage: profilePhotoUrl == null
                  ? null
                  : NetworkImage(profilePhotoUrl),
              onForegroundImageError: profilePhotoUrl == null
                  ? null
                  : (_, _) {
                      if (mounted && _profilePhotoUrl == profilePhotoUrl) {
                        setState(() => _profilePhotoUrl = null);
                      }
                    },
              child: Text(
                email.isEmpty ? 'J' : email[0].toUpperCase(),
                style: const TextStyle(
                  color: AppPalette.blue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGroup,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Group'),
      ),
      body: StreamBuilder<List<GroupRecord>>(
        stream: _repository.watchGroups(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorState(
              message: networkAwareErrorMessage(
                snapshot.error!,
                action: 'load your groups',
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final serverGroups = snapshot.data!;
          _hiddenGroupIds.removeWhere(
            (id) => !serverGroups.any((group) => group.id == id),
          );
          final groups = serverGroups
              .where((group) => !_hiddenGroupIds.contains(group.id))
              .toList();
          final query = _query.toLowerCase();
          final visible = groups
              .where((group) => group.name.toLowerCase().contains(query))
              .toList();
          final totalOwed = groups.fold<double>(
            0,
            (total, group) => total + group.totalOwed,
          );

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
            children: [
              _SearchField(
                controller: _searchController,
                query: _query,
                onChanged: (value) => setState(() => _query = value.trim()),
                onClear: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      title: 'Total Owed',
                      value: 'RM ${totalOwed.toStringAsFixed(2)}',
                      icon: Icons.arrow_downward_rounded,
                      color: AppPalette.red,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Active Groups',
                      value: groups.length.toString(),
                      icon: Icons.account_balance_wallet_outlined,
                      color: AppPalette.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _query.isEmpty ? 'My Groups' : 'Search results',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  Text(
                    _query.isEmpty
                        ? 'Updated today'
                        : '${visible.length} found',
                    style: const TextStyle(
                      color: AppPalette.secondaryLabel,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (groups.isEmpty)
                const _EmptyGroupsState(searching: false)
              else if (visible.isEmpty)
                const _EmptyGroupsState(searching: true)
              else
                ...visible.map(
                  (group) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _GroupCard(
                      group: group,
                      repository: _repository,
                      onTap: () => _openGroup(group),
                      onRename: () => _renameGroup(group),
                      onDelete: () => _deleteGroup(group),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER',
    ];
    return months[month - 1];
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.separator),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search for groups',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Clear search',
                ),
          fillColor: AppPalette.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppPalette.secondaryLabel,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final GroupRecord group;
  final JpayRepository repository;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _GroupCard({
    required this.group,
    required this.repository,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.separator),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppPalette.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    group.name.isEmpty ? '?' : group.name[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      StreamBuilder<List<GroupFriendRecord>>(
                        stream: repository.watchFriends(group.id),
                        builder: (context, snapshot) {
                          final count = snapshot.data?.length;
                          return Row(
                            children: [
                              const Icon(
                                Icons.people_outline,
                                size: 14,
                                color: AppPalette.secondaryLabel,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                count == null
                                    ? 'Loading friends…'
                                    : '$count ${count == 1 ? 'friend' : 'friends'}',
                                style: const TextStyle(
                                  color: AppPalette.secondaryLabel,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (group.totalOwed > 0)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 108),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppPalette.redContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'RM ${group.totalOwed.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppPalette.red,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                else
                  const Text(
                    'All paid',
                    style: TextStyle(
                      color: AppPalette.green,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Group actions',
                  onSelected: (value) {
                    if (value == 'rename') onRename();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename group')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete group',
                        style: TextStyle(color: AppPalette.red),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ManageGroupsScreen extends StatelessWidget {
  final JpayRepository repository;
  final ValueChanged<GroupRecord> onOpen;
  final ValueChanged<GroupRecord> onRename;
  final ValueChanged<GroupRecord> onDelete;

  const _ManageGroupsScreen({
    required this.repository,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Groups')),
      body: StreamBuilder<List<GroupRecord>>(
        stream: repository.watchGroups(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorState(
              message: networkAwareErrorMessage(
                snapshot.error!,
                action: 'load your groups',
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = snapshot.data!;
          if (groups.isEmpty) {
            return const _EmptyGroupsState(searching: false);
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final group = groups[index];
              return Card(
                child: ListTile(
                  onTap: () {
                    Navigator.pop(context);
                    onOpen(group);
                  },
                  contentPadding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  leading: CircleAvatar(
                    backgroundColor: AppPalette.blue,
                    foregroundColor: Colors.white,
                    child: Text(
                      group.name.isEmpty ? '?' : group.name[0].toUpperCase(),
                    ),
                  ),
                  title: Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    group.totalOwed > 0
                        ? 'RM ${group.totalOwed.toStringAsFixed(2)} owed'
                        : 'All settled',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => onRename(group),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Rename group',
                      ),
                      IconButton(
                        onPressed: () => onDelete(group),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppPalette.red,
                        ),
                        tooltip: 'Delete group',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyGroupsState extends StatelessWidget {
  final bool searching;

  const _EmptyGroupsState({required this.searching});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 52),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(
              color: AppPalette.surfaceElevated,
              shape: BoxShape.circle,
            ),
            child: Icon(
              searching
                  ? Icons.search_off_outlined
                  : Icons.account_balance_wallet_outlined,
              size: 48,
              color: AppPalette.blue,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            searching ? 'No matching groups' : 'No groups yet',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(
            searching
                ? 'Try a different name or clear your search.'
                : 'Create your first group to start tracking expenses.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppPalette.secondaryLabel),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
