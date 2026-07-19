import 'package:flutter/material.dart';

const _primary = Color(0xFF176BFF);
const _primarySoft = Color(0xFFEAF1FF);
const _navy = Color(0xFF102A56);
const _ink = Color(0xFF344054);
const _muted = Color(0xFF667085);
const _border = Color(0xFFE4EAF2);
const _canvas = Color(0xFFF5F8FC);

enum AppNotificationType { appointment, result, reminder, security }

extension on AppNotificationType {
  IconData get icon => switch (this) {
    AppNotificationType.appointment => Icons.calendar_month_rounded,
    AppNotificationType.result => Icons.science_rounded,
    AppNotificationType.reminder => Icons.notifications_active_rounded,
    AppNotificationType.security => Icons.shield_rounded,
  };

  Color get color => switch (this) {
    AppNotificationType.appointment => const Color(0xFF176BFF),
    AppNotificationType.result => const Color(0xFF079A7B),
    AppNotificationType.reminder => const Color(0xFFE77C22),
    AppNotificationType.security => const Color(0xFF7257D9),
  };
}

class AppNotification {
  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final AppNotificationType type;
  final bool isRead;
  final String? actionLabel;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.type,
    this.isRead = false,
    this.actionLabel,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    title: title,
    message: message,
    createdAt: createdAt,
    type: type,
    isRead: isRead ?? this.isRead,
    actionLabel: actionLabel,
  );
}

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

enum _NotificationFilter { all, unread }

class NotificationsPage extends StatefulWidget {
  final List<AppNotification>? notifications;
  final ValueChanged<List<AppNotification>>? onNotificationsChanged;

  const NotificationsPage({
    super.key,
    this.notifications,
    this.onNotificationsChanged,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late List<AppNotification> _notifications;
  _NotificationFilter _filter = _NotificationFilter.all;

  @override
  void initState() {
    super.initState();
    _notifications = List.of(widget.notifications ?? defaultAppNotifications());
  }

  int get _unreadCount =>
      _notifications.where((notification) => !notification.isRead).length;

  List<AppNotification> get _visibleNotifications => switch (_filter) {
    _NotificationFilter.all => _notifications,
    _NotificationFilter.unread =>
      _notifications.where((notification) => !notification.isRead).toList(),
  };

  void _notifyParent() {
    widget.onNotificationsChanged?.call(List.unmodifiable(_notifications));
  }

  void _setRead(AppNotification notification, bool isRead) {
    final index = _notifications.indexWhere(
      (item) => item.id == notification.id,
    );
    if (index < 0 || _notifications[index].isRead == isRead) return;
    setState(() {
      _notifications[index] = _notifications[index].copyWith(isRead: isRead);
    });
    _notifyParent();
  }

  void _markAllAsRead() {
    if (_unreadCount == 0) return;
    setState(() {
      _notifications = _notifications
          .map((notification) => notification.copyWith(isRead: true))
          .toList();
    });
    _notifyParent();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Toutes les notifications ont été lues.')),
    );
  }

  void _delete(AppNotification notification) {
    final index = _notifications.indexWhere(
      (item) => item.id == notification.id,
    );
    if (index < 0) return;
    setState(() => _notifications.removeAt(index));
    _notifyParent();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Notification supprimée.'),
          action: SnackBarAction(
            label: 'Annuler',
            onPressed: () {
              if (_notifications.any((item) => item.id == notification.id)) {
                return;
              }
              setState(() {
                _notifications.insert(
                  index.clamp(0, _notifications.length),
                  notification,
                );
              });
              _notifyParent();
            },
          ),
        ),
      );
  }

  void _openNotification(AppNotification notification) {
    _setRead(notification, true);
    final action = notification.actionLabel;
    if (action == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action : contenu bientôt disponible.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleNotifications = _visibleNotifications;
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Tout marquer comme lu',
            onPressed: _unreadCount == 0 ? null : _markAllAsRead,
            icon: const Icon(Icons.done_all_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  sliver: SliverToBoxAdapter(
                    child: _NotificationSummary(unreadCount: _unreadCount),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: _FilterChip(
                            label: 'Toutes (${_notifications.length})',
                            selected: _filter == _NotificationFilter.all,
                            onSelected: () => setState(
                              () => _filter = _NotificationFilter.all,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _FilterChip(
                            label: 'Non lues ($_unreadCount)',
                            selected: _filter == _NotificationFilter.unread,
                            onSelected: () => setState(
                              () => _filter = _NotificationFilter.unread,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 18)),
                if (visibleNotifications.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyNotifications(filter: _filter),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    sliver: SliverList.separated(
                      itemCount: visibleNotifications.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final notification = visibleNotifications[index];
                        return _NotificationTile(
                          key: ValueKey(notification.id),
                          notification: notification,
                          onTap: () => _openNotification(notification),
                          onReadChanged: (isRead) =>
                              _setRead(notification, isRead),
                          onDelete: () => _delete(notification),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationSummary extends StatelessWidget {
  final int unreadCount;

  const _NotificationSummary({required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    final hasUnread = unreadCount > 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF176BFF), Color(0xFF0A9FD6)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29176BFF),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: .22)),
            ),
            child: Icon(
              hasUnread
                  ? Icons.notifications_active_rounded
                  : Icons.done_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasUnread
                      ? '$unreadCount nouvelle${unreadCount > 1 ? 's' : ''} notification${unreadCount > 1 ? 's' : ''}'
                      : 'Tout est à jour',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasUnread
                      ? 'Retrouvez ici les nouvelles de votre parcours santé.'
                      : 'Vous avez consulté toutes vos notifications.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .86),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ChoiceChip(
      label: SizedBox(
        width: double.infinity,
        child: Text(label, textAlign: TextAlign.center),
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      selectedColor: _primarySoft,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? _primary : _border),
      labelStyle: TextStyle(
        color: selected ? _primary : _muted,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

enum _NotificationMenuAction { toggleRead, delete }

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  final ValueChanged<bool> onReadChanged;
  final VoidCallback onDelete;

  const _NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
    required this.onReadChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Dismissible(
    key: ValueKey('dismiss-${notification.id}'),
    direction: DismissDirection.endToStart,
    onDismissed: (_) => onDelete(),
    background: Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFD92D20),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
    ),
    child: Material(
      color: notification.isRead ? Colors.white : const Color(0xFFF7FAFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: notification.isRead ? _border : const Color(0xFFBCD2FF),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: notification.type.color.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      notification.type.icon,
                      color: notification.type.color,
                      size: 24,
                    ),
                  ),
                  if (!notification.isRead)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: _primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: TextStyle(
                        color: _navy,
                        fontSize: 15.5,
                        fontWeight: notification.isRead
                            ? FontWeight.w700
                            : FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      notification.message,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 15,
                          color: _muted,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _relativeTime(notification.createdAt),
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (notification.actionLabel != null) ...[
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              notification.actionLabel!,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_NotificationMenuAction>(
                tooltip: 'Options de la notification',
                onSelected: (action) {
                  switch (action) {
                    case _NotificationMenuAction.toggleRead:
                      onReadChanged(!notification.isRead);
                    case _NotificationMenuAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _NotificationMenuAction.toggleRead,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        notification.isRead
                            ? Icons.mark_email_unread_outlined
                            : Icons.mark_email_read_outlined,
                      ),
                      title: Text(
                        notification.isRead
                            ? 'Marquer comme non lue'
                            : 'Marquer comme lue',
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _NotificationMenuAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text('Supprimer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _EmptyNotifications extends StatelessWidget {
  final _NotificationFilter filter;

  const _EmptyNotifications({required this.filter});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 80),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: _primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: _primary,
              size: 34,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            filter == _NotificationFilter.unread
                ? 'Aucune notification non lue'
                : 'Aucune notification',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _navy,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            filter == _NotificationFilter.unread
                ? 'Vous avez tout consulté. Revenez plus tard pour les nouveautés.'
                : 'Vos rappels et mises à jour de santé apparaîtront ici.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, height: 1.4),
          ),
        ],
      ),
    ),
  );
}

String _relativeTime(DateTime date) {
  final difference = DateTime.now().difference(date);
  if (difference.isNegative || difference.inMinutes < 1) return 'À l’instant';
  if (difference.inMinutes < 60) return 'Il y a ${difference.inMinutes} min';
  if (difference.inHours < 24) return 'Il y a ${difference.inHours} h';
  if (difference.inDays == 1) return 'Hier';
  return 'Il y a ${difference.inDays} jours';
}
