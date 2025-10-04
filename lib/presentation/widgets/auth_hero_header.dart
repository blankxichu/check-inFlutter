import 'package:flutter/material.dart';

class AuthHeroHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double height;
  const AuthHeroHeader({super.key, required this.title, this.subtitle, this.height = 140});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Tweak contrast per mode: in dark, lower saturation but slightly higher opacity for visibility
    final start = cs.primary.withOpacity(isDark ? 0.10 : 0.18);
    final end = cs.secondary.withOpacity(isDark ? 0.12 : 0.16);
    final circlePrimaryOpacity = isDark ? 0.12 : 0.08;
    final circleTertiaryOpacity = isDark ? 0.10 : 0.08;
    final iconOverlayOpacity = isDark ? 0.30 : 0.25;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [start, end],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop decorative circles
            Positioned(
              top: -20,
              left: -20,
              child: _circle(cs.primary, 120, circlePrimaryOpacity),
            ),
            Positioned(
              bottom: -30,
              right: -10,
              child: _circle(cs.tertiary, 160, circleTertiaryOpacity),
            ),
            // Thematic icons related to the app: school, calendar, shield
            Positioned(
              top: 18,
              right: 18,
              child: Icon(Icons.calendar_month, color: cs.primary.withOpacity(iconOverlayOpacity), size: 48),
            ),
            Positioned(
              bottom: 16,
              left: 18,
              child: Icon(Icons.shield_outlined, color: cs.secondary.withOpacity(iconOverlayOpacity), size: 56),
            ),
            Positioned(
              bottom: 16,
              right: 72,
              child: Icon(Icons.school_outlined, color: cs.tertiary.withOpacity(isDark ? 0.28 : 0.23), size: 40),
            ),
            // Text content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle(Color color, double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(opacity),
      ),
    );
  }
}
