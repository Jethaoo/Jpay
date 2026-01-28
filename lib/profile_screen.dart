import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _displayNameController = TextEditingController();
  final _picker = ImagePicker();
  File? _imageFile;
  String? _photoUrl;
  bool _isSaving = false;

  User get _user => FirebaseAuth.instance.currentUser!;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_user.uid)
        .get();

    if (!mounted) return;

    final data = doc.data();
    _displayNameController.text =
        data != null && data['displayName'] is String ? data['displayName'] as String : '';
    _photoUrl =
        data != null && data['photoUrl'] is String ? data['photoUrl'] as String : null;
    setState(() {});
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (picked == null) return;

    setState(() {
      _imageFile = File(picked.path);
    });
  }

  Future<void> _saveProfile() async {
    setState(() {
      _isSaving = true;
    });

    try {
      String? downloadUrl = _photoUrl;

      // If a new image is picked, upload it to Firebase Storage.
      if (_imageFile != null) {
        try {
          // Use a simple filename based on user ID (will overwrite old one)
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('user_profile_pics')
              .child('${_user.uid}.jpg');

          // Upload new image with metadata
          final metadata = SettableMetadata(
            contentType: 'image/jpeg',
            cacheControl: 'max-age=3600',
          );
          
          // Upload the file
          await storageRef.putFile(_imageFile!, metadata);
          
          // Get download URL after successful upload
          downloadUrl = await storageRef.getDownloadURL();
          
        } catch (uploadError) {
          // If upload fails, show specific error with helpful message
          if (!mounted) return;
          
          String errorMessage = 'Error uploading image: $uploadError';
          if (uploadError.toString().contains('permission') || 
              uploadError.toString().contains('object-not-found')) {
            errorMessage += '\n\nPlease update Firebase Storage rules:\n'
                'Go to Firebase Console → Storage → Rules\n'
                'Add rules to allow authenticated users to write to user_profile_pics/';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              duration: const Duration(seconds: 6),
            ),
          );
          return;
        }
      }

      // Save to Firestore
      try {
        await FirebaseFirestore.instance.collection('users').doc(_user.uid).set(
          {
            'displayName': _displayNameController.text.trim(),
            if (downloadUrl != null) 'photoUrl': downloadUrl,
          },
          SetOptions(merge: true),
        );

        _photoUrl = downloadUrl;
        _imageFile = null; // Clear the picked file after successful save

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
      } catch (firestoreError) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving to database: $firestoreError'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unexpected error: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = _user.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 12),
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    Builder(
                      builder: (context) {
                        final hasImage = _imageFile != null || (_photoUrl != null && _photoUrl!.isNotEmpty);
                        final imageProvider = _imageFile != null
                            ? FileImage(_imageFile!) as ImageProvider
                            : (_photoUrl != null && _photoUrl!.isNotEmpty
                                ? NetworkImage(_photoUrl!) as ImageProvider
                                : null);
                        
                        return CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.indigo.shade100,
                          backgroundImage: imageProvider,
                          onBackgroundImageError: hasImage
                              ? (exception, stackTrace) {
                                  // If network image fails to load, clear the photoUrl
                                  setState(() {
                                    _photoUrl = null;
                                  });
                                }
                              : null,
                          child: !hasImage
                              ? Text(
                                  email.isNotEmpty ? email[0].toUpperCase() : 'U',
                                  style: GoogleFonts.inter(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.indigo.shade700,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.indigo,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Account',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _displayNameController,
              decoration: InputDecoration(
                labelText: 'Display name',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              enabled: false,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
              controller: TextEditingController(text: email),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Save changes',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text(
                'Logout',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


