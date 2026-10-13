import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pageController;
  int _currentPage = 0;
  double _page = 0;
  bool _reduceMotion = false;

  static const _pages = <_OnboardingData>[
    _OnboardingData(
      eyebrow: 'BIENVENUE SUR I-ENTIER',
      title: 'Votre santé.\nEnfin réunie.',
      description:
          'Un seul espace pour comprendre, suivre et prendre soin de votre santé au quotidien.',
      imagePath: 'assets/onboarding/health-overview.jpg',
      imageLabel:
          'Une mère et sa fille préparent ensemble un petit-déjeuner équilibré',
      accent: Color(0xFFD8E5C7),
      softAccent: Color(0xFFCCFBF4),
    ),
    _OnboardingData(
      eyebrow: 'TROUVER & CONSULTER',
      title: 'Les bons soins,\nau bon moment.',
      description:
          'Repérez rapidement les professionnels, pharmacies et laboratoires utiles autour de vous.',
      imagePath: 'assets/onboarding/nearby-care.jpg',
      imageLabel:
          'Une pharmacienne accompagne un patient dans une pharmacie de proximité',
      accent: Color(0xFFD8E5C7),
      softAccent: Color(0xFFDDEAFF),
    ),
    _OnboardingData(
      eyebrow: 'SUIVRE & PRÉVENIR',
      title: 'Un suivi qui vous\nressemble vraiment.',
      description:
          'Cycle, bien-être mental, prévention et indicateurs santé : voyez l’essentiel d’un coup d’œil.',
      imagePath: 'assets/onboarding/health-tracking.jpg',
      imageLabel:
          'Une femme prend soin de son bien-être lors d’une activité matinale en plein air',
      accent: Color(0xFFD8E5C7),
      softAccent: Color(0xFFFFDFE8),
    ),
    _OnboardingData(
      eyebrow: 'SIMPLE & SÉCURISÉ',
      title: 'Vous gardez le\ncontrôle.',
      description:
          'Vos informations restent dans votre espace personnel, avec un assistant santé disponible quand vous en avez besoin.',
      imagePath: 'assets/onboarding/private-care.jpg',
      imageLabel:
          'Une patiente échange en confiance avec son médecin dans un cabinet privé',
      accent: Color(0xFFD8E5C7),
      softAccent: Color(0xFFFFEBC8),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(_handlePageScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
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
    super.dispose();
  }

  void _goNext() {
    if (_currentPage == _pages.length - 1) {
      widget.onFinished();
      return;
    }
    if (_reduceMotion) {
      _pageController.jumpToPage(_currentPage + 1);
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToPage(int index) {
    if (_reduceMotion) {
      _pageController.jumpToPage(index);
      return;
    }
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
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 250);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 18, 8),
      child: Row(
        children: [
          const _IntroBrand(),
          const Spacer(),
          AnimatedOpacity(
            opacity: showSkip ? 1 : 0,
            duration: duration,
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
          Icons.add_rounded,
          color: Color(0xFFD8E5C7),
          size: 26,
        ),
      ),
      const SizedBox(width: 10),
      const Text(
        'I-ENTIER',
        style: TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: .7,
        ),
      ),
    ],
  );
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data, required this.progress});

  final _OnboardingData data;
  final double progress;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 820;
      final compactHeight = constraints.maxHeight < 610;
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final visualContent = _OnboardingIllustration(data: data);
      final copyContent = _OnboardingCopy(data: data, centered: !desktop);
      final visual = reduceMotion
          ? visualContent
          : Transform.translate(
              offset: Offset(progress * -34, progress.abs() * 7),
              child: Opacity(
                opacity: (1 - progress.abs() * .36).clamp(0.0, 1.0),
                child: visualContent,
              ),
            );
      final copy = reduceMotion
          ? copyContent
          : Transform.translate(
              offset: Offset(progress * -18, 0),
              child: Opacity(
                opacity: (1 - progress.abs() * .42).clamp(0.0, 1.0),
                child: copyContent,
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
      Text(
        data.eyebrow,
        style: TextStyle(
          color: data.accent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
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
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 16),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Text(
          data.description,
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: const TextStyle(
            color: Color(0xFFC1CDC3),
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
  const _OnboardingIllustration({required this.data});
  final _OnboardingData data;

  @override
  Widget build(BuildContext context) => Center(
    child: AspectRatio(
      aspectRatio: 1.12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.asset(
          data.imagePath,
          fit: BoxFit.cover,
          semanticLabel: data.imageLabel,
          errorBuilder: (context, error, stackTrace) =>
              ColoredBox(color: data.softAccent),
        ),
      ),
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final dotAnimationDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 360);
    final buttonAnimationDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 380);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const hitTargetSize = 48.0;
              final indicatorsWidth = pageCount * hitTargetSize;
              final desiredButtonWidth = lastPage ? 174.0 : 58.0;
              final availableButtonWidth =
                  constraints.maxWidth - indicatorsWidth;
              final buttonWidth = math
                  .min(desiredButtonWidth, math.max(58.0, availableButtonWidth))
                  .toDouble();

              final indicators = SizedBox(
                width: indicatorsWidth,
                height: hitTargetSize,
                child: Row(
                  children: List.generate(pageCount, (index) {
                    final selected = index == currentPage;
                    return Semantics(
                      key: ValueKey('onboarding-dot-$index'),
                      container: true,
                      button: true,
                      selected: selected,
                      label: 'Étape ${index + 1} sur $pageCount',
                      hint: selected
                          ? 'Étape actuelle'
                          : 'Afficher cette étape',
                      onTap: () => onDotTap(index),
                      sortKey: OrdinalSortKey(index.toDouble()),
                      excludeSemantics: true,
                      child: SizedBox.square(
                        dimension: hitTargetSize,
                        child: InkResponse(
                          onTap: () => onDotTap(index),
                          containedInkWell: true,
                          highlightShape: BoxShape.circle,
                          radius: hitTargetSize / 2,
                          child: Center(
                            child: AnimatedContainer(
                              duration: dotAnimationDuration,
                              curve: Curves.easeOutCubic,
                              width: selected ? 28 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: selected
                                    ? accent
                                    : Colors.white.withValues(alpha: .27),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );

              final nextButton = Semantics(
                key: const ValueKey('onboarding-next'),
                container: true,
                button: true,
                label: lastPage
                    ? 'Se connecter'
                    : 'Continuer vers l’étape ${currentPage + 2} sur $pageCount',
                hint: lastPage
                    ? 'Terminer la présentation et ouvrir la connexion'
                    : 'Afficher l’étape suivante',
                onTap: onNext,
                sortKey: OrdinalSortKey(pageCount.toDouble()),
                excludeSemantics: true,
                child: AnimatedContainer(
                  duration: buttonAnimationDuration,
                  width: buttonWidth,
                  height: 58,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
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
                                      fontWeight: FontWeight.w600,
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
              );

              if (constraints.maxWidth < indicatorsWidth + 58) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: indicators),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: nextButton),
                  ],
                );
              }

              return Row(children: [indicators, const Spacer(), nextButton]);
            },
          ),
        ),
      ),
    );
  }
}

class _OnboardingData {
  const _OnboardingData({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.imagePath,
    required this.imageLabel,
    required this.accent,
    required this.softAccent,
  });

  final String eyebrow;
  final String title;
  final String description;
  final String imagePath;
  final String imageLabel;
  final Color accent;
  final Color softAccent;
}

abstract final class _IntroColors {
  static const navy = Color(0xFF1D322A);
}
