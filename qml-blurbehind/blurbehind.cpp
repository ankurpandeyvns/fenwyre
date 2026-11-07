#include "blurbehind.h"
#include <KWindowEffects>
#include <QQuickWindow>
#include <QRegion>
#include <cmath>

BlurBehind::BlurBehind(QQuickItem *parent) : QQuickItem(parent)
{
    connect(this, &QQuickItem::visibleChanged, this, &BlurBehind::update);
    connect(this, &QQuickItem::xChanged, this, &BlurBehind::update);
    connect(this, &QQuickItem::yChanged, this, &BlurBehind::update);
}
BlurBehind::~BlurBehind()
{
    if (m_window)
        KWindowEffects::enableBlurBehind(m_window, false);
}
void BlurBehind::setRadius(qreal r) { if (r != m_radius) { m_radius = r; update(); Q_EMIT radiusChanged(); } }
void BlurBehind::setActive(bool a) { if (a != m_active) { m_active = a; update(); Q_EMIT activeChanged(); } }
void BlurBehind::itemChange(ItemChange change, const ItemChangeData &data)
{
    if (change == ItemSceneChange) {
        if (m_window)
            KWindowEffects::enableBlurBehind(m_window, false);
        m_window = data.window;
        if (m_window)
            connect(m_window, &QWindow::visibleChanged, this, &BlurBehind::update);
    }
    QQuickItem::itemChange(change, data);
    update();
}
void BlurBehind::geometryChange(const QRectF &n, const QRectF &o)
{
    QQuickItem::geometryChange(n, o);
    update();
}
void BlurBehind::update()
{
    if (!m_window || !m_window->isVisible())
        return;
    if (!m_active || !isVisible() || width() <= 0 || height() <= 0) {
        KWindowEffects::enableBlurBehind(m_window, false);
        return;
    }
    const QRectF r = mapRectToScene(QRectF(0, 0, width(), height()));
    const int x = std::round(r.x()), y = std::round(r.y()), w = std::round(r.width()), h = std::round(r.height());
    const int rad = std::min<int>(std::round(m_radius), std::min(w, h) / 2);
    QRegion region(x, y + rad, w, h - 2 * rad);
    for (int i = 0; i < rad; ++i) {   // rounded corners, one row at a time
        const double dy = rad - i - 0.5;
        const int inset = std::round(rad - std::sqrt(std::max(0.0, double(rad) * rad - dy * dy)));
        region += QRegion(x + inset, y + i, w - 2 * inset, 1);
        region += QRegion(x + inset, y + h - 1 - i, w - 2 * inset, 1);
    }
    KWindowEffects::enableBlurBehind(m_window, true, region);
}
