#include "StyleCheckDialog.h"

#include <QApplication>
#include <QTimer>

// StyleCheck [light|dark] [--shots DIR [--menus]]: the system appearance without light or dark. With --shots the
// window shows its tabs one by one, shoots each of them into DIR and quits; with --menus it also shoots its open lists
// and pull-down menus
int main(int argc, char *argv[])
{
    // window containers of the AppKit controls must not make their sibling widgets native, as in our apps
    QCoreApplication::setAttribute(Qt::AA_DontCreateNativeWidgetSiblings, true);

    QApplication app(argc, argv);

    const QStringList args = app.arguments();
    Qt::ColorScheme scheme = Qt::ColorScheme::Unknown;

    if (args.contains("light"))
        scheme = Qt::ColorScheme::Light;
    else if (args.contains("dark"))
        scheme = Qt::ColorScheme::Dark;

    StyleCheckDialog dialog(scheme);
    dialog.show();

    QTimer::singleShot(0, &dialog, &StyleCheckDialog::activate);

    const qsizetype shots = args.indexOf("--shots");

    if (shots > 0 && shots + 1 < args.size())
        dialog.tour(args.at(shots + 1), args.contains("--menus"));

    return app.exec();
}
