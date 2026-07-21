import 'dart:math' as math;

import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _ambientController;
  int _currentPage = 0;
  double _page = 0;

  static const _pages = <_OnboardingData>[
    _OnboardingData(
      eyebrow: 'BIENVENUE SUR I-ENTIER',
      title: 'Votre santé.\nEnfin réunie.',
      description:
          'Un seul espace pour comprendre, suivre et prendre soin de votre santé au quotidien.',
      icon: Icons.all_inclusive_rounded,
      accent: Color(0xFF61E4D8),
      softAccent: Color(0xFFCCFBF4),
      visual: _OnboardingVisual.overview,
    ),
    _OnboardingData(
      eyebrow: 'TROUVER & CONSULTER',
      title: 'Les bons soins,\nau bon moment.',
      description:
          'Repérez rapidement les professionnels, pharmacies et laboratoires utiles autour de vous.',
      icon: Icons.near_me_rounded,
      accent: Color(0xFF72A8FF),
      softAccent: Color(0xFFDDEAFF),
      visual: _OnboardingVisual.nearby,
    ),
    _OnboardingData(
      eyebrow: 'SUIVRE & PRÉVENIR',
      title: 'Un suivi qui vous\nressemble vraiment.',
      description:
          'Cycle, bien-être mental, prévention et indicateurs santé : voyez l’essentiel d’un coup d’œil.',
      icon: Icons.monitor_heart_rounded,
      accent: Color(0xFFFF8CAA),
      softAccent: Color(0xFFFFDFE8),
      visual: _OnboardingVisual.tracking,
    ),
    _OnboardingData(
      eyebrow: 'SIMPLE & SÉCURISÉ',
      title: 'Vous gardez le\ncontrôle.',
      description:
          'Vos informations restent dans votre espace personnel, avec un assistant santé disponible quand vous en avez besoin.',
      icon: Icons.shield_rounded,
      accent: Color(0xFFFFC76A),
      softAccent: Color(0xFFFFEBC8),
      visual: _OnboardingVisual.secure,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(_handlePageScroll);
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  void _handlePageScroll() {
    if (!_pageController.hasClients) return;
    final nextPage = _pageController.page ?? 0;
    if ((nextPage - _page).abs() > .001) {
      setState(() => _page = nextPage);
    }
  }

  @override
  void dispose() {
    _pageController
      ..removeListener(_handlePageScroll)
      ..dispose();
    _ambientController.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_currentPage == _pages.length - 1) {
      widget.onFinished();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentData = _pages[_currentPage];
    return Scaffold(
      backgroundColor: _IntroColors.navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _ambientController,
              builder: (context, _) => CustomPaint(
                painter: _OnboardingBackdropPainter(
                  animation: _ambientController.value,
                  page: _page,
                  accent: currentData.accent,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _OnboardingHeader(
                  onSkip: widget.onFinished,
                  showSkip: _currentPage != _pages.length - 1,
                ),
                Expanded(
                  child: PageView.builder(
                    key: const ValueKey('onboarding-pages'),
                    controller: _pageController,
                    itemCount: _pages.length,
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    itemBuilder: (context, index) => _OnboardingPage(
                      data: _pages[index],
                      progress: (_page - index).clamp(-1.0, 1.0),
                      animation: _ambientController,
                    ),
                  ),
                ),
                _OnboardingControls(
                  currentPage: _currentPage,
                  pageCount: _pages.length,
                  accent: currentData.accent,
                  onDotTap: _goToPage,
                  onNext: _goNext,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({required this.onSkip, required this.showSkip});

  final VoidCallback onSkip;
  final bool showSkip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 12, 18, 8),
    child: Row(
      children: [
        const _IntroBrand(),
        const Spacer(),
        AnimatedOpacity(
          opacity: showSkip ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: ExcludeSemantics(
            excluding: !showSkip,
            child: IgnorePointer(
              key: const ValueKey('skip-onboarding-guard'),
              ignoring: !showSkip,
              child: TextButton(
                key: const ValueKey('skip-onboarding'),
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Passer',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(width: 5),
                    Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _IntroBrand extends StatelessWidget {
  const _IntroBrand();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 39,
        height: 39,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: .16)),
        ),
        child: const Icon(
          Icons.all_inclusive_rounded,
          color: Color(0xFF70E9DF),
          size: 26,
        ),
      ),
      const SizedBox(width: 10),
      const Text(
        'I-ENTIER',
        style: TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: .7,
        ),
      ),
    ],
  );
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.data,
    required this.progress,
    required this.animation,
  });

  final _OnboardingData data;
  final double progress;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 820;
      final compactHeight = constraints.maxHeight < 610;
      final visual = Transform.translate(
        offset: Offset(progress * -34, progress.abs() * 7),
        child: Opacity(
          opacity: (1 - progress.abs() * .36).clamp(0.0, 1.0),
          child: _OnboardingIllustration(data: data, animation: animation),
        ),
      );
      final copy = Transform.translate(
        offset: Offset(progress * -18, 0),
        child: Opacity(
          opacity: (1 - progress.abs() * .42).clamp(0.0, 1.0),
          child: _OnboardingCopy(data: data, centered: !desktop),
        ),
      );

      if (desktop) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Row(
                children: [
                  Expanded(flex: 11, child: visual),
                  const SizedBox(width: 72),
                  Expanded(flex: 9, child: copy),
                ],
              ),
            ),
          ),
        );
      }

      return SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(22, compactHeight ? 0 : 8, 22, 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: compactHeight ? 245 : 305, child: visual),
              SizedBox(height: compactHeight ? 12 : 22),
              copy,
            ],
          ),
        ),
      );
    },
  );
}

class _OnboardingCopy extends StatelessWidget {
  const _OnboardingCopy({required this.data, required this.centered});

  final _OnboardingData data;
  final bool centered;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: data.accent.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: data.accent.withValues(alpha: .28)),
        ),
        child: Text(
          data.eyebrow,
          style: TextStyle(
            color: data.accent,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.35,
          ),
        ),
      ),
      const SizedBox(height: 17),
      Text(
        data.title,
        textAlign: centered ? TextAlign.center : TextAlign.left,
        style: TextStyle(
          color: Colors.white,
          fontSize: centered ? 34 : 48,
          height: 1.04,
          letterSpacing: centered ? -1.1 : -1.7,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 16),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Text(
          data.description,
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: const TextStyle(
            color: Color(0xFFBCD0E5),
            fontSize: 15.5,
            height: 1.5,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    ],
  );
}

class _OnboardingIllustration extends StatelessWidget {
  const _OnboardingIllustration({required this.data, required this.animation});

  final _OnboardingData data;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final wave = math.sin(animation.value * math.pi * 2);
      return Center(
        child: AspectRatio(
          aspectRatio: 1.05,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + wave * .015,
                child: Container(
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        data.accent.withValues(alpha: .22),
                        data.accent.withValues(alpha: .035),
                        Colors.transparent,
                      ],
                      stops: const [0, .63, 1],
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, wave * 5),
                child: _MainVisualCard(data: data),
              ),
              ..._floatingItems(data.visual, data.accent, wave),
            ],
          ),
        ),
      );
    },
  );

  List<Widget> _floatingItems(
    _OnboardingVisual visual,
    Color accent,
    double wave,
  ) => switch (visual) {
    _OnboardingVisual.overview => [
      Positioned(
        left: 5,
        top: 42 + wave * 5,
        child: const _FloatingChip(
          icon: Icons.favorite_rounded,
          label: 'Bien-être',
          color: Color(0xFFFF6B8E),
        ),
      ),
      Positioned(
        right: 0,
        bottom: 50 - wave * 5,
        child: const _FloatingChip(
          icon: Icons.verified_user_rounded,
          label: 'Protégé',
          color: Color(0xFF27C7B8),
        ),
      ),
    ],
    _OnboardingVisual.nearby => [
      Positioned(
        left: 0,
        bottom: 54 + wave * 4,
        child: const _FloatingChip(
          icon: Icons.local_pharmacy_rounded,
          label: 'Pharmacie',
          color: Color(0xFF27C7B8),
        ),
      ),
      Positioned(
        right: 0,
        top: 48 - wave * 4,
        child: const _FloatingChip(
          icon: Icons.biotech_rounded,
          label: 'Laboratoire',
          color: Color(0xFF8A7CFF),
        ),
      ),
    ],
    _OnboardingVisual.tracking => [
      Positioned(
        right: 0,
        top: 46 + wave * 4,
        child: const _FloatingChip(
          icon: Icons.self_improvement_rounded,
          label: 'Équilibre',
          color: Color(0xFF9A7BFF),
        ),
      ),
      Positioned(
        left: 2,
        bottom: 52 - wave * 4,
        child: const _FloatingChip(
          icon: Icons.calendar_month_rounded,
          label: 'Prévention',
          color: Color(0xFFFFB54C),
        ),
      ),
    ],
    _OnboardingVisual.secure => [
      Positioned(
        left: 3,
        top: 48 + wave * 4,
        child: const _FloatingChip(
          icon: Icons.lock_rounded,
          label: 'Privé',
          color: Color(0xFF27C7B8),
        ),
      ),
      Positioned(
        right: 0,
        bottom: 50 - wave * 4,
        child: const _FloatingChip(
          icon: Icons.auto_awesome_rounded,
          label: 'Assistant',
          color: Color(0xFF6E9EFF),
        ),
      ),
    ],
  };
}

class _MainVisualCard extends StatelessWidget {
  const _MainVisualCard({required this.data});

  final _OnboardingData data;

  @override
  Widget build(BuildContext context) => Container(
    width: 224,
    height: 224,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(56),
      border: Border.all(color: Colors.white.withValues(alpha: .2)),
      boxShadow: [
        BoxShadow(
          color: data.accent.withValues(alpha: .16),
          blurRadius: 48,
          spreadRadius: 4,
        ),
        const BoxShadow(
          color: Color(0x38000000),
          blurRadius: 30,
          offset: Offset(0, 18),
        ),
      ],
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          right: -25,
          top: -30,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: data.accent.withValues(alpha: .12),
            ),
          ),
        ),
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: data.softAccent,
            borderRadius: BorderRadius.circular(36),
            boxShadow: [
              BoxShadow(
                color: data.accent.withValues(alpha: .22),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(data.icon, color: _IntroColors.navy, size: 60),
        ),
      ],
    ),
  );
}

class _FloatingChip extends StatelessWidget {
  const _FloatingChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 9, 14, 9),
    decoration: BoxDecoration(
      color: const Color(0xFFF7FAFF),
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x3D001632),
          blurRadius: 22,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 31,
          height: 31,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 9),
        Text(
          label,
          style: const TextStyle(
            color: _IntroColors.navy,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _OnboardingControls extends StatelessWidget {
  const _OnboardingControls({
    required this.currentPage,
    required this.pageCount,
    required this.accent,
    required this.onDotTap,
    required this.onNext,
  });

  final int currentPage;
  final int pageCount;
  final Color accent;
  final ValueChanged<int> onDotTap;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final lastPage = currentPage == pageCount - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Row(
            children: [
              Semantics(
                label: 'Étape ${currentPage + 1} sur $pageCount',
                child: Row(
                  children: List.generate(pageCount, (index) {
                    final selected = index == currentPage;
                    return GestureDetector(
                      key: ValueKey('onboarding-dot-$index'),
                      onTap: () => onDotTap(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 360),
                        curve: Curves.easeOutCubic,
                        width: selected ? 28 : 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? accent
                              : Colors.white.withValues(alpha: .27),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 380),
                width: lastPage ? 174 : 58,
                height: 58,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: .3),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('onboarding-next'),
                    onTap: onNext,
                    borderRadius: BorderRadius.circular(20),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (!lastPage || constraints.maxWidth < 150) {
                          return const Icon(
                            Icons.arrow_forward_rounded,
                            color: _IntroColors.navy,
                            size: 23,
                          );
                        }
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Se connecter',
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: _IntroColors.navy,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              SizedBox(width: 7),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: _IntroColors.navy,
                                size: 23,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingBackdropPainter extends CustomPainter {
  const _OnboardingBackdropPainter({
    required this.animation,
    required this.page,
    required this.accent,
  });

  final double animation;
  final double page;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF07182F), Color(0xFF0A2B52), Color(0xFF073F56)],
          stops: [0, .58, 1],
        ).createShader(rect),
    );

    final phase = animation * math.pi * 2;
    final glow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 85)
      ..color = accent.withValues(alpha: .12);
    canvas.drawCircle(
      Offset(
        size.width * (.2 + math.sin(phase) * .035),
        size.height * (.3 + math.cos(phase) * .03),
      ),
      math.min(size.width, size.height) * .25,
      glow,
    );
    glow.color = const Color(0x1F247BFF);
    canvas.drawCircle(
      Offset(
        size.width * (.85 + math.cos(phase * .7) * .04),
        size.height * (.76 + math.sin(phase * .7) * .03),
      ),
      math.min(size.width, size.height) * .3,
      glow,
    );

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .025)
      ..strokeWidth = 1;
    for (double x = -30; x < size.width + 50; x += 54) {
      canvas.drawLine(
        Offset(x + page * 5, 0),
        Offset(x - 70 + page * 5, size.height),
        grid,
      );
    }

    final particle = Paint();
    for (var index = 0; index < 18; index++) {
      final x = ((index * 47) % 101) / 100 * size.width;
      final baseY = ((index * 73) % 97) / 100 * size.height;
      final y = baseY + math.sin(phase + index) * 7;
      particle.color = Colors.white.withValues(
        alpha: .08 + (math.sin(phase * 1.4 + index) + 1) * .06,
      );
      canvas.drawCircle(Offset(x, y), index % 5 == 0 ? 1.8 : 1, particle);
    }
  }

  @override
  bool shouldRepaint(covariant _OnboardingBackdropPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.page != page ||
      oldDelegate.accent != accent;
}

enum _OnboardingVisual { overview, nearby, tracking, secure }

class _OnboardingData {
  const _OnboardingData({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.softAccent,
    required this.visual,
  });

  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final Color softAccent;
  final _OnboardingVisual visual;
}

abstract final class _IntroColors {
  static const navy = Color(0xFF0B2444);
}
