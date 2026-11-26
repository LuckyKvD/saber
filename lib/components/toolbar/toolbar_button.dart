import 'package:material_ui/material_ui.dart';

class ToolbarIconButton extends StatelessWidget {
  const new({
    super.key,
    this.tooltip,
    this.selected = false,
    this.enabled = true,
    required this.onPressed,
    required this.padding,
    required this.child,
    this.compact = false,
    this.tinted = false,
  });

  /// Schmale Variante (kleineres Symbol, weniger Innenabstand).
  final bool compact;

  /// Symbol hat eine eigene Farbe: gewählt wird dann mit Rahmen statt
  /// Vollfläche markiert, damit die Symbolfarbe lesbar bleibt.
  final bool tinted;

  final String? tooltip;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final backgroundColor = WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled) ||
          !states.contains(WidgetState.selected)) {
        return Colors.transparent;
      }
      return tinted ? colorScheme.secondaryContainer : colorScheme.primary;
    });
    final foregroundColor = WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colorScheme.onSurface.withValues(alpha: 0.4);
      }
      if (states.contains(WidgetState.selected)) {
        return colorScheme.onPrimary;
      }
      return colorScheme.primary;
    });
    final buttonStyle = ButtonStyle(
      backgroundColor: backgroundColor,
      iconColor: foregroundColor,
      foregroundColor: foregroundColor,
      iconSize: WidgetStatePropertyAll(compact ? 18 : 20),
      minimumSize: WidgetStatePropertyAll(Size.square(compact ? 30 : 36)),
      padding: WidgetStatePropertyAll(EdgeInsets.all(compact ? 6 : 8)),
      side: tinted
          ? WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected) &&
                  !states.contains(WidgetState.disabled)) {
                return BorderSide(color: colorScheme.primary, width: 2);
              }
              return BorderSide.none;
            })
          : null,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Padding(
      padding: padding,
      child: IconButton.filled(
        style: buttonStyle,
        onPressed: (enabled) ? onPressed : null,
        tooltip: tooltip,
        isSelected: selected,
        icon: child,
      ),
    );
  }
}
