import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/child_profile.dart';
import '../services/api_client.dart';
import '../widgets/feedback_ui.dart';

/// Create a child profile, or edit/delete an existing one.
/// Pops with `true` when something was saved or deleted.
class ChildProfileScreen extends StatefulWidget {
  const ChildProfileScreen({super.key, this.existing});

  final ChildProfile? existing;

  @override
  State<ChildProfileScreen> createState() => _ChildProfileScreenState();
}

class _ChildProfileScreenState extends State<ChildProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  DateTime? _birthDate;
  late final Set<String> _interests;
  bool _saving = false;
  bool _showInterestError = false;
  bool _showBirthDateError = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _birthDate = c?.birthDate;
    _interests = {...?c?.interests};
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  int _monthsOld(DateTime birth) {
    final now = DateTime.now();
    var months = (now.year - birth.year) * 12 + now.month - birth.month;
    if (now.day < birth.day) months--;
    return months < 0 ? 0 : months;
  }

  Future<void> _pickBirthDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(today.year - 1, today.month, today.day),
      firstDate: DateTime(today.year - 12),
      lastDate: today,
      helpText: 'Child\'s birth date',
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _showBirthDateError = false;
      });
    }
  }

  Future<void> _save() async {
    final formOk = _formKey.currentState!.validate();
    setState(() {
      _showBirthDateError = _birthDate == null;
      _showInterestError = _interests.isEmpty;
    });
    if (!formOk || _birthDate == null || _interests.isEmpty) return;

    final draft = ChildDraft(
      name: _name.text.trim(),
      birthDate: _birthDate!,
      // Keep the canonical order so the profile reads the same everywhere.
      interests: kInterests.where(_interests.contains).toList(),
    );
    setState(() => _saving = true);
    try {
      final api = context.read<ApiClient>();
      if (_isEditing) {
        await api.updateChild(widget.existing!.id, draft);
      } else {
        await api.createChild(draft);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final child = widget.existing!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${child.name}\'s profile?'),
        content: const Text(
            'This also deletes the ratings and comments saved for this child.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await context.read<ApiClient>().deleteChild(child.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final birth = _birthDate;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit profile' : 'New child profile'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Delete profile',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('child-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Child\'s name',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 16),
            InkWell(
              key: const Key('birth-date'),
              onTap: _pickBirthDate,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Birth date',
                  prefixIcon: const Icon(Icons.cake_outlined),
                  suffixIcon: const Icon(Icons.calendar_month_outlined),
                  errorText:
                      _showBirthDateError ? 'Choose a birth date' : null,
                  helperText: birth == null
                      ? 'Used to match activities to your child\'s age'
                      : '${formatAge(_monthsOld(birth))} old',
                ),
                isEmpty: birth == null,
                child: birth == null
                    ? null
                    : Text(DateFormat.yMMMMd().format(birth)),
              ),
            ),
            const SizedBox(height: 24),
            Text('Interests', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Pick everything your child enjoys.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final interest in kInterests)
                  FilterChip(
                    key: Key('interest-$interest'),
                    avatar: _interests.contains(interest)
                        ? null
                        : Icon(interestIcon(interest), size: 18),
                    label: Text(interest),
                    selected: _interests.contains(interest),
                    onSelected: (on) => setState(() {
                      on ? _interests.add(interest) : _interests.remove(interest);
                      if (_interests.isNotEmpty) _showInterestError = false;
                    }),
                  ),
              ],
            ),
            if (_showInterestError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Choose at least one interest',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 32),
            FilledButton.icon(
              key: const Key('save-child'),
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_isEditing ? 'Save changes' : 'Create profile'),
            ),
          ],
        ),
      ),
    );
  }
}
