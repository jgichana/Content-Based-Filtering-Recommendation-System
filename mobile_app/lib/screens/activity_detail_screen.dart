import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/activity.dart';
import '../models/child_profile.dart';
import '../models/feedback.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../widgets/feedback_ui.dart';
import '../widgets/star_rating.dart';

/// One recommended activity: details, the caregiver's rating, and comments.
class ActivityDetailScreen extends StatefulWidget {
  const ActivityDetailScreen({
    super.key,
    required this.child,
    required this.activity,
    this.onFeedbackChanged,
  });

  final ChildProfile child;
  final RecommendedActivity activity;

  /// Tells the list screen the new rating and comment count.
  final void Function(int? rating, int commentCount)? onFeedbackChanged;

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  final _commentController = TextEditingController();
  int? _rating;
  List<ActivityComment>? _comments;
  ApiException? _error;
  bool _sending = false;

  ApiClient get _api => context.read<ApiClient>();
  String get _activityId => widget.activity.activityId;

  @override
  void initState() {
    super.initState();
    _rating = widget.activity.myRating;
    _load();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _notify() =>
      widget.onFeedbackChanged?.call(_rating, _comments?.length ?? 0);

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final fb = await _api.getFeedback(widget.child.id, _activityId);
      if (!mounted) return;
      setState(() {
        _rating = fb.rating;
        _comments = fb.comments;
      });
      _notify();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _setRating(int? rating) async {
    final previous = _rating;
    setState(() => _rating = rating);
    try {
      if (rating == null) {
        await _api.clearRating(widget.child.id, _activityId);
      } else {
        await _api.rateActivity(widget.child.id, _activityId, rating);
      }
      _notify();
    } catch (e) {
      if (!mounted) return;
      setState(() => _rating = previous);
      showError(context, e);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final comment = await _api.addComment(widget.child.id, _activityId, text);
      if (!mounted) return;
      _commentController.clear();
      setState(() => _comments = [...?_comments, comment]);
      _notify();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(ActivityComment comment) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.deleteComment(comment.id);
      if (!mounted) return;
      setState(() =>
          _comments = _comments?.where((c) => c.id != comment.id).toList());
      _notify();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.activity;
    final myId = context.watch<AuthService>().caregiver?.id;

    return Scaffold(
      appBar: AppBar(title: Text(a.interest)),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _DetailsCard(activity: a),
                  const SizedBox(height: 24),
                  Text('How did ${widget.child.name} like it?',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      StarRating(
                        rating: _rating,
                        size: 40,
                        onChanged: (r) => _setRating(r),
                      ),
                      const Spacer(),
                      if (_rating != null)
                        TextButton(
                          onPressed: () => _setRating(null),
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Comments', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._buildComments(theme, myId),
                ],
              ),
            ),
          ),
          _CommentComposer(
            controller: _commentController,
            sending: _sending,
            onSend: _sendComment,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildComments(ThemeData theme, int? myId) {
    final comments = _comments;
    if (comments == null) {
      if (_error != null) {
        return [
          Text(_error!.message, style: TextStyle(color: theme.colorScheme.error)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _load, child: const Text('Try again')),
          ),
        ];
      }
      return const [
        Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (comments.isEmpty) {
      return [
        Text('No comments yet. Add notes on how the activity went.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ];
    }
    final dateFormat = DateFormat.yMMMd().add_jm();
    return [
      for (final c in comments)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(c.body),
            subtitle: Text('${c.authorName} · ${dateFormat.format(c.createdAt)}'),
            trailing: c.caregiverId == myId
                ? IconButton(
                    tooltip: 'Delete comment',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteComment(c),
                  )
                : null,
          ),
        ),
    ];
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.activity});

  final RecommendedActivity activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: Text(label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
              Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(activity.description, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            row(interestIcon(activity.interest), 'Interest', activity.interest),
            row(Icons.psychology_outlined, 'Develops',
                activity.developmentalArea),
            row(Icons.category_outlined, 'Category', activity.category),
            row(Icons.cake_outlined, 'Suited from',
                formatAge(activity.ageInMonths)),
            if (activity.materialsNeeded != null)
              row(Icons.inventory_2_outlined, 'Materials',
                  activity.materialsNeeded!),
            row(Icons.insights_outlined, 'Match score',
                activity.similarity.toStringAsFixed(2)),
          ],
        ),
      ),
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('comment-field'),
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Add a comment',
                    counterText: '',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                key: const Key('send-comment'),
                tooltip: 'Send',
                onPressed: sending ? null : onSend,
                icon: sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
