import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'network_status.dart';

const int maximumGroupNameLength = 60;

String? validateGroupName(String value) {
  final name = value.trim();
  if (name.isEmpty) return 'Enter a group name';
  if (name.length > maximumGroupNameLength) {
    return 'Use $maximumGroupNameLength characters or fewer';
  }
  return null;
}

class EditGroupNameDialog extends StatefulWidget {
  final String groupId;
  final String currentName;

  const EditGroupNameDialog({
    super.key,
    required this.groupId,
    required this.currentName,
  });

  @override
  State<EditGroupNameDialog> createState() => _EditGroupNameDialogState();
}

class _EditGroupNameDialogState extends State<EditGroupNameDialog> {
  late final TextEditingController _nameController;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final validationError = validateGroupName(name);
    if (validationError != null) {
      setState(() => _errorText = validationError);
      return;
    }

    if (name == widget.currentName.trim()) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _errorText = null;
      _isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('You need to sign in before renaming a group.');
      }

      final groups = await FirebaseFirestore.instance
          .collection('groups')
          .where('createdBy', isEqualTo: user.uid)
          .get();
      final normalizedName = name.toLowerCase();
      final duplicateExists = groups.docs.any((document) {
        if (document.id == widget.groupId) return false;
        final data = document.data();
        final existingName = (data['name'] as String? ?? '')
            .trim()
            .toLowerCase();
        return existingName == normalizedName;
      });

      if (duplicateExists) {
        if (mounted) {
          setState(() {
            _errorText = 'You already have a group with this name';
            _isSaving = false;
          });
        }
        return;
      }

      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .update({'name': name});

      if (mounted) Navigator.of(context).pop(name);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              networkAwareErrorMessage(error, action: 'rename this group'),
            ),
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit group name'),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        enabled: !_isSaving,
        maxLength: maximumGroupNameLength,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
        onSubmitted: (_) {
          if (!_isSaving) _save();
        },
        decoration: InputDecoration(
          labelText: 'Group name',
          hintText: 'e.g. Penang trip',
          errorText: _errorText,
          prefixIcon: const Icon(Icons.edit_outlined),
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
