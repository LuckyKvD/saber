import 'dart:async';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/security/app_lock.dart';

/// Kurze Einblendung beim Start: Feder, Fork von Saber, Urheber und Mitwirkende.
/// Verschwindet nach ein paar Sekunden oder per Tipp. Nur einmal pro Start.
class FederSplash extends StatefulWidget {
  const new({super.key, required this.child});

  final Widget child;

  static var _shown = false;

  @override
  State<FederSplash> createState() => _FederSplashState();
}

class _FederSplashState extends State<FederSplash> {
  var visible = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    if (FederSplash._shown) return;
    if (AppLock.isLocked.value) {
      // Erst nach dem Entsperren (Fingerabdruck) zeigen.
      AppLock.isLocked.addListener(_onLockChanged);
    } else {
      FederSplash._shown = true;
      visible = true;
      timer = Timer(const Duration(milliseconds: 4800), _hide);
    }
  }

  void _onLockChanged() {
    if (AppLock.isLocked.value) return;
    AppLock.isLocked.removeListener(_onLockChanged);
    _show();
  }

  void _show() {
    if (FederSplash._shown || !mounted) return;
    FederSplash._shown = true;
    setState(() => visible = true);
    timer = Timer(const Duration(milliseconds: 4800), _hide);
  }

  void _hide() {
    if (mounted && visible) setState(() => visible = false);
  }

  @override
  void dispose() {
    AppLock.isLocked.removeListener(_onLockChanged);
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        Positioned.fill(child: widget.child),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 600),
              child: GestureDetector(
                onTap: _hide,
                child: const _SplashContent(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SplashContent extends StatelessWidget {
  const _SplashContent();

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE3B84B);
    const textStyle = TextStyle(
      color: Color(0xFFD9DFEA),
      fontSize: 16,
      height: 1.5,
      decoration: TextDecoration.none,
      fontWeight: FontWeight.w400,
    );
    return ColoredBox(
      color: const Color(0xFF0B1A33),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset('assets/icon/icon.svg', width: 140, height: 140),
                const SizedBox(height: 20),
                const Text(
                  'Feder',
                  style: TextStyle(
                    color: gold,
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ein Fork von Saber',
                  style: textStyle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Saber von Adil Hanney und allen Mitwirkenden\nMit großem Dank an das Saber-Team',
                  style: textStyle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Idee & Veränderung: LuckyKvD\nAusführung: Claude',
                  style: TextStyle(
                    color: gold,
                    fontSize: 16,
                    height: 1.5,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
