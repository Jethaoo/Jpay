import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'backend/backend_models.dart';
import 'backend/jpay_repository.dart';
import 'network_status.dart';

class SupabaseProfileScreen extends StatefulWidget {
  final JpayRepository repository;

  const SupabaseProfileScreen({super.key, required this.repository});

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
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
      _photoUrl = photoUrl;
    } catch (error) {
      _showError(error, 'load your profile');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 78,
      maxWidth: 1600,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() => _selectedImage = bytes);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      var photoPath = _profile?.photoPath;
      if (_selectedImage != null) {
        photoPath = await widget.repository.uploadProfilePicture(
          _selectedImage!,
        );
      }
      await widget.repository.updateProfile(
        displayName: _displayNameController.text.trim(),
        photoPath: photoPath,
      );
      if (photoPath != null) {
        _photoUrl = await widget.repository.createProfilePictureUrl(photoPath);
      }
      _profile = ProfileRecord(
        id: _profile!.id,
        displayName: _displayNameController.text.trim(),
        photoPath: photoPath,
      );
      _selectedImage = null;
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

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: AppPalette.surfaceElevated,
                        foregroundImage: _selectedImage != null
                            ? MemoryImage(_selectedImage!)
                            : (_photoUrl == null
                                  ? null
                                  : NetworkImage(_photoUrl!) as ImageProvider),
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
                              padding: EdgeInsets.all(9),
                              child: Icon(
                                Icons.edit_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 34),
                const Text(
                  'Account',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _displayNameController,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: user?.email ?? '',
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
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
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                    if (!context.mounted) return;
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Logout'),
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
