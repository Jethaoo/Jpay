import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'backend/backend_models.dart';
import 'backend/jpay_repository.dart';
import 'network_status.dart';
import 'services/jpay_auth_service.dart';
import 'widgets/app_ui.dart';

class SupabaseProfileScreen extends StatefulWidget {
  final JpayRepository repository;
  final JpayAuthService? authService;

  const SupabaseProfileScreen({
    super.key,
    required this.repository,
    this.authService,
  });

  @override
  State<SupabaseProfileScreen> createState() => _SupabaseProfileScreenState();
}

class _SupabaseProfileScreenState extends State<SupabaseProfileScreen> {
  final _displayNameController = TextEditingController();
  final _picker = ImagePicker();
  ProfileRecord? _profile;
  Uint8List? _selectedImage;
  String? _photoUrl;
  bool _loading = true;
  bool _saving = false;
  String _initialDisplayName = '';
  String? _nameError;
  String? _photoError;

  JpayAuthService get _authService =>
      widget.authService ?? SupabaseJpayAuthService(Supabase.instance.client);

  bool get _isDirty =>
      _selectedImage != null ||
      _displayNameController.text.trim() != _initialDisplayName;

  @override
  void initState() {
    super.initState();
    _displayNameController.addListener(_handleNameChanged);
    _load();
  }

  @override
  void dispose() {
    _displayNameController.removeListener(_handleNameChanged);
    _displayNameController.dispose();
    super.dispose();
  }

  void _handleNameChanged() {
    if (!mounted) return;
    setState(() {
      if (_displayNameController.text.trim().isNotEmpty) _nameError = null;
    });
  }

  Future<void> _load() async {
    try {
      final profile = await widget.repository.getProfile();
      final photoUrl = await widget.repository.createProfilePictureUrl(
        profile.photoPath,
      );
      if (!mounted) return;
      _profile = profile;
      _displayNameController.text = profile.displayName;
      _initialDisplayName = profile.displayName.trim();
      _photoUrl = photoUrl;
    } catch (error) {
      _showError(error, 'load your profile');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 78,
        maxWidth: 1600,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImage = bytes;
        _photoError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _photoError = 'Could not open your photo library.');
      }
    }
  }

  Future<void> _save() async {
    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) {
      setState(() => _nameError = 'Enter a display name.');
      return;
    }
    if (!_isDirty) return;
    setState(() => _saving = true);
    try {
      var photoPath = _profile?.photoPath;
      if (_selectedImage != null) {
        photoPath = await widget.repository.uploadProfilePicture(
          _selectedImage!,
        );
      }
      await widget.repository.updateProfile(
        displayName: displayName,
        photoPath: photoPath,
      );
      if (photoPath != null) {
        _photoUrl = await widget.repository.createProfilePictureUrl(photoPath);
      }
      _profile = ProfileRecord(
        id: _profile!.id,
        displayName: displayName,
        photoPath: photoPath,
      );
      _selectedImage = null;
      _initialDisplayName = displayName;
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated')));
    } catch (error) {
      _showError(error, 'update your profile');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(Object error, String action) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(networkAwareErrorMessage(error, action: action))),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.logout_rounded, color: AppPalette.red),
        title: const Text('Log out of Jpay?'),
        content: const Text(
          'Your saved account data will remain available after you sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppPalette.red),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const AppLoadingList(itemCount: 3)
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              children: [
                AppSectionCard(
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 52,
                            backgroundColor: AppPalette.surfaceElevated,
                            foregroundImage: _selectedImage != null
                                ? MemoryImage(_selectedImage!)
                                : (_photoUrl == null
                                      ? null
                                      : NetworkImage(_photoUrl!)
                                            as ImageProvider),
                            onForegroundImageError: (_, _) {
                              if (mounted) {
                                setState(() {
                                  _photoUrl = null;
                                  _photoError =
                                      'Your profile photo could not be loaded.';
                                });
                              }
                            },
                            child: _selectedImage == null && _photoUrl == null
                                ? const Icon(
                                    Icons.person_rounded,
                                    size: 48,
                                    color: AppPalette.secondaryLabel,
                                  )
                                : null,
                          ),
                          Semantics(
                            button: true,
                            label: 'Choose profile picture',
                            child: Material(
                              color: AppPalette.blue,
                              shape: const CircleBorder(),
                              child: InkWell(
                                onTap: _pickPhoto,
                                customBorder: const CircleBorder(),
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.photo_camera_outlined,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _displayNameController.text.trim().isEmpty
                            ? 'Your profile'
                            : _displayNameController.text.trim(),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(
                          color: AppPalette.secondaryLabel,
                        ),
                      ),
                      if (_photoError != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _photoError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppPalette.orange,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppSectionHeader(
                        title: 'Account',
                        subtitle: 'How you appear across Jpay.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _displayNameController,
                        maxLength: 80,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Display name',
                          errorText: _nameError,
                          counterText: '',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        initialValue: user?.email ?? '',
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _saving || !_isDirty ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Text('Save Changes'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: _saving ? null : _confirmLogout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log out'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppPalette.red,
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ],
            ),
    );
  }
}
