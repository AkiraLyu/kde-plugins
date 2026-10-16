// SPDX-License-Identifier: GPL-2.0-or-later

#include <QAction>
#include <QApplication>
#include <QCursor>
#include <QDir>
#include <QFile>
#include <QList>
#include <QMenu>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

#include <KConfigPropertyMap>
#include <KLocalizedString>
#include <KWayland/Client/connection_thread.h>
#include <KWayland/Client/fakeinput.h>
#include <KWayland/Client/registry.h>
#include <Plasma/Applet>
#include <Plasma/Containment>
#include <Plasma/Corona>
#include <PlasmaQuick/AppletQuickItem>
#include <PlasmaQuick/Dialog>
#include <taskmanager/abstracttasksmodel.h>
#include <taskmanager/tasksmodel.h>

#include <linux/input-event-codes.h>

class TestCorona : public Plasma::Corona
{
public:
    QRect screenGeometry(uint) const override
    {
        return QRect(0, 0, 1600, 900);
    }
};

class SmokeTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        QVERIFY2(qEnvironmentVariable("TASK_MANAGER_TEST_SESSION") == QLatin1String("1"), "Run this test through CTest in its isolated Wayland session.");
    }

    void appletLoadsAndAppliesSettings()
    {
        KWayland::Client::Registry registry;
        registry.create(KWayland::Client::ConnectionThread::fromApplication());
        registry.setup();
        QTRY_VERIFY(registry.hasInterface(KWayland::Client::Registry::Interface::FakeInput));
        const auto interface = registry.interface(KWayland::Client::Registry::Interface::FakeInput);
        QScopedPointer<KWayland::Client::FakeInput> input(registry.createFakeInput(interface.name, interface.version));
        QVERIFY(input->isValid());
        input->authenticate(QStringLiteral("Task Manager Smoke Test"), QStringLiteral("Test input in an isolated compositor"));
        const auto movePointer = [&input](const QPoint &position) {
            input->requestPointerMoveAbsolute(position);
            return QTest::qWaitFor([&position] { return QCursor::pos() == position; });
        };
        const auto sendKeys = [&input](const QList<quint32> &keys) {
            for (auto key : keys) {
                input->requestKeyboardKeyPress(key);
            }
            for (auto key = keys.crbegin(); key != keys.crend(); ++key) {
                input->requestKeyboardKeyRelease(*key);
            }
        };

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
        const QDir applications(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/applications"));
        QVERIFY(applications.mkpath(QStringLiteral(".")));
        QStringList launchers;
        for (int i = 0; i < 3; ++i) {
            const QString path = applications.filePath(QStringLiteral("org.kde.adjustabletaskmanager.smoke.launcher-%1.desktop").arg(i));
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
        QGuiApplication::setDesktopFileName(QStringLiteral("org.kde.adjustabletaskmanager.smoke.launcher-1"));

        auto *item = PlasmaQuick::AppletQuickItem::itemForApplet(applet);
        QVERIFY(item);
        QVERIFY2(!applet->failedToLaunch(), qPrintable(applet->launchErrorMessage()));
        // Plasma may also load a stock task manager in the same process.
        auto *stockApplet = containment->createApplet(QStringLiteral("org.kde.plasma.icontasks"));
        QVERIFY(stockApplet);
        QVERIFY(stockApplet->configuration()->setProperty("launchers", launchers));
        QVERIFY(stockApplet->configuration()->setProperty("showOnlyCurrentDesktop", false));
        QVERIFY(stockApplet->configuration()->setProperty("showOnlyCurrentActivity", false));
        auto *stockItem = PlasmaQuick::AppletQuickItem::itemForApplet(stockApplet);
        QVERIFY(stockItem);
        PlasmaQuick::Dialog window;
        window.setType(PlasmaQuick::Dialog::Dock);
        window.setBackgroundHints(PlasmaQuick::Dialog::NoBackground);
        window.resize(1600, 48);
        item->setParentItem(window.contentItem());
        item->setSize(QSizeF(1600, 48));
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));

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

        QVERIFY(movePointer(window.mapToGlobal(launcher->mapToScene(QPointF(24, 24)).toPoint())));
        QTRY_VERIFY(launcher->property("containsMouse").toBool());
        input->requestPointerButtonPress(Qt::RightButton);
        QTRY_VERIFY(launcher->property("contextMenu").value<QObject *>());
        auto *menu = launcher->property("contextMenu").value<QObject *>();
        QCOMPARE(menu->property("backend").value<QObject *>(), item->property("backend").value<QObject *>());
        QTRY_VERIFY(qobject_cast<QMenu *>(QApplication::activePopupWidget()));
        auto *popup = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        QVERIFY(QTest::qWaitForWindowExposed(popup->windowHandle()));
        input->requestPointerButtonRelease(Qt::RightButton);
        QVERIFY(!popup->actions().isEmpty());
        sendKeys({KEY_ESC});
        QTRY_VERIFY(!launcher->property("contextMenu").value<QObject *>());
        QVERIFY(!QFile::exists(launchMarker));
        // Keep a single eligible task manager for the shortcut checks below.
        // Removing the stock instance must leave the shared shortcuts working.
        delete stockApplet;

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

        // Plasma 6.8 also dispatches task cycling and reordering through the backend.
        QTRY_VERIFY(model->index(2, 0).data(TaskManager::AbstractTasksModel::IsActive).toBool());
        sendKeys({KEY_LEFTMETA, KEY_LEFTCTRL, KEY_PAGEUP});
        QTRY_VERIFY(model->index(1, 0).data(TaskManager::AbstractTasksModel::IsActive).toBool());
        sendKeys({KEY_LEFTMETA, KEY_LEFTCTRL, KEY_PAGEDOWN});
        QTRY_VERIFY(model->index(2, 0).data(TaskManager::AbstractTasksModel::IsActive).toBool());
        sendKeys({KEY_LEFTMETA, KEY_LEFTCTRL, KEY_LEFTSHIFT, KEY_PAGEUP});
        QTRY_COMPARE(model->index(1, 0).data(Qt::DisplayRole).toString(), QStringLiteral("Short"));
        sendKeys({KEY_LEFTMETA, KEY_LEFTCTRL, KEY_LEFTSHIFT, KEY_PAGEDOWN});
        QTRY_COMPARE(model->index(1, 0).data(Qt::DisplayRole).toString(), longTitle);
        QCOMPARE(model->index(2, 0).data(Qt::DisplayRole).toString(), QStringLiteral("Short"));
        QCOMPARE(model->launcherList(), launchers);

        if (const auto path = qEnvironmentVariable("TASK_MANAGER_SCREENSHOT"); !path.isEmpty()) {
            QTest::qWait(200);
            QVERIFY(window.grabWindow().save(path));
        }

        launchedWindow.setWindowState(Qt::WindowMinimized);
        secondWindow.setWindowState(Qt::WindowMinimized);
        QTRY_VERIFY(model->index(1, 0).data(TaskManager::AbstractTasksModel::IsMinimized).toBool());
        QTRY_VERIFY(model->index(2, 0).data(TaskManager::AbstractTasksModel::IsMinimized).toBool());
        QTRY_VERIFY(!model->activeTask().isValid());
        QVERIFY(!QFile::exists(launchMarker));
        sendKeys({KEY_LEFTMETA, KEY_2});
        QTRY_VERIFY(!model->index(2, 0).data(TaskManager::AbstractTasksModel::IsMinimized).toBool());
        QVERIFY(model->index(1, 0).data(TaskManager::AbstractTasksModel::IsMinimized).toBool());
        secondWindow.close();
        QTRY_COMPARE(model->index(2, 0).data(launcherRole), lastUrl);

        // Meta+1 must restore the first window even though a pinned icon precedes it.
        launchedWindow.setWindowState(Qt::WindowMinimized);
        QTRY_VERIFY(model->index(1, 0).data(TaskManager::AbstractTasksModel::IsMinimized).toBool());
        QTRY_VERIFY(!model->activeTask().isValid());
        sendKeys({KEY_LEFTMETA, KEY_1});
        QTRY_VERIFY(!model->index(1, 0).data(TaskManager::AbstractTasksModel::IsMinimized).toBool());
        QVERIFY(!QFile::exists(launchMarker));

        sendKeys({KEY_LEFTMETA, KEY_2});
        QTest::qWait(100);
        QVERIFY(!model->index(1, 0).data(TaskManager::AbstractTasksModel::IsMinimized).toBool());

        // Exercise a window action as well as opening the launcher's menu above.
        QVERIFY(movePointer(window.mapToGlobal(windowTask->mapToScene(QPointF(24, 24)).toPoint())));
        QTRY_VERIFY(windowTask->property("containsMouse").toBool());
        input->requestPointerButtonPress(Qt::RightButton);
        QTRY_VERIFY(qobject_cast<QMenu *>(QApplication::activePopupWidget()));
        popup = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        QVERIFY(QTest::qWaitForWindowExposed(popup->windowHandle()));
        input->requestPointerButtonRelease(Qt::RightButton);
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
        // Keyboard navigation does not depend on the compositor's popup placement.
        sendKeys({KEY_END});
        QTRY_COMPARE(popup->activeAction(), closeAction);
        sendKeys({KEY_ENTER});
        QTRY_VERIFY(model->index(1, 0).data(TaskManager::AbstractTasksModel::IsLauncher).toBool());
        QCOMPARE(model->index(1, 0).data(launcherRole), middleUrl);
        QCOMPARE(model->launcherList(), launchers);

        // With only launchers left, neither a valid number nor an out-of-range one may launch an app.
        sendKeys({KEY_LEFTMETA, KEY_1});
        sendKeys({KEY_LEFTMETA, KEY_9});
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
    QApplication app(argc, argv);
    KLocalizedString::setApplicationDomain("plasma_applet_org.kde.plasma.adjustabletaskmanager");
    SmokeTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "smoke.moc"
