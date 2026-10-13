import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/diagnostic_assessment.dart';

AssessmentOption option(
  String id, {
  Set<String> tags = const {},
  String? next,
}) => AssessmentOption(
  id: id,
  label: id,
  icon: Icons.check,
  tags: tags,
  nextQuestionId: next,
);

AssessmentQuestion question(
  String id, {
  Set<String> required = const {},
  Set<String> excluded = const {},
  bool multiple = false,
  List<AssessmentOption>? options,
}) => AssessmentQuestion(
  id: id,
  title: id,
  prompt: id,
  icon: Icons.help_outline,
  requiredTags: required,
  excludedTags: excluded,
  allowMultiple: multiple,
  options: options ?? [option('yes'), option('no')],
);

AssessmentPathway pathway(List<AssessmentQuestion> questions) =>
    AssessmentPathway(
      id: 'navigation',
      title: 'Navigation',
      subtitle: '',
      icon: Icons.account_tree,
      color: Colors.blue,
      questions: questions,
      possibilities: const [],
      selfCare: const [],
    );

void main() {
  const engine = AssessmentEngine();

  test('visite toutes les branches multiples et les questions communes', () {
    final tree = pathway([
      question(
        'root',
        multiple: true,
        options: [
          option('a', tags: {'a'}, next: 'late'),
          option('b', tags: {'b'}, next: 'early'),
        ],
      ),
      question('common'),
      question('early', required: {'b'}),
      question('late', required: {'a'}),
    ]);
    final answers = {'root': 'a|b'};
    expect(
      engine.nextQuestion(tree, answers, afterQuestionId: 'root')?.id,
      'late',
    );
    answers['late'] = 'yes';
    expect(
      engine.nextQuestion(tree, answers, afterQuestionId: 'late')?.id,
      'early',
    );
    answers['early'] = 'yes';
    expect(
      engine.nextQuestion(tree, answers, afterQuestionId: 'early')?.id,
      'common',
    );
    answers['common'] = 'yes';
    expect(
      engine.nextQuestion(tree, answers, afterQuestionId: 'common'),
      isNull,
    );
    expect(engine.answeredQuestions(tree, answers).map((q) => q.id), [
      'root',
      'late',
      'early',
      'common',
    ]);
    expect(engine.progress(tree, answers), 100);
  });

  test('retrouve une question activée avant sa position dans le catalogue', () {
    final tree = pathway([
      question('detail', required: {'active'}),
      question(
        'root',
        options: [
          option('yes', tags: {'active'}),
          option('no'),
        ],
      ),
    ]);
    expect(engine.nextQuestion(tree, {})?.id, 'root');
    expect(
      engine.nextQuestion(tree, {'root': 'yes'}, afterQuestionId: 'root')?.id,
      'detail',
    );
  });

  test('un lien cyclique ne repose jamais une question déjà répondue', () {
    final tree = pathway([
      question(
        'a',
        options: [
          option('yes', next: 'b'),
          option('no'),
        ],
      ),
      question(
        'b',
        options: [
          option('yes', next: 'a'),
          option('no'),
        ],
      ),
      question('c'),
    ]);
    expect(
      engine.nextQuestion(tree, {
        'a': 'yes',
        'b': 'yes',
      }, afterQuestionId: 'b')?.id,
      'c',
    );
    expect(
      engine.nextQuestion(tree, {'a': 'yes', 'b': 'yes', 'c': 'yes'}),
      isNull,
    );
  });

  test(
    'retire les descendants abandonnés et conserve les réponses indépendantes',
    () {
      final tree = pathway([
        question(
          'root',
          options: [
            option('yes', tags: {'branch'}),
            option('no'),
          ],
        ),
        question(
          'child',
          required: {'branch'},
          options: [
            option('yes', tags: {'leaf'}),
            option('no'),
          ],
        ),
        question('leaf', required: {'leaf'}),
        question('common'),
      ]);
      final answers = {
        'root': 'no',
        'child': 'yes',
        'leaf': 'yes',
        'common': 'no',
      };
      expect(engine.reconcileAnswers(tree, answers), {
        'root': 'no',
        'common': 'no',
      });
      expect(engine.nextQuestion(tree, answers), isNull);
      expect(engine.progress(tree, answers), 100);
    },
  );

  test('une branche ne se maintient pas avec ses propres réponses', () {
    final tree = pathway([
      question('root'),
      question(
        'a',
        required: {'b'},
        options: [
          option('yes', tags: {'a'}),
          option('no'),
        ],
      ),
      question(
        'b',
        required: {'a'},
        options: [
          option('yes', tags: {'b'}),
          option('no'),
        ],
      ),
    ]);
    expect(
      engine.reconcileAnswers(tree, {'root': 'yes', 'a': 'yes', 'b': 'yes'}),
      {'root': 'yes'},
    );
  });

  test('propage les exclusions aux descendants', () {
    final tree = pathway([
      question(
        'root',
        options: [
          option('yes', tags: {'exclude'}),
          option('no'),
        ],
      ),
      question(
        'child',
        excluded: {'exclude'},
        options: [
          option('yes', tags: {'leaf'}),
          option('no'),
        ],
      ),
      question('leaf', required: {'leaf'}),
    ]);
    expect(
      engine.reconcileAnswers(tree, {
        'root': 'yes',
        'child': 'yes',
        'leaf': 'yes',
      }),
      {'root': 'yes'},
    );
  });

  test('les réponses invalides ne gonflent pas la progression', () {
    final tree = pathway([question('a'), question('b')]);
    expect(
      engine.progress(tree, {'a': 'yes', 'b': 'removed', 'unknown': 'yes'}),
      50,
    );
    expect(engine.nextQuestion(tree, {'a': 'yes', 'b': 'yes|no'})?.id, 'b');
    expect(engine.progress(tree, {'a': '', 'unknown': 'yes'}), 0);
  });

  test('les parcours publiés rejettent les liens et identifiants ambigus', () {
    final invalidTrees = [
      pathway([question('a'), question('a')]),
      pathway([
        question('a', options: [option('yes'), option('yes')]),
      ]),
      pathway([
        question(
          'a',
          options: [
            option('yes', next: 'missing'),
            option('no'),
          ],
        ),
      ]),
      pathway([
        question(
          'a',
          options: [
            option('yes', next: 'a'),
            option('no'),
          ],
        ),
      ]),
      pathway([
        question('a', options: [option('yes|no'), option('no')]),
      ]),
      pathway([
        question('a', required: {'branch'}, excluded: {'branch'}),
      ]),
      pathway([
        question('a', required: {'missing'}),
      ]),
    ];
    for (final tree in invalidTrees) {
      expect(
        () => assessmentPathwayFromMap(assessmentPathwayToMap(tree)),
        throwsFormatException,
      );
    }
  });

  test(
    'les dix parcours terminent sans répéter ni oublier une branche active',
    () {
      final random = Random(42);
      for (final tree in assessmentPathways) {
        for (var run = 0; run < 50; run++) {
          final answers = <String, String>{};
          String? previous;
          while (true) {
            final next = engine.nextQuestion(
              tree,
              answers,
              afterQuestionId: previous,
            );
            if (next == null) break;
            expect(
              answers.containsKey(next.id),
              isFalse,
              reason: '${tree.id}/${next.id}',
            );
            final selected = next.options[random.nextInt(next.options.length)];
            answers[next.id] = selected.id;
            previous = next.id;
            expect(answers.length, lessThanOrEqualTo(tree.questions.length));
          }
          final active = engine.reconcileAnswers(tree, answers);
          final tags = engine.answerTags(tree, active);
          expect(
            tree.questions
                .where((q) => q.appliesTo(tags))
                .map((q) => q.id)
                .toSet(),
            active.keys.toSet(),
          );
          expect(engine.progress(tree, answers), 100);
        }
      }
    },
  );
}
