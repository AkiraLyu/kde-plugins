// SPDX-License-Identifier: GPL-2.0-or-later

#include <QAction>
#include <QApplication>
#include <QFile>
#include <QMenu>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QTest>

#include <KConfigPropertyMap>
#include <KLocalizedString>
#include <Plasma/Applet>
#include <Plasma/Containment>
#include <Plasma/Corona>
#include <PlasmaQuick/AppletQuickItem>
#include <taskmanager/abstracttasksmodel.h>
#include <taskmanager/tasksmodel.h>

class TestCorona : public Plasma::Corona
{
public:
    QRect screenGeometry(int) const override
    {
        return QRect(0, 0, 1600, 900);
    }
};

class SmokeTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void appletLoadsAndAppliesSettings()
    {
        TestCorona corona;
        auto *containment = corona.createContainment(QStringLiteral("null"));
        QVERIFY(containment);
        containment->setFormFactor(Plasma::Types::Horizontal);
        containment->setLocation(Plasma::Types::BottomEdge);
        auto *applet = containment->createApplet(QStringLiteral("org.kde.plasma.adjustabletaskmanager"));
        QVERIFY(applet);
        auto *config = applet->configuration();
        QTemporaryDir launcherFiles;
        const QString launchMarker = launcherFiles.filePath(QStringLiteral("launcher-activated"));
        QStringList launchers;
        for (int i = 0; i < 3; ++i) {
            const QString path = launcherFiles.filePath(QStringLiteral("launcher-%1.desktop").arg(i));
            QFile desktop(path);
            QVERIFY(desktop.open(QIODevice::WriteOnly));
            desktop.write(QStringLiteral("[Desktop Entry]\nType=Application\nName=Smoke launcher\nExec=/usr/bin/touch %1\nIcon=applications-system\n")
                              .arg(launchMarker)
                              .toUtf8());
            desktop.close();
            launchers.append(QUrl::fromLocalFile(path).toString());
        }
        QVERIFY(config->setProperty("launchers", launchers));
        QVERIFY(config->setProperty("showOnlyCurrentDesktop", false));
        QVERIFY(config->setProperty("showOnlyCurrentActivity", false));
        QGuiApplication::setDesktopFileName(launcherFiles.filePath(QStringLiteral("launcher-1.desktop")));

        auto *item = PlasmaQuick::AppletQuickItem::itemForApplet(applet);
        QVERIFY(item);
        QVERIFY2(!applet->failedToLaunch(), qPrintable(applet->launchErrorMessage()));
        // Plasma may also load a stock task manager in the same process.
        auto *stockApplet = containment->createApplet(QStringLiteral("org.kde.plasma.icontasks"));
        QVERIFY(stockApplet);
        QVERIFY(PlasmaQuick::AppletQuickItem::itemForApplet(stockApplet));
        QQuickWindow window;
        window.setFlags(Qt::Tool | Qt::FramelessWindowHint);
        window.resize(1600, 48);
        item->setParentItem(window.contentItem());
        item->setSize(QSizeF(1600, 48));
        window.show();

        auto *model = item->property("tasksModel").value<TaskManager::TasksModel *>();
        QVERIFY(model);
        QCOMPARE(model->launcherList(), launchers);
        QVERIFY(model->launchInPlace());
        QVERIFY(model->separateLaunchers());
        QVERIFY(model->hideActivatedLaunchers());

        auto *list = item->property("taskList").value<QQuickItem *>();
        QVERIFY(list);
        QTRY_VERIFY(list->childItems().size() >= 3);
        auto *launcher = list->childItems().at(0);
        QTRY_COMPARE(launcher->width(), 60.0);
        QVERIFY(config->setProperty("launcherSpacing", 36));
        QTRY_COMPARE(launcher->width(), 84.0);
        QVERIFY(config->setProperty("launcherSpacing", 0));
        QTRY_COMPARE(launcher->width(), 48.0);

        QTest::mouseClick(&window, Qt::RightButton, Qt::NoModifier, launcher->mapToScene(QPointF(24, 24)).toPoint());
        QTRY_VERIFY(launcher->property("contextMenu").value<QObject *>());
        auto *menu = launcher->property("contextMenu").value<QObject *>();
        QCOMPARE(menu->property("backend").value<QObject *>(), item->property("backend").value<QObject *>());
        QTRY_VERIFY(qobject_cast<QMenu *>(QApplication::activePopupWidget()));
        auto *popup = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        QVERIFY(!popup->actions().isEmpty());
        QTest::keyClick(popup, Qt::Key_Escape);
        QTRY_VERIFY(!launcher->property("contextMenu").value<QObject *>());

        // A matching window must replace the middle launcher and restore it on close.
        const auto launcherRole = TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon;
        const auto middleUrl = model->index(1, 0).data(launcherRole);
        const auto lastUrl = model->index(2, 0).data(launcherRole);
        QQuickWindow launchedWindow;
        launchedWindow.setTitle(QStringLiteral("Smoke launcher"));
        launchedWindow.resize(320, 160);
        launchedWindow.show();
        QTRY_VERIFY(model->index(1, 0).data(TaskManager::AbstractTasksModel::IsWindow).toBool());
        QCOMPARE(model->index(1, 0).data(launcherRole), middleUrl);
        QCOMPARE(model->index(2, 0).data(launcherRole), lastUrl);
        QCOMPARE(model->launcherList(), launchers);
        auto *windowTask = list->childItems().at(1);
        QVERIFY(config->setProperty("taskMaxWidth", 3));
        QVERIFY(config->setProperty("customTaskMaxWidth", 317));
        QTRY_VERIFY(windowTask->width() > 48 && windowTask->width() < 317);
        const qreal shortWidth = windowTask->width();
        launchedWindow.setTitle(QStringLiteral("S"));
        QTRY_COMPARE(windowTask->property("labelText").toString(), QStringLiteral("S"));
        QTRY_VERIFY(windowTask->width() < shortWidth);

        const QString longTitle = QStringLiteral("A long window title that must reach the custom maximum task width");
        launchedWindow.setTitle(longTitle);
        QTRY_COMPARE(windowTask->property("labelText").toString(), longTitle);
        QTRY_COMPARE(windowTask->width(), 317.0);
        QVERIFY(config->setProperty("customTaskMaxWidth", 100));
        QTRY_COMPARE(windowTask->width(), 100.0);
        QVERIFY(config->setProperty("customTaskMaxWidth", 317));

        QQuickWindow secondWindow;
        secondWindow.setTitle(QStringLiteral("Short"));
        secondWindow.resize(320, 160);
        secondWindow.show();
        QTRY_VERIFY(model->index(2, 0).data(TaskManager::AbstractTasksModel::IsWindow).toBool());
        auto *secondTask = list->childItems().at(2);
        QTRY_COMPARE(secondTask->property("labelText").toString(), QStringLiteral("Short"));
        QTRY_VERIFY(secondTask->width() < windowTask->width());
        QCOMPARE(windowTask->width(), 317.0);
        QVERIFY(config->value(QStringLiteral("shrinkTasksToTitle")).toBool());
        QVERIFY(config->setProperty("shrinkTasksToTitle", false));
        QTRY_COMPARE(secondTask->width(), 317.0);
        QCOMPARE(windowTask->width(), 317.0);
        QVERIFY(config->setProperty("shrinkTasksToTitle", true));
        QTRY_VERIFY(secondTask->width() < windowTask->width());

        if (const auto path = qEnvironmentVariable("TASK_MANAGER_SCREENSHOT"); !path.isEmpty()) {
            QTest::qWait(200);
            QVERIFY(window.grabWindow().save(path));
        }

        launchedWindow.setWindowState(Qt::WindowMinimized);
        secondWindow.setWindowState(Qt::WindowMinimized);
        QTRY_VERIFY(model->index(1, 0).data(TaskManager::AbstractTasksModel::IsMinimized).toBool());
        QTRY_VERIFY(model->index(2, 0).data(TaskManager::AbstractTasksModel::IsMinimized).toBool());
        QVERIFY(QMetaObject::invokeMethod(item, "activateTaskAtIndex", Q_ARG(QVariant, 1)));
        QTRY_VERIFY(!model->index(2, 0).data(TaskManager::AbstractTasksModel::IsMinimized).toBool());
        QVERIFY(model->index(1, 0).data(TaskManager::AbstractTasksModel::IsMinimized).toBool());
        secondWindow.close();
        QTRY_COMPARE(model->index(2, 0).data(launcherRole), lastUrl);

        // Meta+1 must restore the first window even though a pinned icon precedes it.
        launchedWindow.setWindowState(Qt::WindowMinimized);
        QTRY_VERIFY(model->index(1, 0).data(TaskManager::AbstractTasksModel::IsMinimized).toBool());
        QVERIFY(QMetaObject::invokeMethod(item, "activateTaskAtIndex", Q_ARG(QVariant, 0)));
        QTRY_VERIFY(!model->index(1, 0).data(TaskManager::AbstractTasksModel::IsMinimized).toBool());
        QVERIFY(!QFile::exists(launchMarker));

        QVERIFY(QMetaObject::invokeMethod(item, "activateTaskAtIndex", Q_ARG(QVariant, 1)));
        QTest::qWait(100);
        QVERIFY(!model->index(1, 0).data(TaskManager::AbstractTasksModel::IsMinimized).toBool());

        // Exercise a window action as well as opening the launcher's menu above.
        QTest::mouseClick(&window, Qt::RightButton, Qt::NoModifier, windowTask->mapToScene(QPointF(24, 24)).toPoint());
        QTRY_VERIFY(qobject_cast<QMenu *>(QApplication::activePopupWidget()));
        popup = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        QAction *closeAction = nullptr;
        for (auto *action : popup->actions()) {
            if (action->icon().name() == QLatin1String("window-close")) {
                closeAction = action;
                break;
            }
        }
        QVERIFY(closeAction);
        QVERIFY(closeAction->isEnabled());
        if (const auto path = qEnvironmentVariable("TASK_MANAGER_SCREENSHOT"); !path.isEmpty()) {
            QVERIFY(popup->grab().save(path + QStringLiteral(".menu.png")));
        }
        QTest::mouseClick(popup, Qt::LeftButton, Qt::NoModifier, popup->actionGeometry(closeAction).center());
        QTRY_VERIFY(model->index(1, 0).data(TaskManager::AbstractTasksModel::IsLauncher).toBool());
        QCOMPARE(model->index(1, 0).data(launcherRole), middleUrl);
        QCOMPARE(model->launcherList(), launchers);

        // With only launchers left, neither a valid number nor an out-of-range one may launch an app.
        QVERIFY(QMetaObject::invokeMethod(item, "activateTaskAtIndex", Q_ARG(QVariant, 0)));
        QVERIFY(QMetaObject::invokeMethod(item, "activateTaskAtIndex", Q_ARG(QVariant, 8)));
        QTest::qWait(500);
        QVERIFY(!QFile::exists(launchMarker));

        QVERIFY(config->setProperty("sortingStrategy", 2));
        QTRY_VERIFY(!model->launchInPlace());
        QVERIFY(config->setProperty("sortingStrategy", 1));
        QTRY_VERIFY(model->launchInPlace());

        const QUrl resourceRoot(QStringLiteral("qrc:/qt/qml/plasma/applet/org/kde/plasma/adjustabletaskmanager/"));
        QQmlComponent appearance(qmlEngine(item), resourceRoot.resolved(QUrl(QStringLiteral("ConfigAppearance.qml"))));
        QScopedPointer<QObject> page(appearance.create(qmlContext(item)));
        QVERIFY2(page, qPrintable(appearance.errorString()));
        for (int i = 0; i < page->metaObject()->propertyCount(); ++i) {
            const auto property = page->metaObject()->property(i);
            const auto name = QString::fromLatin1(property.name());
            if (name.startsWith(QLatin1String("cfg_")) && config->contains(name.mid(4))) {
                property.write(page.data(), config->value(name.mid(4)));
            }
        }
        QVERIFY(page->setProperty("cfg_taskMaxWidth", 3));
        QVERIFY(page->setProperty("cfg_customTaskMaxWidth", 317));
        QCOMPARE(page->property("cfg_customTaskMaxWidth").toInt(), 317);
        QVERIFY(page->property("cfg_shrinkTasksToTitle").toBool());
        QVERIFY(page->setProperty("cfg_shrinkTasksToTitle", false));
        QVERIFY(!page->property("cfg_shrinkTasksToTitle").toBool());
        QVERIFY(page->setProperty("cfg_launcherSpacing", 25));
        QCOMPARE(page->property("cfg_launcherSpacing").toInt(), 25);

        containment->setFormFactor(Plasma::Types::Vertical);
        containment->flushPendingConstraintsEvents();
        applet->flushPendingConstraintsEvents();
        QTRY_VERIFY(item->property("vertical").toBool());
        item->setSize(QSizeF(60, 800));
        QTest::qWait(100);
        launcher = nullptr;
        for (auto *child : list->childItems()) {
            if (child->property("isIcon").toBool()) {
                launcher = child;
                break;
            }
        }
        QVERIFY(launcher);
        QCOMPARE(config->value(QStringLiteral("launcherSpacing")).toInt(), 0);
        QTRY_VERIFY(launcher->height() < item->height());
        const auto height = launcher->height();
        QVERIFY(config->setProperty("launcherSpacing", 24));
        QTRY_COMPARE(launcher->height(), height + 24);

        if (const auto path = qEnvironmentVariable("TASK_MANAGER_SCREENSHOT"); !path.isEmpty()) {
            containment->setFormFactor(Plasma::Types::Horizontal);
            containment->flushPendingConstraintsEvents();
            applet->flushPendingConstraintsEvents();
            item->setSize(QSizeF(1600, 48));
            QQuickWindow configWindow;
            configWindow.resize(810, 690);
            auto *pageItem = qobject_cast<QQuickItem *>(page.data());
            QVERIFY(pageItem);
            pageItem->setParentItem(configWindow.contentItem());
            pageItem->setSize(QSizeF(810, 690));
            configWindow.show();
            QVERIFY(QTest::qWaitForWindowExposed(&configWindow));
            QTest::qWait(500);
            QVERIFY(configWindow.grabWindow().save(path + QStringLiteral(".config.png")));
        }
    }
};

int main(int argc, char **argv)
{
    QTemporaryDir config;
    qputenv("XDG_CONFIG_HOME", config.path().toUtf8());
    QApplication app(argc, argv);
    KLocalizedString::setApplicationDomain("plasma_applet_org.kde.plasma.adjustabletaskmanager");
    SmokeTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "smoke.moc"
