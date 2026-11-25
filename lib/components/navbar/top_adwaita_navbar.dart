import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/routes.dart';

const _navy = Color(0xFF0B1A33);
const _gold = Color(0xFFE3B84B);

class const TopAdwaitaNavbar({
  super.key,
  final int selectedIndex = 0,
  final ValueChanged<int>? onDestinationSelected,
}) extends StatelessWidget implements PreferredSizeWidget {
  @override
  Widget build(BuildContext context) {
    final routes = HomeRoutes.routes;
    final screenSize = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ColoredBox(
        color: _navy,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, topInset + 14, 14, 12),
          child: Semantics(
        role: SemanticsRole.tabBar,
        explicitChildNodes: true,
        container: true,
        child: Center(
          child: SizedBox(
            width: screenSize.width < 340 * routes.length
                ? double.infinity
                : 280.0 * routes.length,
            child: Row(
              mainAxisAlignment: .center,
              spacing: 3,
              children: [
                for (int i = 0; i < routes.length; ++i)
                  Expanded(
                    child: _Tab(
                      route: routes[i],
                      selected: i == selectedIndex,
                      onTap: () => onDestinationSelected?.call(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size(double.infinity, 46);
}

class const _Tab({
  required final HomeRoute route,
  required final bool selected,
  required final VoidCallback? onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        role: SemanticsRole.tab,
        selected: selected,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: selected ? _gold : Colors.transparent,
            foregroundColor: selected ? _navy : const Color(0xFFD9DFEA),
            iconColor: selected ? _navy : const Color(0xFFD9DFEA),
            iconSize: 28,
            minimumSize: const Size(0, 58),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            overlayColor: selected ? Colors.transparent : null,
          ),
          child: _TabContent(route: route),
        ),
      ),
    );
  }
}

class const _TabContent({required final HomeRoute route})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: .min,
      spacing: 8,
      children: [
        route.destination.icon,
        Text(
          route.destination.label,
          style: const TextStyle(fontWeight: .w600, fontSize: 19),
        ),
      ],
    );
  }
}
