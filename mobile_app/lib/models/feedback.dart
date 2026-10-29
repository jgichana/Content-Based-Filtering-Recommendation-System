class ActivityComment {
  const ActivityComment({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.caregiverId,
    required this.authorName,
  });

  final int id;
  final String body;
  final DateTime createdAt;
  final int caregiverId;
  final String authorName;

  factory ActivityComment.fromJson(Map<String, dynamic> json) =>
      ActivityComment(
        id: json['comment_id'] as int,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        caregiverId: json['caregiver_id'] as int,
        authorName: json['author_name'] as String,
      );
}

class ActivityFeedback {
  const ActivityFeedback({this.rating, this.comments = const []});

  final int? rating;
  final List<ActivityComment> comments;

  factory ActivityFeedback.fromJson(Map<String, dynamic> json) =>
      ActivityFeedback(
        rating: json['rating'] as int?,
        comments: (json['comments'] as List? ?? const [])
            .map((e) => ActivityComment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
