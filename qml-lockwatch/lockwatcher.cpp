#include "lockwatcher.h"
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>

static const char *kService = "org.freedesktop.ScreenSaver";
static const char *kPath = "/ScreenSaver";
static const char *kIface = "org.freedesktop.ScreenSaver";

LockWatcher::LockWatcher(QObject *parent)
    : QObject(parent)
{
    auto bus = QDBusConnection::sessionBus();
    bus.connect(QString::fromLatin1(kService), QString::fromLatin1(kPath), QString::fromLatin1(kIface),
                QStringLiteral("ActiveChanged"), this, SLOT(onActiveChanged(bool)));
    // initial state, asynchronously
    auto msg = QDBusMessage::createMethodCall(QString::fromLatin1(kService), QString::fromLatin1(kPath),
                                              QString::fromLatin1(kIface), QStringLiteral("GetActive"));
    auto *w = new QDBusPendingCallWatcher(bus.asyncCall(msg), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        QDBusPendingReply<bool> reply = *call;
        if (reply.isValid() && reply.value() != m_locked) {
            m_locked = reply.value();
            Q_EMIT lockedChanged();
        }
        call->deleteLater();
    });
}

void LockWatcher::onActiveChanged(bool active)
{
    if (active == m_locked)
        return;
    m_locked = active;
    Q_EMIT lockedChanged();
    if (active)
        Q_EMIT lockStarted();
    else
        Q_EMIT unlocked();
}
