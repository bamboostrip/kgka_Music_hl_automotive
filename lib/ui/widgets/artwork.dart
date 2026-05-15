import 'package:flutter/material.dart';

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    this.url,
    required this.size,
    this.borderRadius = 8,
    this.icon = Icons.music_note_rounded,
  });

  final String? url;
  final double size;
  final double borderRadius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageUrl = url;
    final child = imageUrl == null
        ? _Fallback(icon: icon)
        : Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _Fallback(icon: icon),
            loadingBuilder: (context, child, progress) {
              if (progress == null) {
                return child;
              }
              return ColoredBox(
                color: colorScheme.surfaceContainerHighest,
                child: Center(
                  child: SizedBox.square(
                    dimension: size.isFinite ? size * .22 : 28,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: size.isFinite
          ? SizedBox.square(dimension: size, child: child)
          : SizedBox.expand(child: child),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: Icon(icon, color: colorScheme.onPrimaryContainer, size: 28),
    );
  }
}
