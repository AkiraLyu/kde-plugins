#include <QApplication>
#include <QWidget>
#include <QPainter>
#include <QTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFile>
#include <QSaveFile>

class Backdrop : public QWidget {
public:
    Backdrop() { setWindowFlags(Qt::Tool|Qt::FramelessWindowHint|Qt::WindowStaysOnBottomHint); setWindowTitle("Backdrop"); resize(1200,900); }
    void paintEvent(QPaintEvent *) override {
        QPainter p(this);
        if (qEnvironmentVariableIsSet("WECHAT_GLASS_TEST_FLAT")) {
            p.fillRect(rect(), QColor(24,40,56));
            return;
        }
        for(int y=0;y<height();y+=8) for(int x=0;x<width();x+=8)
            p.fillRect(x,y,8,8,((x/8+y/8)%2) ? QColor(40,60,180) : QColor(230,210,80));
    }
};
class Popup : public QWidget {
public:
    Popup(QWidget *parent) : QWidget(parent,Qt::Tool|Qt::FramelessWindowHint) {
        setWindowTitle("Popup"); setAttribute(Qt::WA_TranslucentBackground); resize(240,240);
    }
    void paintEvent(QPaintEvent *) override {
        QPainter p(this); p.setRenderHint(QPainter::Antialiasing);
        p.setPen(Qt::NoPen); p.setBrush(QColor(0,0,0,25)); p.drawRoundedRect(QRectF(25,25,190,190),12,12);
        p.setBrush(QColor(248,248,248)); p.drawRoundedRect(QRectF(30,30,180,180),8,8);
        p.setPen(Qt::black); p.drawText(QRect(40,40,160,160),Qt::AlignCenter,"Popup content");
    }
};
class Main : public QWidget {
public:
    int frame=0; Popup popup{this};
    Main() { setWindowFlags(Qt::Window|Qt::FramelessWindowHint); setWindowTitle("WeChat"); resize(880,640); }
    void destroySurface() { destroy(); }
    void paintEvent(QPaintEvent *) override {
        QPainter p(this); p.fillRect(rect(),QColor(224,224,224));
        if(!frame) return;
        p.fillRect(QRect(61,33,width()-61,height()-33),QColor(250,250,250));
        p.fillRect(QRect(350,100,200,200), QColor(30+(frame*11)%180,180,100));
        p.setPen(Qt::black); p.drawText(QPoint(100,250),QString("Frame %1").arg(frame));
        // WeChat paints a 201-gray outline one physical pixel wide.
        const qreal edge=1.0/devicePixelRatioF();
        p.fillRect(QRectF(0,0,width(),edge),QColor(201,201,201));
        p.fillRect(QRectF(0,0,edge,height()),QColor(201,201,201));
        p.fillRect(QRectF(width()-edge,0,edge,height()),QColor(201,201,201));
        p.fillRect(QRectF(0,height()-edge,width(),edge),QColor(201,201,201));
    }
};
int main(int argc,char **argv) {
    QApplication app(argc,argv); app.setApplicationName("wechat");
    app.setQuitOnLastWindowClosed(false);
    Backdrop b; b.show(); b.move(0,0);
    Main w; w.show(); w.move(160,130);
    const QString root=qEnvironmentVariable("WECHAT_GLASS_TEST_DIR");
    QTimer::singleShot(2000,&w,[&]{ w.frame=1; w.update(); });
    QTimer timer;
    QByteArray lastAction;
    QObject::connect(&timer,&QTimer::timeout,&w,[&]{
        b.move(0,0);
        QFile command(root+"/command");
        if (!command.open(QIODevice::ReadOnly)) return;
        const auto action=command.readAll().trimmed();
        if (action != lastAction) {
            if (action == "hide") w.hide();
            if (action == "close") w.close();
            if (action == "destroy") w.destroySurface();
            if (action == "show") { w.show(); w.raise(); }
            lastAction = action;
        }
        const auto parts=action.split(' ');
        if(parts.size()==3 && parts[0]=="move") w.move(parts[1].toInt(),parts[2].toInt());
        if(action=="popup") { w.popup.move(w.pos()+QPoint(-20,200)); w.popup.show(); }
        else w.popup.hide();
        if(action=="resize") w.resize(928,664); else w.resize(880,640);
        if(w.frame) { ++w.frame; w.update(); }
        QSaveFile state(root+"/client.json");
        if (!state.open(QIODevice::WriteOnly)) return;
        state.write(QJsonDocument(QJsonObject{{"main",double(w.internalWinId())},{"popup",double(w.popup.winId())},
            {"action",QString::fromUtf8(action)},{"visible",w.isVisible()},
            {"frame",w.frame},{"x",w.x()},{"y",w.y()},{"width",w.width()},{"height",w.height()},
            {"dpr",w.devicePixelRatioF()},
            {"popup_x",w.popup.x()},{"popup_y",w.popup.y()}}).toJson()); state.commit();
    });
    timer.start(qEnvironmentVariableIsSet("WECHAT_GLASS_TEST_FAST_COMMANDS") ? 50 : 500);
    return app.exec();
}
