import 'package:material_ui/material_ui.dart';
import 'package:saber/components/toolbar/tool_setting_chips.dart';
import 'package:saber/data/extensions/axis_extensions.dart';
import 'package:saber/data/prefs.dart';

/// Radierer-Einstellungen direkt in der Leiste: Größe und Modus.
class EraserModal extends StatelessWidget {
  const EraserModal({super.key});

  @override
  Widget build(BuildContext context) {
    final axis = stows.editorToolbarAlignment.value.axis.opposite;
    return Center(
      child: SingleChildScrollView(
        scrollDirection: axis,
        child: Flex(
          direction: axis,
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            ToolSettingChips<int>(
              label: 'Größe',
              pref: stows.eraserSize,
              options: const [
                (5, 'Fein'),
                (10, 'Normal'),
                (20, 'Groß'),
                (35, 'Sehr groß'),
                (60, 'Riesig'),
              ],
            ),
            ToolSettingChips<bool>(
              label: 'Modus',
              pref: stows.eraserPartial,
              options: const [(false, 'Ganze Linie'), (true, 'Teilstrich')],
            ),
          ],
        ),
      ),
    );
  }
}
