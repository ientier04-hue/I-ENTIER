import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/diagnostic_assessment.dart';

void main() {
  const engine = AssessmentEngine();

  test('les parcours utilisent le contenu v4 enrichi', () {
    expect(assessmentPathways, hasLength(14));
    expect(assessmentPathways.every((p) => p.version == 4), isTrue);
    expect(assessmentPathways.expand((p) => p.questions), hasLength(162));
    expect(
      assessmentPathways
          .expand((p) => p.questions)
          .expand((q) => q.options)
          .length,
      greaterThanOrEqualTo(912),
    );
    for (final pathway in assessmentPathways) {
      final restored = assessmentPathwayFromMap(
        assessmentPathwayToMap(pathway),
        version: pathway.version,
      );
      expect(assessmentPathwayToMap(restored), assessmentPathwayToMap(pathway));
    }
  });

  final urgencyCases =
      <
        ({
          String name,
          String pathway,
          Map<String, String> answers,
          AssessmentUrgency urgency,
        })
      >[
        (
          name: 'vomissement de sang',
          pathway: 'abdominal',
          answers: {'abdominal_warning': 'blood_vomit'},
          urgency: AssessmentUrgency.emergency,
        ),
        (
          name: 'diabète et vomissements',
          pathway: 'abdominal',
          answers: {'abdominal_warning': 'diabetes_vomit'},
          urgency: AssessmentUrgency.emergency,
        ),
        (
          name: 'migration en fosse iliaque droite',
          pathway: 'abdominal',
          answers: {'abdominal_evolution': 'migration_right'},
          urgency: AssessmentUrgency.consultationToday,
        ),
        (
          name: 'céphalée avec douleur à la mastication',
          pathway: 'headache',
          answers: {'headache_context': 'jaw_scalp'},
          urgency: AssessmentUrgency.consultationToday,
        ),
        (
          name: 'saignement incontrôlable',
          pathway: 'menstrual',
          answers: {'menstrual_bleeding_quantity': 'uncontrolled'},
          urgency: AssessmentUrgency.emergency,
        ),
        (
          name: 'saignement horaire sans instabilité déclarée',
          pathway: 'menstrual',
          answers: {'menstrual_bleeding_quantity': 'hourly'},
          urgency: AssessmentUrgency.consultationToday,
        ),
        (
          name: 'fièvre 38 avant trois mois avec toux',
          pathway: 'respiratory',
          answers: {
            'respiratory_age': 'under_3_months',
            'respiratory_temperature': '38',
          },
          urgency: AssessmentUrgency.emergency,
        ),
        (
          name: 'fièvre 39 entre trois et six mois',
          pathway: 'respiratory',
          answers: {
            'respiratory_age': '3_to_6_months',
            'respiratory_temperature': '39',
          },
          urgency: AssessmentUrgency.consultationToday,
        ),
        (
          name: 'température basse du jeune nourrisson',
          pathway: 'fever',
          answers: {
            'fever_age': 'under_3_months',
            'fever_temperature': 'below_36',
          },
          urgency: AssessmentUrgency.emergency,
        ),
        (
          name: 'impossibilité d’avaler la salive',
          pathway: 'respiratory',
          answers: {'respiratory_swallowing': 'cannot_swallow_saliva'},
          urgency: AssessmentUrgency.emergency,
        ),
        (
          name: 'voix étouffée et trismus',
          pathway: 'respiratory',
          answers: {'respiratory_swallowing': 'muffled_voice'},
          urgency: AssessmentUrgency.emergency,
        ),
        (
          name: 'peau douloureuse chaude et gonflée sans fièvre',
          pathway: 'skin',
          answers: {'skin_sensation': 'pain|warm|swollen'},
          urgency: AssessmentUrgency.consultationToday,
        ),
        (
          name: 'douleur cutanée isolée',
          pathway: 'skin',
          answers: {'skin_sensation': 'pain'},
          urgency: AssessmentUrgency.consultationSoon,
        ),
        (
          name: 'jambe gonflée en début de grossesse',
          pathway: 'pregnancy',
          answers: {
            'pregnancy_stage': 'early',
            'pregnancy_leg_symptoms': 'one_leg',
          },
          urgency: AssessmentUrgency.emergency,
        ),
        (
          name: 'fièvre maternelle mesurée à 38',
          pathway: 'pregnancy',
          answers: {'pregnancy_sickness': 'fever'},
          urgency: AssessmentUrgency.emergency,
        ),
        (
          name: 'douleur thoracique qui persiste sans seuil d’attente',
          pathway: 'chest',
          answers: {'chest_duration': 'ongoing'},
          urgency: AssessmentUrgency.emergency,
        ),
        (
          name: 'douleur thoracique irradiée au bras',
          pathway: 'chest',
          answers: {'chest_radiation': 'arm'},
          urgency: AssessmentUrgency.emergency,
        ),
        (
          name: 'échec du traitement urinaire après 48 heures',
          pathway: 'urinary',
          answers: {'urinary_treatment_response': 'not_improving'},
          urgency: AssessmentUrgency.consultationToday,
        ),
        (
          name: 'brûlure urinaire après 65 ans',
          pathway: 'urinary',
          answers: {'urinary_age': '65_plus', 'urinary_main': 'burning'},
          urgency: AssessmentUrgency.consultationToday,
        ),
        (
          name: 'perte de connaissance avec récupération incomplète',
          pathway: 'dizziness',
          answers: {'dizziness_consciousness': 'incomplete'},
          urgency: AssessmentUrgency.emergency,
        ),
        (
          name: 'perte de connaissance brève récupérée',
          pathway: 'dizziness',
          answers: {'dizziness_consciousness': 'recovered'},
          urgency: AssessmentUrgency.consultationSoon,
        ),
        (
          name: 'fièvre sous traitement anticancéreux',
          pathway: 'fever',
          answers: {'fever_medical_context': 'active_cancer_treatment'},
          urgency: AssessmentUrgency.emergency,
        ),
      ];
  for (final scenario in urgencyCases) {
    test(scenario.name, () {
      final result = engine.evaluate(
        assessmentPathwayById(scenario.pathway)!,
        scenario.answers,
      );
      expect(result.urgency, scenario.urgency);
      if (scenario.urgency == AssessmentUrgency.emergency) {
        expect(result.redFlags, isNotEmpty);
        expect(result.selfCare, isEmpty);
      }
    });
  }

  test(
    'une localisation ou un symptôme isolé ne fabrique plus les autres signes',
    () {
      final cases =
          <({String pathway, Map<String, String> answers, Set<String> absent})>[
            (
              pathway: 'abdominal',
              answers: {'abdominal_location': 'upper'},
              absent: {'after_meal', 'heartburn'},
            ),
            (
              pathway: 'abdominal',
              answers: {'abdominal_location': 'diffuse'},
              absent: {'cramps'},
            ),
            (
              pathway: 'headache',
              answers: {'headache_associated': 'light_only'},
              absent: {'nausea'},
            ),
            (
              pathway: 'headache',
              answers: {'headache_neuro': 'confusion'},
              absent: {'seizure'},
            ),
            (
              pathway: 'menstrual',
              answers: {'menstrual_bleeding_pattern': 'between_after_sex'},
              absent: {'postcoital_bleeding'},
            ),
            (
              pathway: 'menstrual',
              answers: {'menstrual_cycle_context': 'stress_weight'},
              absent: {'weight_change', 'intense_exercise'},
            ),
            (
              pathway: 'respiratory',
              answers: {'respiratory_red_flags': 'chills'},
              absent: {'temperature_38', 'temperature_39', 'temperature_40'},
            ),
            (
              pathway: 'respiratory',
              answers: {'respiratory_cough_detail': 'night_reflux'},
              absent: {'reflux_pattern'},
            ),
            (
              pathway: 'skin',
              answers: {'skin_sensation': 'pain'},
              absent: {'warm_skin', 'skin_swelling'},
            ),
            (
              pathway: 'chest',
              answers: {'chest_now': 'severe_breathing'},
              absent: {'cyanosis'},
            ),
            (
              pathway: 'urinary',
              answers: {'urinary_irritation_detail': 'sexual_exposure'},
              absent: {'genital_discharge'},
            ),
            (
              pathway: 'dizziness',
              answers: {'dizziness_associated': 'tinnitus'},
              absent: {'hearing_change'},
            ),
            (
              pathway: 'fever',
              answers: {'fever_temperature': 'below_38'},
              absent: {'temperature_unconfirmed', 'fever'},
            ),
          ];
      for (final scenario in cases) {
        final tags = engine.answerTags(
          assessmentPathwayById(scenario.pathway)!,
          scenario.answers,
        );
        expect(
          tags.intersection(scenario.absent),
          isEmpty,
          reason: scenario.answers.toString(),
        );
      }
    },
  );

  test(
    'l’acidocétose est recherchée avec les signes associés, pas la soif seule',
    () {
      final pathway = assessmentPathwayById('urinary')!;
      final isolated = engine.evaluate(pathway, {
        'urinary_pattern': 'large_thirst',
      });
      final urgent = engine.evaluate(pathway, {
        'urinary_pattern': 'large_thirst',
        'urinary_thirst': 'thirst|vomiting',
      });
      expect(isolated.urgency, AssessmentUrgency.consultationToday);
      expect(
        isolated.matches.map((m) => m.title),
        isNot(contains('Déséquilibre du diabète à exclure en urgence')),
      );
      expect(urgent.urgency, AssessmentUrgency.emergency);
      expect(
        urgent.matches.first.title,
        'Déséquilibre du diabète à exclure en urgence',
      );
    },
  );

  test('la branche soif est accessible et disparaît après correction', () {
    final pathway = assessmentPathwayById('urinary')!;
    final answers = {'urinary_main': 'frequency', 'urinary_volume': 'large'};
    expect(
      engine
          .nextQuestion(pathway, answers, afterQuestionId: 'urinary_volume')
          ?.id,
      'urinary_thirst',
    );
    final corrected = engine.reconcileAnswers(pathway, {
      ...answers,
      'urinary_volume': 'small',
      'urinary_thirst': 'thirst|vomiting',
    });
    expect(corrected.containsKey('urinary_thirst'), isFalse);
    expect(
      engine.evaluate(pathway, corrected).urgency,
      isNot(AssessmentUrgency.emergency),
    );
  });

  test(
    'un post-partum tardif ne déclenche pas les questions de grossesse en cours',
    () {
      final pathway = assessmentPathwayById('pregnancy')!;
      final tags = engine.answerTags(pathway, {
        'pregnancy_stage': 'postpartum_late',
      });
      expect(
        pathway.questionById('pregnancy_bleeding')!.appliesTo(tags),
        isFalse,
      );
      expect(
        pathway.questionById('pregnancy_postpartum_detail')!.appliesTo(tags),
        isTrue,
      );
    },
  );

  test(
    'les antidouleurs fréquents seuls ne suffisent pas à conclure à une surutilisation',
    () {
      final pathway = assessmentPathwayById('headache')!;
      const title = 'Céphalée par surutilisation médicamenteuse possible';
      final isolated = engine.evaluate(pathway, {
        'headache_medicine_days': '15_plus',
      });
      final combined = engine.evaluate(pathway, {
        'headache_frequency': 'frequent_medicine',
        'headache_medicine_days': '15_plus',
      });
      expect(isolated.matches.map((m) => m.title), isNot(contains(title)));
      expect(combined.matches.map((m) => m.title), contains(title));
    },
  );
}
