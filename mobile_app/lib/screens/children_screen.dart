import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/child_profile.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../widgets/feedback_ui.dart';
import 'child_profile_screen.dart';
import 'recommendations_screen.dart';

/// Home screen: the caregiver's child profiles.
class ChildrenScreen extends StatefulWidget {
  const ChildrenScreen({super.key});

  @override
  State<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends State<ChildrenScreen> {
  List<ChildProfile>? _children;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final children = await context.read<ApiClient>().listChildren();
      if (mounted) setState(() => _children = children);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openProfile([ChildProfile? child]) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ChildProfileScreen(existing: child),
    ));
    if (changed == true) _load();
  }

  void _openRecommendations(ChildProfile child) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecommendationsScreen(child: child),
    ));
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true && mounted) await context.read<AuthService>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final caregiver = context.watch<AuthService>().caregiver;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My children'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (v) {
              if (v == 'signout') _confirmSignOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(caregiver?.name ?? ''),
                  subtitle: Text(caregiver?.email ?? ''),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'signout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout),
                  title: Text('Sign out'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: (_children?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => _openProfile(),
              icon: const Icon(Icons.add),
              label: const Text('Add child'),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _children == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _children == null) {
      return MessageView(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load profiles',
        message: _error!.message,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }
    final children = _children ?? const [];
    if (children.isEmpty) {
      return MessageView(
        icon: Icons.child_friendly_outlined,
        title: 'Add your first child',
        message:
            'Create a profile with your child\'s birth date and interests to get activity ideas.',
        actionLabel: 'Create child profile',
        onAction: () => _openProfile(),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _ChildCard(
          child: children[i],
          onTap: () => _openRecommendations(children[i]),
          onEdit: () => _openProfile(children[i]),
        ),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({
    required this.child,
    required this.onTap,
    required this.onEdit,
  });

  final ChildProfile child;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  child.name.characters.first.toUpperCase(),
                  style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(child.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(formatAge(child.ageInMonths),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: child.interests.isEmpty
                          ? [
                              Text('No interests yet',
                                  style: theme.textTheme.bodySmall)
                            ]
                          : [
                              for (final i in child.interests)
                                Chip(
                                  avatar: Icon(interestIcon(i), size: 16),
                                  label: Text(i),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                            ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    tooltip: 'Edit profile',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
