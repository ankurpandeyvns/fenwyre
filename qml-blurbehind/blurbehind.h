#pragma once
#include <QQuickItem>
#include <QPointer>

// Asks KWin to blur what is behind this item (rounded rect) in its window.
class BlurBehind : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(qreal radius READ radius WRITE setRadius NOTIFY radiusChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
public:
    explicit BlurBehind(QQuickItem *parent = nullptr);
    ~BlurBehind() override;
    qreal radius() const { return m_radius; }
    void setRadius(qreal r);
    bool active() const { return m_active; }
    void setActive(bool a);
Q_SIGNALS:
    void radiusChanged();
    void activeChanged();
protected:
    void itemChange(ItemChange change, const ItemChangeData &data) override;
    void geometryChange(const QRectF &n, const QRectF &o) override;
private:
    void update();
    qreal m_radius = 0;
    bool m_active = true;
    QPointer<QWindow> m_window;
};
