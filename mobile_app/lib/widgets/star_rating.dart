import 'package:flutter/material.dart';

/// 1-5 star rating. Read-only when [onChanged] is null.
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.rating,
    this.onChanged,
    this.size = 28,
  });

  final int? rating;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Colors.amber.shade700;
    final value = rating ?? 0;
    return Semantics(
      label: rating == null ? 'Not rated' : 'Rated $value out of 5',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final star = i + 1;
          final icon = Icon(
            star <= value ? Icons.star_rounded : Icons.star_outline_rounded,
            color: star <= value ? color : Theme.of(context).disabledColor,
            size: size,
          );
          if (onChanged == null) return icon;
          return InkResponse(
            key: ValueKey('star-$star'),
            radius: size * 0.8,
            onTap: () => onChanged!(star),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Semantics(
                button: true,
                label: 'Rate $star star${star == 1 ? '' : 's'}',
                child: icon,
              ),
            ),
          );
        }),
      ),
    );
  }
}
