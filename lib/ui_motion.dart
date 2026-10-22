import 'package:flutter/material.dart';

bool uiElementAnimationsEnabled = true;

Duration motionDuration(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// Pointer feedback observes input without taking gestures from scroll views.

class MotionPress extends StatefulWidget {
  const MotionPress({super.key, required this.child, this.enabled = true});

  final Widget child;

  final bool enabled;

  @override
  State<MotionPress> createState() => _MotionPressState();
}

class _MotionPressState extends State<MotionPress> {
  bool pressed = false;

  bool hovering = false;

  void _press(bool value) {
    if (pressed != value && mounted) setState(() => pressed = value);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hovering = true),

    onExit: (_) => setState(() {
      hovering = false;

      pressed = false;
    }),

    child: Listener(
      onPointerDown: widget.enabled ? (_) => _press(true) : null,

      onPointerUp: (_) => _press(false),

      onPointerCancel: (_) => _press(false),

      onPointerMove: (event) {
        if (event.delta.distance > 3) _press(false);
      },

      child: AnimatedScale(
        scale: !widget.enabled || MediaQuery.disableAnimationsOf(context)
            ? 1
            : pressed
            ? .975
            : hovering
            ? 1.008
            : 1,

        duration: motionDuration(context, pressed ? 90 : 240),

        curve: pressed ? Curves.easeOutCubic : Curves.easeOutBack,

        child: widget.child,
      ),
    ),
  );
}

/// Small, staggered entrances. Existing children and scroll state stay mounted.

class MotionEntrance extends StatefulWidget {
  const MotionEntrance({
    super.key,

    required this.child,

    this.order = 0,

    this.active = true,
  });

  final Widget child;

  final int order;

  final bool active;

  @override
  State<MotionEntrance> createState() => _MotionEntranceState();
}

class _MotionEntranceState extends State<MotionEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,

    duration: const Duration(milliseconds: 420),
  );

  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (MediaQuery.disableAnimationsOf(context) ||
        !uiElementAnimationsEnabled) {
      controller.value = 1;
    } else if (!initialized) {
      if (widget.active) controller.forward();
    }

    initialized = true;
  }

  @override
  void didUpdateWidget(MotionEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.active && !oldWidget.active) {
      if (MediaQuery.disableAnimationsOf(context) ||
          !uiElementAnimationsEnabled) {
        controller.value = 1;
      } else {
        controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!uiElementAnimationsEnabled ||
        MediaQuery.disableAnimationsOf(context)) {
      return Opacity(opacity: 1, child: widget.child);
    }

    final start = (widget.order.clamp(0, 5) * .07);

    final curve = Interval(start, 1, curve: Curves.easeOutCubic);

    return AnimatedBuilder(
      animation: controller,

      child: widget.child,

      builder: (context, child) {
        final progress = curve.transform(controller.value);

        if (progress >= 1) {
          return Opacity(opacity: 1, child: child);
        }

        return Opacity(
          opacity: .3 + .7 * progress,

          child: Transform.translate(
            offset: Offset(0, 14 * (1 - progress)),

            child: child,
          ),
        );
      },
    );
  }
}

/// Stable alignment prevents song and icon changes from shifting neighbours.

class MotionSwap extends StatelessWidget {
  const MotionSwap({super.key, required this.identity, required this.child});

  final Object identity;

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: motionDuration(context, 260),

    reverseDuration: motionDuration(context, 160),

    switchInCurve: Curves.easeOutCubic,

    switchOutCurve: Curves.easeInCubic,

    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.centerLeft,

      children: [...previous, ?current],
    ),

    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,

      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .12),

          end: Offset.zero,
        ).animate(animation),

        child: child,
      ),
    ),

    child: KeyedSubtree(key: ValueKey(identity), child: child),
  );
}
