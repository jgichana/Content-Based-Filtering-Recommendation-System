/// One activity returned by POST /recommend (ranked by
/// backend/activity_recommender.py), plus the signed-in caregiver's feedback
/// for this child.
class RecommendedActivity {
  const RecommendedActivity({
    required this.activityId,
    required this.ageInMonths,
    required this.description,
    required this.category,
    required this.interest,
    required this.developmentalArea,
    required this.similarity,
    this.materialsNeeded,
    this.myRating,
    this.commentCount = 0,
  });

  final String activityId;
  final int ageInMonths;
  final String description;
  final String category;
  final String interest;
  final String developmentalArea;
  final String? materialsNeeded;

  /// Cosine similarity between the child's interests and the activity.
  final double similarity;
  final int? myRating;
  final int commentCount;

  factory RecommendedActivity.fromJson(Map<String, dynamic> json) {
    final materials = (json['materials_needed'] as String?)?.trim();
    return RecommendedActivity(
      activityId: json['activity_id'] as String,
      ageInMonths: json['age_in_months'] as int,
      description: json['activity_description'] as String,
      category: json['category'] as String,
      interest: json['interest'] as String,
      developmentalArea: json['target_developmental_area'] as String,
      materialsNeeded:
          (materials == null || materials.isEmpty || materials == 'nan')
              ? null
              : materials,
      similarity: (json['similarity'] as num).toDouble(),
      myRating: json['my_rating'] as int?,
      commentCount: json['comment_count'] as int? ?? 0,
    );
  }

  RecommendedActivity withFeedback({
    required int? rating,
    required int commentCount,
  }) =>
      RecommendedActivity(
        activityId: activityId,
        ageInMonths: ageInMonths,
        description: description,
        category: category,
        interest: interest,
        developmentalArea: developmentalArea,
        materialsNeeded: materialsNeeded,
        similarity: similarity,
        myRating: rating,
        commentCount: commentCount,
      );
}

class RecommendationResult {
  const RecommendationResult({
    required this.childName,
    required this.ageInMonths,
    required this.interestsUsed,
    required this.activities,
  });

  final String childName;
  final int ageInMonths;
  final List<String> interestsUsed;
  final List<RecommendedActivity> activities;

  factory RecommendationResult.fromJson(Map<String, dynamic> json) =>
      RecommendationResult(
        childName: json['child_name'] as String,
        ageInMonths: json['age_in_months'] as int,
        interestsUsed: List<String>.from(json['interests_used'] as List),
        activities: (json['results'] as List)
            .map((e) =>
                RecommendedActivity.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
