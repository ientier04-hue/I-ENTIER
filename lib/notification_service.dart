import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

enum AppNotificationType { appointment, result, reminder, security }

class AppNotification {
  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final DateTime? scheduledAt;
  final AppNotificationType type;
  final bool isRead;
  final String? actionLabel;
  final String source;
  final String sourceId;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.type,
    this.scheduledAt,
    this.isRead = false,
    this.actionLabel,
    this.source = 'app',
    this.sourceId = '',
  });

  bool isDeliveredAt(DateTime now) =>
      scheduledAt == null || !scheduledAt!.isAfter(now);

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    title: title,
    message: message,
    createdAt: createdAt,
    scheduledAt: scheduledAt,
    type: type,
    isRead: isRead ?? this.isRead,
    actionLabel: actionLabel,
    source: source,
    sourceId: sourceId,
  );

  static AppNotification? fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) return null;
    final title = (data['title'] as String?)?.trim() ?? '';
    final message = (data['message'] as String?)?.trim() ?? '';
    if (title.isEmpty || message.isEmpty) return null;
    final scheduledAt = _dateFromFirestore(data['scheduledAt']);
    final createdAt =
        _dateFromFirestore(data['createdAt']) ?? scheduledAt ?? DateTime.now();
    return AppNotification(
      id: document.id,
      title: title,
      message: message,
      createdAt: createdAt,
      scheduledAt: scheduledAt,
      type: _notificationTypeFromName(data['type'] as String?),
      isRead: data['isRead'] == true,
      actionLabel: _optionalText(data['actionLabel']),
      source: _optionalText(data['source']) ?? 'app',
      sourceId: _optionalText(data['sourceId']) ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'title': title,
    'message': message,
    'type': type.name,
    'isRead': isRead,
    'createdAt': Timestamp.fromDate(createdAt),
    if (scheduledAt != null) 'scheduledAt': Timestamp.fromDate(scheduledAt!),
    if (actionLabel != null) 'actionLabel': actionLabel,
    'source': source,
    'sourceId': sourceId,
  };
}

DateTime? _dateFromFirestore(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => null,
};

String? _optionalText(Object? value) {
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? null : text;
}

AppNotificationType _notificationTypeFromName(String? value) =>
    AppNotificationType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => AppNotificationType.reminder,
    );

List<AppNotification> defaultAppNotifications([DateTime? referenceTime]) {
  final now = referenceTime ?? DateTime.now();
  return [
    AppNotification(
      id: 'laboratory-result',
      title: 'Vos résultats sont disponibles',
      message:
          'Le laboratoire a publié les résultats de votre dernière analyse.',
      createdAt: now.subtract(const Duration(minutes: 12)),
      type: AppNotificationType.result,
      actionLabel: 'Voir les résultats',
    ),
    AppNotification(
      id: 'appointment-reminder',
      title: 'Rendez-vous demain à 9 h 30',
      message: 'Votre consultation avec Dre Jean est prévue demain matin.',
      createdAt: now.subtract(const Duration(hours: 2)),
      type: AppNotificationType.appointment,
      actionLabel: 'Voir le rendez-vous',
    ),
    AppNotification(
      id: 'hydration-reminder',
      title: 'Prenez soin de vous',
      message: 'Pensez à boire de l’eau et à faire une courte pause.',
      createdAt: now.subtract(const Duration(hours: 5)),
      type: AppNotificationType.reminder,
    ),
    AppNotification(
      id: 'prescription-renewal',
      title: 'Renouvellement à prévoir',
      message: 'Votre ordonnance arrive à échéance dans 5 jours.',
      createdAt: now.subtract(const Duration(days: 1, hours: 1)),
      type: AppNotificationType.reminder,
      isRead: true,
      actionLabel: 'Consulter l’ordonnance',
    ),
    AppNotification(
      id: 'security',
      title: 'Connexion sécurisée',
      message: 'Une nouvelle connexion à votre compte a été confirmée.',
      createdAt: now.subtract(const Duration(days: 3)),
      type: AppNotificationType.security,
      isRead: true,
    ),
  ];
}

class FirebaseNotificationService {
  FirebaseNotificationService._();

  static final FirebaseNotificationService instance =
      FirebaseNotificationService._();

  static const _payloadPrefix = 'ientier:';
  static const _channelId = 'ientier_health_reminders';
  static const _channelName = 'Rappels santé';
  static const _channelDescription =
      'Rappels de prévention synchronisés avec votre compte I-ENTIER.';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<List<AppNotification>>? _scheduleSubscription;
  Future<void> _scheduleQueue = Future<void>.value();
  String? _patientId;
  bool _initialized = false;

  CollectionReference<Map<String, dynamic>> _collection(String patientId) =>
      FirebaseFirestore.instance
          .collection('patients')
          .doc(patientId)
          .collection('notifications');

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb) return;

    try {
      tz_data.initializeTimeZones();
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_ientier'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _onNotificationSelected,
      );
    } catch (error, stackTrace) {
      debugPrint('Initialisation des notifications impossible: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Stream<List<AppNotification>> watchNotifications(String patientId) =>
      _collection(patientId)
          .orderBy('createdAt', descending: true)
          .limit(200)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(AppNotification.fromFirestore)
                .whereType<AppNotification>()
                .toList(growable: false),
          );

  Future<void> startSync(String patientId) async {
    if (_patientId == patientId && _scheduleSubscription != null) return;
    await stopSync();
    _patientId = patientId;
    await initialize();
    _scheduleSubscription = watchNotifications(patientId).listen(
      (notifications) {
        _scheduleQueue = _scheduleQueue
            .then((_) => _synchronizeSchedules(notifications))
            .onError((Object error, StackTrace stackTrace) {
              debugPrint('Synchronisation des rappels impossible: $error');
            });
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Lecture des notifications Firebase impossible: $error');
      },
    );
  }

  Future<void> stopSync() async {
    await _scheduleSubscription?.cancel();
    _scheduleSubscription = null;
    _patientId = null;
  }

  Future<bool> requestPermission() async {
    await initialize();
    if (kIsWeb) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _localNotifications
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            true;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _localNotifications
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (error) {
      debugPrint('Demande de permission de notification impossible: $error');
    }
    return false;
  }

  Future<void> setRead(String patientId, String notificationId, bool isRead) =>
      _collection(patientId).doc(notificationId).update({
        'isRead': isRead,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> markAllAsRead(
    String patientId,
    Iterable<AppNotification> notifications,
  ) async {
    final unread = notifications.where((notification) => !notification.isRead);
    final batch = FirebaseFirestore.instance.batch();
    var count = 0;
    for (final notification in unread) {
      batch.update(_collection(patientId).doc(notification.id), {
        'isRead': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      count++;
    }
    if (count > 0) await batch.commit();
  }

  Future<void> delete(String patientId, String notificationId) =>
      _collection(patientId).doc(notificationId).delete();

  Future<void> restore(String patientId, AppNotification notification) =>
      _collection(patientId).doc(notification.id).set({
        ...notification.toFirestore(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> _synchronizeSchedules(
    List<AppNotification> notifications,
  ) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      return;
    }

    final now = DateTime.now();
    final futureNotifications =
        notifications
            .where(
              (notification) => notification.scheduledAt?.isAfter(now) == true,
            )
            .toList()
          ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
    final desired = <String, AppNotification>{
      for (final notification in futureNotifications.take(60))
        _payloadFor(notification): notification,
    };
    final pending = await _localNotifications.pendingNotificationRequests();

    for (final request in pending) {
      final payload = request.payload;
      if (payload?.startsWith(_payloadPrefix) != true) continue;
      if (!desired.containsKey(payload)) {
        await _localNotifications.cancel(id: request.id);
      } else {
        desired.remove(payload);
      }
    }

    for (final entry in desired.entries) {
      final notification = entry.value;
      await _localNotifications.zonedSchedule(
        id: _stableNotificationId(notification.id),
        title: notification.title,
        body: notification.message,
        scheduledDate: tz.TZDateTime.from(notification.scheduledAt!, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            threadIdentifier: 'ientier-health-reminders',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: entry.key,
      );
    }
  }

  void _onNotificationSelected(NotificationResponse response) {
    final parsed = _parsePayload(response.payload);
    final patientId = _patientId;
    if (parsed == null || patientId == null) return;
    unawaited(setRead(patientId, parsed, true));
  }

  String _payloadFor(AppNotification notification) =>
      '$_payloadPrefix${notification.id}:${notification.scheduledAt!.millisecondsSinceEpoch}';

  String? _parsePayload(String? payload) {
    if (payload?.startsWith(_payloadPrefix) != true) return null;
    final content = payload!.substring(_payloadPrefix.length);
    final separator = content.lastIndexOf(':');
    return separator <= 0 ? null : content.substring(0, separator);
  }

  int _stableNotificationId(String value) {
    var hash = 0x811C9DC5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash == 0 ? 1 : hash;
  }
}
