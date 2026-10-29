import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/activity.dart';
import '../models/child_profile.dart';
import '../services/api_client.dart';
import '../widgets/feedback_ui.dart';
import '../widgets/star_rating.dart';
import 'activity_detail_screen.dart';

/// Activities recommended for one child by the content-based model, with
/// quick rating and a link to comments.
class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key, required this.child});

  final ChildProfile child;

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  static const _countOptions = [5, 10, 20];

  late Set<String> _interests;
  int _count = 5;
  List<RecommendedActivity>? _activities;
  ApiException? _error;
  bool _loading = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _interests = {...widget.child.interests};
    if (_interests.isEmpty) _interests = {kInterests.first};
    _load();
  }

  Future<void> _load() async {
    final requestId = ++_requestId; // ignore responses to superseded requests
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context.read<ApiClient>().recommend(
            widget.child.id,
            k: _count,
            interests: kInterests.where(_interests.contains).toList(),
          );
      if (mounted && requestId == _requestId) {
        setState(() => _activities = result.activities);
      }
    } on ApiException catch (e) {
      if (mounted && requestId == _requestId) setState(() => _error = e);
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  void _toggleInterest(String interest, bool on) {
    if (!on && _interests.length == 1) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Keep at least one interest selected')));
      return;
    }
    setState(() => on ? _interests.add(interest) : _interests.remove(interest));
    _load();
  }

  void _replace(RecommendedActivity updated) {
    final list = _activities;
    if (list == null) return;
    final i = list.indexWhere((a) => a.activityId == updated.activityId);
    if (i == -1) return;
    setState(() => _activities = [...list]..[i] = updated);
  }

  Future<void> _rate(RecommendedActivity activity, int rating) async {
    final previous = activity;
    _replace(activity.withFeedback(
        rating: rating, commentCount: activity.commentCount)); // optimistic
    try {
      await context
          .read<ApiClient>()
          .rateActivity(widget.child.id, activity.activityId, rating);
    } catch (e) {
      _replace(previous);
      if (mounted) showError(context, e);
    }
  }

  void _openDetail(RecommendedActivity activity) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ActivityDetailScreen(
        child: widget.child,
        activity: activity,
        onFeedbackChanged: (rating, count) => _replace(
            activity.withFeedback(rating: rating, commentCount: count)),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Activities for ${widget.child.name}'),
            Text(formatAge(widget.child.ageInMonths),
                style: theme.textTheme.bodySmall),
          ],
        ),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'How many activities',
            initialValue: _count,
            icon: const Icon(Icons.tune),
            onSelected: (v) {
              setState(() => _count = v);
              _load();
            },
            itemBuilder: (_) => [
              for (final n in _countOptions)
                CheckedPopupMenuItem(
                    value: n, checked: n == _count, child: Text('Show $n')),
            ],
          ),
        ],
        bottom: _loading && _activities != null
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator())
            : null,
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final interest in kInterests)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(interest),
                      selected: _interests.contains(interest),
                      onSelected: (on) => _toggleInterest(interest, on),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    final activities = _activities;
    if (activities == null) {
      if (_error != null) {
        return MessageView(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load activities',
          message: _error!.message,
          actionLabel: 'Try again',
          onAction: _load,
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final selected = kInterests.where(_interests.contains).join(', ');
    final age = formatAge(widget.child.ageInMonths);
    if (activities.isEmpty) {
      return MessageView(
        icon: Icons.search_off,
        title: 'No matching activities',
        message:
            'There are no $selected activities for $age. Try selecting other interests.',
      );
    }
    // Results are strictly limited to the selected interests, so there may be
    // fewer than requested.
    final showAllNote = activities.length < _count;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: activities.length + (showAllNote ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (i == activities.length) {
            return Padding(
              key: const Key('all-shown-note'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'That\'s all ${activities.length} $selected '
                '${activities.length == 1 ? 'activity' : 'activities'} for $age.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            );
          }
          return ActivityCard(
            rank: i + 1,
            activity: activities[i],
            onTap: () => _openDetail(activities[i]),
            onRate: (r) => _rate(activities[i], r),
          );
        },
      ),
    );
  }
}

class ActivityCard extends StatelessWidget {
  const ActivityCard({
    super.key,
    required this.rank,
    required this.activity,
    required this.onTap,
    required this.onRate,
  });

  final int rank;
  final RecommendedActivity activity;
  final VoidCallback onTap;
  final ValueChanged<int> onRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: theme.colorScheme.primary,
                    child: Text('$rank',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.onPrimary)),
                  ),
                  const SizedBox(width: 10),
                  Icon(interestIcon(activity.interest),
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(activity.interest, style: theme.textTheme.labelLarge),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      activity.developmentalArea,
                      style: muted,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(activity.description, style: theme.textTheme.bodyLarge),
              if (activity.materialsNeeded != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(activity.materialsNeeded!, style: muted)),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  StarRating(
                    rating: activity.myRating,
                    onChanged: onRate,
                    size: 26,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(activity.commentCount == 0
                        ? 'Comment'
                        : '${activity.commentCount}'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
