#ifndef StyleCheckDialog_h__
#define StyleCheckDialog_h__

#include <QDialog>
#include <QStringList>

// A window with the Qt controls that need care on macOS under Liquid Glass, each next to the same AppKit control, one
// kind of control on a tab:
// - the controls QMacStyle draws its own way with the patches of crystalidea/qt-build-tools
//   (patches/qtbase-macstyle-*.patch): QProgressBar, small push buttons, QSpinBox arrows, check boxes in item views, the
//   QLineEdit focus ring, the heights of QLineEdit and QSpinBox, the insets of their text and the QSpinBox stepper;
// - the native controls of qcocoacontrols: QCocoaComboBox, whose list opens as an NSMenu, next to a plain QComboBox,
//   and the pull-down buttons of QCocoaButtonActionMenu;
// - QTabWidget, which no patch changes yet, next to NSTabView.
// On a tour the window shows its tabs one by one, prints its window number and the geometry of the controls of each
// tab ("stylecheck ..." lines) and shoots the tab; the shots are analyzed by this geometry (stylecheck.sh,
// scanalyze.swift)

class QCocoaPopover;
class QLineEdit;
class QTabWidget;

class StyleCheckDialog : public QDialog
{
    Q_OBJECT

public:

    // scheme is the initial appearance, Unknown means the system one
    explicit StyleCheckDialog(Qt::ColorScheme scheme = Qt::ColorScheme::Unknown, QWidget *parent = nullptr);

    // Shows the tabs one by one, shoots each of them into dir and quits the app at the end. With menus the lists and
    // pull-down menus of a tab are opened and shot too
    void tour(const QString &dir, bool menus);

    void activate();

protected:

    // Escape closes the window, except on a tour
    void keyPressEvent(QKeyEvent *event) override;

private:

    QWidget *progressSection();
    QWidget *buttonSection();
    QWidget *spinSection();
    QWidget *comboSection();
    QWidget *viewSection();
    QWidget *editSection();
    QWidget *pullDownSection();
    QWidget *tabSection();
    QWidget *cocoaTabSection();
    QWidget *cocoaControlSection();
    QWidget *cocoaWindowSection();

    QCocoaPopover *openPopover(QWidget *anchor);
    int runAlert();
    QDialog *openPreferences();

    void focusPage();

    void startTour();
    void nextTab();
    void shootTab();
    void tabShot();
    void switchCocoaTab();
    void shootPopover();
    void shootAlert();
    void shootPreferences();
    void shootMenuBarPopover();
    void nextMenu();

    QTabWidget *m_tabs = nullptr;
    QLineEdit *m_focusEdit = nullptr;
    int m_activateAttempts = 0;

    QString m_shotDir;
    bool m_menuShots = false;
    int m_tab = -1;      // the tab of the tour
    QStringList m_menus; // the controls of the tab whose menus are still to be shot
    int m_cocoaTabChanges = 0; // currentChanged of the regular QCocoaTabWidget
};

#endif // StyleCheckDialog_h__
