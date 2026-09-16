/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <KMultiTabBar>
#include <KPluginFactory>
#include <KTextEditor/MainWindow>
#include <KTextEditor/Plugin>

#include <QAbstractButton>
#include <QApplication>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QFrame>
#include <QPainter>
#include <QPaintEvent>
#include <QPalette>
#include <QPointer>
#include <QSettings>
#include <QStackedWidget>
#include <QStandardPaths>
#include <QStyle>
#include <QTimer>
#include <QWidget>

namespace
{
constexpr int defaultOpacity = 60;
constexpr int darklyFullBlurHintAlpha = 254;
constexpr auto originalMinimumHeightProperty = "_kate_translucent_bars_original_minimum_height";

bool isRequestedPosition(const KMultiTabBar *bar)
{
    if (!bar) {
        return false;
    }

    return bar->position() == KMultiTabBar::Left || bar->position() == KMultiTabBar::Bottom;
}

KMultiTabBar *ancestorBar(QWidget *widget)
{
    for (QWidget *candidate = widget; candidate; candidate = candidate->parentWidget()) {
        if (auto *bar = qobject_cast<KMultiTabBar *>(candidate)) {
            return bar;
        }
    }

    return nullptr;
}

KMultiTabBar *requestedDescendantBar(QWidget *widget)
{
    const auto bars = widget->findChildren<KMultiTabBar *>();
    for (KMultiTabBar *bar : bars) {
        if (isRequestedPosition(bar)) {
            return bar;
        }
    }

    return nullptr;
}

bool containsKateStatusBar(QWidget *widget)
{
    const auto children = widget->findChildren<QWidget *>(QString(), Qt::FindDirectChildrenOnly);
    for (QWidget *child : children) {
        if (child->inherits("KateStatusBar")) {
            return true;
        }
    }

    return false;
}

bool isBottomBarSeparator(QWidget *widget)
{
    auto *frame = qobject_cast<QFrame *>(widget);
    return frame && frame->frameShape() == QFrame::HLine && !frame->isEnabled() && frame->minimumHeight() == 1
        && frame->maximumHeight() == 1;
}
}

class KateTranslucentBarsView final : public QObject
{
public:
    explicit KateTranslucentBarsView(KTextEditor::MainWindow *mainWindow)
        : QObject(mainWindow)
        , m_window(mainWindow->window())
        , m_configPath(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/darklyrc"))
    {
        reloadOpacity();

        if (QFileInfo::exists(m_configPath)) {
            m_watcher.addPath(m_configPath);
        }

        connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] {
            reloadOpacity();
            if (QFileInfo::exists(m_configPath) && !m_watcher.files().contains(m_configPath)) {
                m_watcher.addPath(m_configPath);
            }
            if (m_window) {
                m_window->update();
            }
            updateDarklyBlurHint();
        });

        qApp->installEventFilter(this);
        connect(mainWindow, &KTextEditor::MainWindow::viewCreated, this, [this] {
            scheduleStatusBarStackUpdate();
        });
        updateDarklyBlurHint();
        scheduleStatusBarStackUpdate();
        if (m_window) {
            m_window->update();
        }
    }

    ~KateTranslucentBarsView() override
    {
        restoreWindowPaletteAlpha();
        updateStatusBarStackHeights(false);
        qApp->removeEventFilter(this);
    }

protected:
    bool eventFilter(QObject *object, QEvent *event) override
    {
        if (m_window && object == m_window && event->type() == QEvent::StyleChange) {
            scheduleStatusBarStackUpdate();
            QTimer::singleShot(0, this, [this] {
                updateDarklyBlurHint();
            });
        }

        if (m_window && event->type() == QEvent::Resize) {
            auto *resizedWidget = qobject_cast<QWidget *>(object);
            auto *bar = qobject_cast<KMultiTabBar *>(resizedWidget);
            if (isRequestedPosition(bar) && bar->position() == KMultiTabBar::Bottom) {
                scheduleStatusBarStackUpdate();
            }
        }

        if (!m_window || event->type() != QEvent::Paint || !darklyIsActive()) {
            return QObject::eventFilter(object, event);
        }

        auto *widget = qobject_cast<QWidget *>(object);
        if (!widget || widget->window() != m_window || !isTranslucentSurface(widget)) {
            return QObject::eventFilter(object, event);
        }

        auto *paintEvent = static_cast<QPaintEvent *>(event);
        QPainter painter(widget);
        painter.setClipRegion(paintEvent->region());

        // Darkly first paints the top-level window with an opaque Window color.
        // Remove those pixels before adding the requested translucent surface.
        painter.setCompositionMode(QPainter::CompositionMode_DestinationOut);
        painter.fillRect(paintEvent->rect(), Qt::black);

        painter.setCompositionMode(QPainter::CompositionMode_SourceOver);
        QColor background = widget->palette().color(QPalette::Window);
        background.setAlphaF(static_cast<qreal>(m_opacity) / 100.0);
        painter.fillRect(paintEvent->rect(), background);

        // QStackedWidget inherits QFrame and paints its opaque frame/background
        // after an event filter runs. The Kate status bar is shorter than this
        // stack, so that repaint showed up as white strips above and below the
        // status text. Its children paint themselves, therefore suppress only
        // this empty container's original paint event.
        if ((qobject_cast<QStackedWidget *>(widget) && containsKateStatusBar(widget))
            || isBottomBarSeparator(widget)) {
            return true;
        }

        return QObject::eventFilter(object, event);
    }

private:
    bool darklyIsActive() const
    {
        const QStyle *style = qApp->style();
        if (!style) {
            return false;
        }

        const QString className = QString::fromLatin1(style->metaObject()->className());
        return className.contains(QStringLiteral("Darkly"), Qt::CaseInsensitive)
            || style->objectName().contains(QStringLiteral("darkly"), Qt::CaseInsensitive);
    }

    bool isTranslucentSurface(QWidget *widget) const
    {
        // Preserve the hover/selected rendering of the actual sidebar buttons.
        if (qobject_cast<QAbstractButton *>(widget)) {
            return false;
        }

        if (auto *bar = qobject_cast<KMultiTabBar *>(widget)) {
            return isRequestedPosition(bar);
        }

        if (widget->inherits("KMultiTabBarInternal")) {
            return isRequestedPosition(ancestorBar(widget));
        }

        if (widget->inherits("KateMDI::MultiTabBar") || widget->inherits("KateMDI::Sidebar")) {
            return requestedDescendantBar(widget) != nullptr;
        }

        if (widget->inherits("KateStatusBar")) {
            return true;
        }

        if (qobject_cast<QStackedWidget *>(widget) && containsKateStatusBar(widget)) {
            return true;
        }

        if (isBottomBarSeparator(widget)) {
            return true;
        }

        return false;
    }

    void reloadOpacity()
    {
        QSettings settings(m_configPath, QSettings::IniFormat);
        settings.beginGroup(QStringLiteral("Style"));
        const int toolBarOpacity = qBound(0, settings.value(QStringLiteral("ToolBarOpacity"), defaultOpacity).toInt(), 100);
        m_opacity = qBound(0, settings.value(QStringLiteral("KateBarsOpacity"), toolBarOpacity).toInt(), 100);
    }

    void updateDarklyBlurHint()
    {
        if (!m_window) {
            return;
        }

        if (!darklyIsActive() || m_opacity >= 100) {
            restoreWindowPaletteAlpha();
            return;
        }

        QPalette palette = m_window->palette();
        if (!m_blurHintApplied) {
            m_originalActiveWindowAlpha = palette.color(QPalette::Active, QPalette::Window).alpha();
            m_originalInactiveWindowAlpha = palette.color(QPalette::Inactive, QPalette::Window).alpha();
            m_originalDisabledWindowAlpha = palette.color(QPalette::Disabled, QPalette::Window).alpha();
            m_originalPaletteResolveMask = palette.resolveMask();
            m_blurHintApplied = true;
        }

        // Darkly owns the Wayland blur hint. An alpha below 255 selects its
        // stable, rounded full-window region; 254 remains visually opaque on
        // surfaces that this plugin does not explicitly repaint.
        bool changed = false;
        const auto setHintAlpha = [&palette, &changed](QPalette::ColorGroup group) {
            QColor color = palette.color(group, QPalette::Window);
            if (color.alpha() > darklyFullBlurHintAlpha) {
                color.setAlpha(darklyFullBlurHintAlpha);
                palette.setColor(group, QPalette::Window, color);
                changed = true;
            }
        };

        setHintAlpha(QPalette::Active);
        setHintAlpha(QPalette::Inactive);
        setHintAlpha(QPalette::Disabled);
        if (changed) {
            m_window->setPalette(palette);
        }
    }

    void restoreWindowPaletteAlpha()
    {
        if (!m_window || !m_blurHintApplied) {
            return;
        }

        QPalette palette = m_window->palette();
        const auto restoreAlpha = [&palette](QPalette::ColorGroup group, int alpha) {
            QColor color = palette.color(group, QPalette::Window);
            color.setAlpha(alpha);
            palette.setColor(group, QPalette::Window, color);
        };
        restoreAlpha(QPalette::Active, m_originalActiveWindowAlpha);
        restoreAlpha(QPalette::Inactive, m_originalInactiveWindowAlpha);
        restoreAlpha(QPalette::Disabled, m_originalDisabledWindowAlpha);
        palette.setResolveMask(m_originalPaletteResolveMask);
        m_window->setPalette(palette);
        m_blurHintApplied = false;
    }

    void scheduleStatusBarStackUpdate()
    {
        QTimer::singleShot(0, this, [this] {
            updateStatusBarStackHeights(darklyIsActive());
        });
    }

    void updateStatusBarStackHeights(bool translucent)
    {
        if (!m_window) {
            return;
        }

        int bottomBarHeight = 0;
        const auto bars = m_window->findChildren<KMultiTabBar *>();
        for (KMultiTabBar *bar : bars) {
            if (bar->position() == KMultiTabBar::Bottom) {
                bottomBarHeight = qMax(bottomBarHeight, qMax(bar->height(), bar->sizeHint().height()));
            }
        }

        bool geometryChanged = false;
        const auto stacks = m_window->findChildren<QStackedWidget *>();
        for (QStackedWidget *stack : stacks) {
            if (!containsKateStatusBar(stack)) {
                continue;
            }

            const QVariant originalMinimumHeight = stack->property(originalMinimumHeightProperty);
            int minimumHeight = stack->minimumHeight();

            if (translucent) {
                if (!originalMinimumHeight.isValid()) {
                    stack->setProperty(originalMinimumHeightProperty, minimumHeight);
                } else {
                    minimumHeight = originalMinimumHeight.toInt();
                }
                minimumHeight = qMax(minimumHeight, bottomBarHeight);
            } else if (originalMinimumHeight.isValid()) {
                minimumHeight = originalMinimumHeight.toInt();
                stack->setProperty(originalMinimumHeightProperty, QVariant());
            } else {
                continue;
            }

            if (stack->minimumHeight() != minimumHeight) {
                stack->setMinimumHeight(minimumHeight);
                stack->updateGeometry();
                geometryChanged = true;
            }
        }

        if (geometryChanged) {
            const auto widgets = m_window->findChildren<QWidget *>();
            for (QWidget *widget : widgets) {
                if (isTranslucentSurface(widget)) {
                    widget->update();
                }
            }
        }
    }

    QPointer<QWidget> m_window;
    QString m_configPath;
    QFileSystemWatcher m_watcher;
    int m_opacity = defaultOpacity;
    int m_originalActiveWindowAlpha = 255;
    int m_originalInactiveWindowAlpha = 255;
    int m_originalDisabledWindowAlpha = 255;
    QPalette::ResolveMask m_originalPaletteResolveMask = 0;
    bool m_blurHintApplied = false;
};

class KateTranslucentBarsPlugin final : public KTextEditor::Plugin
{
    Q_OBJECT

public:
    explicit KateTranslucentBarsPlugin(QObject *parent)
        : KTextEditor::Plugin(parent)
    {
    }

    QObject *createView(KTextEditor::MainWindow *mainWindow) override
    {
        return new KateTranslucentBarsView(mainWindow);
    }
};

K_PLUGIN_FACTORY_WITH_JSON(KateTranslucentBarsPluginFactory,
                           "katetranslucentbarsplugin.json",
                           registerPlugin<KateTranslucentBarsPlugin>();)

#include "katetranslucentbarsplugin.moc"
