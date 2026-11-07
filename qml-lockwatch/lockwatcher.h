#pragma once
#include <QObject>
#include <QQmlEngine>

// Tracks the session lock through org.freedesktop.ScreenSaver (ActiveChanged), so QML
// can react to lock/unlock without polling. Used by the net.local.macintosh wallpaper.
class LockWatcher : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool locked READ locked NOTIFY lockedChanged)
public:
    explicit LockWatcher(QObject *parent = nullptr);
    bool locked() const { return m_locked; }
Q_SIGNALS:
    void lockedChanged();
    void unlocked();   // emitted on the transition locked -> unlocked
    void lockStarted();
private Q_SLOTS:
    void onActiveChanged(bool active);
private:
    bool m_locked = false;
};
