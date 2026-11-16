#include "StyleCheckDialog.h"

#include <QtWidgets>

#include <cstdio>
#include <unistd.h>

#import <AppKit/AppKit.h>

#include <qcocoaappearance.h>
#include <qcocoabox.h>
#include <qcocoabutton.h>
#include <qcocoabuttonactionmenu.h>
#include <qcocoacombobox.h>
#include <qcocoagradientbutton.h>
#include <qcocoaicon.h>
#include <qcocoamenubaritem.h>
#include <qcocoamessagebox.h>
#include <qcocoapopover.h>
#include <qcocoapreferencesdialog.h>
#include <qcocoasegmentedbutton.h>
#include <qcocoaslider.h>
#include <qcocoatabwidget.h>

// A private but exported QtCore function (qcore_mac_p.h): QMacStyle draws the controls for Liquid Glass when it
// returns true, and only then the qtbase-macstyle-*.patch patches take effect
bool qt_apple_runningWithLiquidGlass();

namespace
{
    const int kWideWidth = 180; // progress bars and line edits have no width of their own

    // The bezel of an AppKit text field reaches 1 pt beyond its frame, QMacStyle draws it inside the widget. A Qt
    // field gets these points more at each side to look as wide as the AppKit one next to it
    const int kBezelOutset = 1;

    // the tab widgets on the Tabs tab, Qt and AppKit alike: three tabs and a page with a check box
    const int kTabsWidth = 300;
    const int kTabsHeight = 100;
const int kSliderWidth = 160;
const int kBoxWidth = 200;
const int kBoxHeight = 70;

    // the property of a QCocoaButtonActionMenu with its QMenu: the menu finds the NSPopUpButton of the control
    const char *kPullDownMenu = "styleCheckMenu";

    // the tabs of the window are named sc_group_<tab>, and <tab> names them in the report and in the shot files
    const QLatin1StringView kTabPrefix("sc_group_");

    NSFont *fontForSize(NSControlSize size)
    {
        return [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:size]];
    }

    // the tabs of the tab widgets on the Tabs tab
    QStringList tabTitles()
    {
        return {"General", "Fans", "Sensors"};
    }

    // the AppKit samples by their names, to open their menus
    QHash<QString, NSView *> &nativeViews()
    {
        static QHash<QString, NSView *> views;
        return views;
    }

    // An AppKit control in a Qt window: a foreign NSView in QWindow::fromWinId (Qt retains it) inside a window
    // container. The size is the one the control finds fitting, the width and the height can be given explicitly
    QWidget *nativeWidget(NSView *view, const char *name, int width = 0, int height = 0)
    {
        NSSize size = view.fittingSize;
        const NSSize intrinsic = view.intrinsicContentSize;

        if (intrinsic.height != NSViewNoIntrinsicMetric && intrinsic.height > size.height)
            size.height = intrinsic.height;

        if (width)
            size.width = width;

        if (height)
            size.height = height;

        [view setFrameSize:size];

        QWidget *widget = QWidget::createWindowContainer(QWindow::fromWinId(reinterpret_cast<WId>(view)));
        widget->setAttribute(Qt::WA_NativeWindow, true);
        widget->setFixedSize(qCeil(size.width), qCeil(size.height));
        widget->setObjectName(name);

        nativeViews().insert(name, view);

        return widget;
    }

    QWidget *nativeProgress(const char *name, double value, bool indeterminate)
    {
        NSProgressIndicator *indicator = [[[NSProgressIndicator alloc] init] autorelease];
        indicator.style = NSProgressIndicatorStyleBar;
        indicator.indeterminate = indeterminate;
        indicator.minValue = 0;
        indicator.maxValue = 100;
        indicator.doubleValue = value;

        if (indeterminate)
            [indicator startAnimation:nil];

        return nativeWidget(indicator, name, kWideWidth);
    }

    QWidget *nativeButton(const char *name, NSString *title, NSControlSize size, bool enabled = true)
    {
        NSButton *button = [NSButton buttonWithTitle:title target:nil action:nil];
        button.controlSize = size;
        button.font = fontForSize(size);
        button.enabled = enabled;

        return nativeWidget(button, name);
    }

    // a text field with a stepper is the AppKit counterpart of QSpinBox
    QWidget *nativeStepper(const char *name, NSControlSize size, bool enabled = true)
    {
        NSTextField *field = [NSTextField textFieldWithString:@"2400"];
        field.controlSize = size;
        field.font = fontForSize(size);
        field.enabled = enabled;
        [field.widthAnchor constraintEqualToConstant:64].active = YES;

        NSStepper *stepper = [[[NSStepper alloc] init] autorelease];
        stepper.controlSize = size;
        stepper.enabled = enabled;

        NSStackView *stack = [NSStackView stackViewWithViews:@[field, stepper]];
        stack.spacing = 2;

        return nativeWidget(stack, name);
    }

    QWidget *nativeCheckBox(const char *name, NSString *title, NSControlStateValue state, bool enabled = true)
    {
        NSButton *box = [NSButton checkboxWithTitle:title target:nil action:nil];
        box.allowsMixedState = YES;
        box.state = state;
        box.enabled = enabled;

        return nativeWidget(box, name);
    }

    QWidget *nativeTextField(const char *name, NSString *text, NSControlSize size, bool enabled = true,
                             NSTextAlignment alignment = NSTextAlignmentNatural)
    {
        NSTextField *field = [NSTextField textFieldWithString:text];
        field.controlSize = size;
        field.font = fontForSize(size);
        field.enabled = enabled;
        field.alignment = alignment;

        return nativeWidget(field, name, kWideWidth);
    }

    // an AppKit pop-up button with the items of the lists in comboSection()
    QWidget *nativePopUp(const char *name, const QIcon &icon)
    {
        NSPopUpButton *button = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO] autorelease];
        button.font = fontForSize(NSControlSizeRegular);
        button.autoenablesItems = NO;

        NSImage *image = QCocoaIcon::imageFromQIcon(icon);
        image.size = NSMakeSize(16, 16); // the icon size of QComboBox

        [button addItemWithTitle:@"Automatic"];
        [button.menu addItem:[NSMenuItem separatorItem]];
        [button addItemWithTitle:@"CPU Core Average"];
        button.lastItem.image = image;
        [button addItemWithTitle:@"GPU Cluster 1"];
        button.lastItem.image = image;
        [button addItemWithTitle:@"Disabled item"];
        button.lastItem.enabled = NO;

        return nativeWidget(button, name);
    }

    // A pull-down button with the toolbar bezel, like QCocoaButtonActionMenu, in the size it asks for itself. The
    // first item is the title of the button, the menu shows the items after it
    QWidget *nativePullDown(const char *name, NSString *title, NSArray<NSString *> *items, bool iconOnly)
    {
        NSPopUpButton *button = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES] autorelease];
        button.bezelStyle = NSBezelStyleToolbar;
        button.font = fontForSize(NSControlSizeRegular);
        button.autoenablesItems = NO;

        NSPopUpButtonCell *cell = button.cell;
        cell.usesItemFromMenu = YES;

        NSMenuItem *titleItem = [button.menu addItemWithTitle:title action:nil keyEquivalent:@""];

        if (iconOnly)
        {
            titleItem.image = [NSImage imageNamed:NSImageNameActionTemplate];
            button.imagePosition = NSImageOnly;
        }

        for (NSString *item in items)
            [button.menu addItemWithTitle:item action:nil keyEquivalent:@""];

        return nativeWidget(button, name);
    }

    // NSTabView with the tabs of the QTabWidget next to it, each page with a checked check box
    QWidget *nativeTabs(const char *name, NSControlSize size)
    {
        NSTabView *tabs = [[[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, kTabsWidth, kTabsHeight)] autorelease];
        tabs.controlSize = size;
        tabs.font = fontForSize(size);

        for (const QString &title : tabTitles())
        {
            NSButton *box = [NSButton checkboxWithTitle:@"Option" target:nil action:nil];
            box.controlSize = size;
            box.font = fontForSize(size);
            box.state = NSControlStateValueOn;
            box.translatesAutoresizingMaskIntoConstraints = NO;

            NSView *page = [[[NSView alloc] init] autorelease];
            [page addSubview:box];
            [box.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:12].active = YES;
            [box.topAnchor constraintEqualToAnchor:page.topAnchor constant:12].active = YES;

            NSTabViewItem *item = [[[NSTabViewItem alloc] initWithIdentifier:title.toNSString()] autorelease];
            item.label = title.toNSString();
            item.view = page;

            [tabs addTabViewItem:item];
        }

        return nativeWidget(tabs, name, kTabsWidth, kTabsHeight);
    }

    QProgressBar *progressBar(const char *name, int minimum, int maximum, int value)
    {
        QProgressBar *bar = new QProgressBar;
        bar->setObjectName(name);
        bar->setRange(minimum, maximum);
        bar->setTextVisible(false);
        bar->setFixedWidth(kWideWidth);

        // a value below the minimum keeps the initial state of the bar, as after reset(): an empty groove
        if (value >= minimum)
            bar->setValue(value);

        return bar;
    }

    template <class Widget>
    Widget *named(Widget *widget, const char *name, Qt::WidgetAttribute size = Qt::WA_MacNormalSize)
    {
        widget->setObjectName(name);
        widget->setAttribute(size);

        return widget;
    }

    QPushButton *pushButton(const char *name, const QString &title, Qt::WidgetAttribute size, bool enabled = true)
    {
        QPushButton *button = named(new QPushButton(title), name, size);
        button->setAutoDefault(false); // a default button is drawn in the accent color, the AppKit samples are plain
        button->setEnabled(enabled);

        return button;
    }

    QSpinBox *spinBox(const char *name, Qt::WidgetAttribute size, bool enabled = true)
    {
        QSpinBox *spin = named(new QSpinBox, name, size);
        spin->setRange(0, 6000);
        spin->setValue(2400);
        spin->setEnabled(enabled);

        return spin;
    }

    QLineEdit *lineEdit(const char *name, const QString &text, Qt::WidgetAttribute size = Qt::WA_MacNormalSize)
    {
        QLineEdit *edit = named(new QLineEdit(text), name, size);
        edit->setFixedWidth(kWideWidth + 2 * kBezelOutset);

        return edit;
    }

    // QTabWidget with the tabs of the NSTabView next to it. The tab bar gets the size attribute of its own:
    // QApplication::font() gives the small font only to a widget with the attribute, not to its children
    QTabWidget *tabWidget(const char *name, Qt::WidgetAttribute size)
    {
        QTabWidget *tabs = named(new QTabWidget, name, size);
        tabs->tabBar()->setAttribute(size);

        for (const QString &title : tabTitles())
        {
            QCheckBox *box = new QCheckBox("Option");
            box->setAttribute(size);
            box->setChecked(true);

            QWidget *page = new QWidget;
            QVBoxLayout *layout = new QVBoxLayout(page);
            layout->addWidget(box);
            layout->addStretch();

            tabs->addTab(page, title);
        }

        tabs->setFixedSize(kTabsWidth, kTabsHeight);

        return tabs;
    }

    // QCocoaTabWidget with the tabs of the NSTabView next to it. The tab widget takes the size attribute, as
    // WindowHelpers::Darwin::setWidgetSmallFont() of our apps gives it; the bar gets it too for the plain QTabWidget
    // QCocoaTabWidget is before macOS 27
    QCocoaTabWidget *cocoaTabWidget(const char *name, Qt::WidgetAttribute size)
    {
        QCocoaTabWidget *tabs = named(new QCocoaTabWidget, name, size);
        tabs->tabBar()->setAttribute(size);

        for (const QString &title : tabTitles())
        {
            QCheckBox *box = new QCheckBox("Option");
            box->setAttribute(size);
            box->setChecked(true);

            QWidget *page = new QWidget;
            QVBoxLayout *layout = new QVBoxLayout(page);
            layout->addWidget(box);
            layout->addStretch();

            tabs->addTab(page, title);
        }

        tabs->setFixedSize(kTabsWidth, kTabsHeight);

        return tabs;
    }

    // The native bar of a QCocoaTabWidget: the NSSegmentedControl over its QTabBar
    NSSegmentedControl *nativeTabBar(QTabWidget *tabs)
    {
        NSView *root = reinterpret_cast<NSView *>(tabs->window()->winId());
        const QRect bar(tabs->tabBar()->mapTo(tabs->window(), QPoint(0, 0)), tabs->tabBar()->size());
        NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObject:root];

        while (views.count)
        {
            NSView *view = views.lastObject;
            [views removeLastObject];

            if ([view isKindOfClass:[NSSegmentedControl class]])
            {
                const NSRect frame = [view convertRect:view.bounds toView:root];

                if (bar.contains(QPoint(qRound(NSMidX(frame)), qRound(NSMidY(frame)))))
                    return static_cast<NSSegmentedControl *>(view);
            }

            [views addObjectsFromArray:view.subviews];
        }

        return nil;
    }

    // A click of the mouse, as the window gets it from the system
    void postClick(NSView *view, NSPoint point)
    {
        const NSPoint location = [view convertPoint:point toView:nil];

        for (const NSEventType type : {NSEventTypeLeftMouseDown, NSEventTypeLeftMouseUp})
        {
            [NSApp postEvent:[NSEvent mouseEventWithType:type location:location modifierFlags:0
                                               timestamp:NSProcessInfo.processInfo.systemUptime
                                            windowNumber:view.window.windowNumber context:nil eventNumber:0
                                              clickCount:1 pressure:1]
                     atStart:NO];
        }
    }

    // A tab of the window: a line on what it checks, then what the caller puts into the layout
    QWidget *page(const char *name, const QString &checks, QVBoxLayout *&layout)
    {
        QWidget *tab = new QWidget;
        tab->setObjectName(name);

        layout = new QVBoxLayout(tab);
        layout->addWidget(new QLabel(checks));

        return tab;
    }

    // A tab with rows of the caption, the Qt control and the AppKit sample
    QWidget *section(const char *name, const QString &checks, QGridLayout *&grid)
    {
        QVBoxLayout *layout = nullptr;
        QWidget *tab = page(name, checks, layout);

        grid = new QGridLayout;
        grid->addWidget(new QLabel("Qt"), 0, 1);
        grid->addWidget(new QLabel("AppKit"), 0, 2);
        grid->setColumnStretch(3, 1);

        layout->addLayout(grid);
        layout->addStretch();

        return tab;
    }

    void addRow(QGridLayout *grid, const QString &caption, QWidget *qt, QWidget *native = nullptr)
    {
        const int row = grid->rowCount();
        const Qt::Alignment alignment = Qt::AlignLeft | Qt::AlignVCenter;

        grid->addWidget(new QLabel(caption), row, 0);
        grid->addWidget(qt, row, 1, alignment);

        if (native)
            grid->addWidget(native, row, 2, alignment);
    }

    // The lists and the pull-down buttons of a tab whose menus are shot, each Qt control followed by its AppKit sample.
    // The last step on the Lists tab chooses the next item of QCocoaComboBox with the keyboard
    QStringList menuSteps(const QString &tab)
    {
        if (tab == "combos")
            return {"sc_combo_qt", "sc_combo_native", "ns_combo", "sc_combo_native select"};

        if (tab == "pulldowns")
            return {"sc_pd_text", "ns_pd_text", "sc_pd_icon", "ns_pd_icon"};

        if (tab == "cocoawindows")
            return {"popover", "alert", "preferences", "menubar"};

        return {};
    }

    // The front window of this process above the level of normal windows: an open menu or the list of a QComboBox
    CGWindowID topPopUpWindow()
    {
        CGWindowID found = 0;
        CFArrayRef windows = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);

        // the list goes from the front to the back
        for (NSDictionary *info in (__bridge NSArray *)windows)
        {
            if ([info[(id)kCGWindowOwnerPID] intValue] == getpid() && [info[(id)kCGWindowLayer] intValue] > 0)
            {
                found = [info[(id)kCGWindowNumber] unsignedIntValue];
                break;
            }
        }

        if (windows)
            CFRelease(windows);

        return found;
    }

    // A shot of a window by its number. The display of a locked Mac goes dark now and then until the next wake from
    // caffeinate, which stylecheck.sh declares every 4 s, and the shots fail meanwhile: they are tried again for 6 s
    bool shootWindow(CGWindowID window, const QByteArray &path)
    {
        const QByteArray command = "screencapture -x -o -l " + QByteArray::number(window) + " '" + path + '\'';

        for (int attempt = 0; attempt < 8; ++attempt)
        {
            if (attempt)
                [NSThread sleepForTimeInterval:0.75];

            if (system(command.constData()) == 0)
                return true;
        }

        return false;
    }

    void postKey(unsigned short keyCode, NSString *characters)
    {
        NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                                         timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:0 context:nil
                                        characters:characters charactersIgnoringModifiers:characters isARepeat:NO
                                           keyCode:keyCode];
        [NSApp postEvent:event atStart:NO];
    }

    NSPopUpButton *findPopUpButton(NSView *view, NSMenu *menu)
    {
        if ([view isKindOfClass:[NSPopUpButton class]] && static_cast<NSPopUpButton *>(view).menu == menu)
            return static_cast<NSPopUpButton *>(view);

        for (NSView *subview in view.subviews)
        {
            if (NSPopUpButton *button = findPopUpButton(subview, menu))
                return button;
        }

        return nil;
    }

    // a shot of a region of the screen shows the lock screen on a locked Mac
    bool screenLocked()
    {
        CFDictionaryRef session = CGSessionCopyCurrentDictionary();
        const bool locked = session && [((__bridge NSDictionary *)session)[@"CGSSessionScreenIsLocked"] boolValue];

        if (session)
            CFRelease(session);

        return locked;
    }

    // The front window of this process other than the given one, below the menu bar: a sheet, a panel
    CGWindowID frontWindow(CGWindowID except)
    {
        CGWindowID found = 0;
        CFArrayRef windows = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);

        // the list goes from the front to the back
        for (NSDictionary *info in (__bridge NSArray *)windows)
        {
            const CGWindowID number = [info[(id)kCGWindowNumber] unsignedIntValue];

            if ([info[(id)kCGWindowOwnerPID] intValue] == getpid() && number != except &&
                [info[(id)kCGWindowLayer] intValue] < kCGStatusWindowLevel)
            {
                found = number;
                break;
            }
        }

        if (windows)
            CFRelease(windows);

        return found;
    }

    // The window of the open NSPopover of this process
    CGWindowID popoverWindow()
    {
        for (NSWindow *window in NSApp.windows)
        {
            if (window.visible && [NSStringFromClass([window class]) containsString:@"Popover"])
                return CGWindowID(window.windowNumber);
        }

        return 0;
    }

    // How a window is closed after its shot: a menu with Escape, or with Down and Return to choose the next item, an
    // alert with Return, which presses its default button. The caller closes the other windows itself
    enum class Close { Escape, NextItem, Return, ByCaller };

    // While an NSMenu is open, the main thread stays in its tracking loop until the menu closes. So a second after the
    // menu opens another thread shoots it and closes it with keys. The keys go to the event queue of the app and reach
    // the menu in an inactive app too. The list of QComboBox doesn't block, and popovers, alerts and other windows are
    // shot the same way.
    //
    // Two shots of each:
    // - <file>-menu.png by the number of the window: the one window() gives, or else the front window of this process
    //   above the normal ones, an open menu or the list of QComboBox. An NSMenu comes together with the window under
    //   it, cut to that window. It works on a locked Mac, as long as the display is on;
    // - <file>.png, the screen around the control, when there is a control and the Mac isn't locked.
    //
    // then, if given, runs on the main thread of the context once the keys are posted: the list of QComboBox doesn't
    // block, and the tour goes on from there
    void shootLater(const QString &dir, const QString &file, const QRect &control, Close close,
                    QObject *context = nullptr, const std::function<void()> &then = {},
                    const std::function<CGWindowID()> &window = {})
    {
        // an NSMenu opens over the control, the list of QComboBox below it; the region keeps to the screen
        QRect region(control.x() - 60, control.y() - 320, std::max(control.width(), 320) + 160, 960);

        if (const QScreen *screen = QGuiApplication::screenAt(control.center()))
            region = region.intersected(screen->geometry());

        const QByteArray regionShot = QString("screencapture -x -R %1,%2,%3,%4 '%5/%6.png'").arg(region.x())
            .arg(region.y()).arg(region.width()).arg(region.height()).arg(dir, file).toUtf8();
        const bool regionWanted = !control.isNull() && !screenLocked();

        // A block captures a C++ reference as a reference, and the objects behind dir, file, then and window are gone
        // by the time it runs: it gets copies of its own
        const QByteArray windowShot = QString("%1/%2-menu.png").arg(dir, file).toUtf8();
        const QByteArray name = file.toUtf8();
        const std::function<void()> next = then;
        const std::function<CGWindowID()> find = window;

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [NSThread sleepForTimeInterval:1.0];

            const CGWindowID number = find ? find() : topPopUpWindow();
            const bool shot = number && shootWindow(number, windowShot);
            const bool region = regionWanted && system(regionShot.constData()) == 0;

            printf("stylecheck menu %s window=%u menu=%d region=%d\n", name.constData(), number, int(shot), int(region));
            fflush(stdout);

            switch (close)
            {
            case Close::Escape:
                postKey(53, @"\e");
                break;

            case Close::NextItem:
                postKey(125, [NSString stringWithFormat:@"%C", unichar(NSDownArrowFunctionKey)]);
                [NSThread sleepForTimeInterval:0.3];
                postKey(36, @"\r");
                break;

            case Close::Return:
                postKey(36, @"\r");
                break;

            case Close::ByCaller:
                break;
            }

            if (next)
                QMetaObject::invokeMethod(context, next, Qt::QueuedConnection);
        });
    }

    NSButton *nativeButton(NSString *title, NSBezelStyle bezel)
    {
        NSButton *button = [NSButton buttonWithTitle:title target:nil action:nil];
        button.bezelStyle = bezel;
        [button sizeToFit];

        return button;
    }

    // What MFC shows in its popovers: a text, a check box and two buttons with the textured bezel of QCocoaButton. A
    // top-level widget, as QCocoaPopover wants it
    QWidget *popoverContents()
    {
        QWidget *contents = new QWidget;
        QVBoxLayout *layout = new QVBoxLayout(contents);

        QLabel *text = new QLabel("Fan control is limited on this Mac: the fans don't go below their minimum speed.");
        text->setWordWrap(true);
        text->setFixedWidth(280);
        layout->addWidget(text);

        QCheckBox *again = new QCheckBox("Don't show again");
        again->setAttribute(Qt::WA_MacSmallSize);
        layout->addWidget(again);

        QHBoxLayout *buttons = new QHBoxLayout;
        buttons->addStretch();

        for (const char *title : {"Close", "More Info"})
        {
            QCocoaButton *button = new QCocoaButton(contents);
            button->setBezelStyle(QCocoaButton::TexturedRounded);
            button->setText(title);
            buttons->addWidget(button);
        }

        layout->addLayout(buttons);

        return contents;
    }

    // A page of the sample preferences: the controls MFC has on its pages
    class SamplePreferencesPage : public QPreferencesPage
    {
    public:

        SamplePreferencesPage(const QString &title, QCocoaIcon::StandardIcon icon)
            : QPreferencesPage(nullptr), _title(title), _icon(icon)
        {
            QFormLayout *form = new QFormLayout(this);

            form->addRow(new QCheckBox("Start at login"));

            QComboBox *mode = new QCocoaComboBox;
            mode->addItems({"Automatic", "Constant RPM", "Sensor-based"});
            form->addRow("Fan mode:", mode);

            QSpinBox *speed = new QSpinBox;
            speed->setRange(0, 6000);
            speed->setValue(2400);
            form->addRow("Speed:", speed);
        }

        QString getTitle() const override
        {
            return _title;
        }

        QIcon getIcon() const override
        {
            return QIcon(QCocoaIcon::standardIcon(_icon, 32));
        }

        // the dialog takes the size the page has here
        void updateLayout() override
        {
            adjustSize();
        }

    private:

        QString _title;
        QCocoaIcon::StandardIcon _icon;
    };
}

StyleCheckDialog::StyleCheckDialog(Qt::ColorScheme scheme, QWidget *parent)
    : QDialog(parent)
{
    setWindowTitle("Style Check");

    QLabel *info = new QLabel(QString("Qt %1, style \"%2\", Liquid Glass: Qt %3, qcocoacontrols %4, macOS %5")
                              .arg(qVersion(), style()->name(), qt_apple_runningWithLiquidGlass() ? "yes" : "no",
                                   QCocoaAppearance::isLiquidGlass() ? "yes" : "no", QSysInfo::productVersion()));

    QComboBox *schemes = new QComboBox;
    schemes->addItems({"System", "Light", "Dark"});

    QObject::connect(schemes, &QComboBox::currentIndexChanged, schemes, [](int index) {
        const Qt::ColorScheme values[] = {Qt::ColorScheme::Unknown, Qt::ColorScheme::Light, Qt::ColorScheme::Dark};
        QGuiApplication::styleHints()->setColorScheme(values[index]);
    });

    if (scheme == Qt::ColorScheme::Light)
        schemes->setCurrentIndex(1);
    else if (scheme == Qt::ColorScheme::Dark)
        schemes->setCurrentIndex(2);

    QHBoxLayout *header = new QHBoxLayout;
    header->addWidget(info);
    header->addStretch();
    header->addWidget(new QLabel("Appearance:"));
    header->addWidget(schemes);

    // One kind of control on a tab. The lists and pull-down buttons stay at the top of their tabs: the shot of an open
    // NSMenu on a locked Mac is cut to the window (see shootLater())
    m_tabs = new QTabWidget;
    m_tabs->addTab(progressSection(), "Progress");
    m_tabs->addTab(buttonSection(), "Buttons");
    m_tabs->addTab(spinSection(), "Spin boxes");
    m_tabs->addTab(editSection(), "Line edits");
    m_tabs->addTab(viewSection(), "Item views");
    m_tabs->addTab(comboSection(), "Lists");
    m_tabs->addTab(pullDownSection(), "Pull-downs");
    m_tabs->addTab(tabSection(), "Tabs");
    m_tabs->addTab(cocoaTabSection(), "Native tabs");
    m_tabs->addTab(cocoaControlSection(), "Cocoa controls");
    m_tabs->addTab(cocoaWindowSection(), "Popovers");

    connect(m_tabs, &QTabWidget::currentChanged, this, &StyleCheckDialog::focusPage);

    QDialogButtonBox *buttons = new QDialogButtonBox(QDialogButtonBox::Close);
    QObject::connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);

    QVBoxLayout *layout = new QVBoxLayout(this);
    layout->addLayout(header);
    layout->addWidget(m_tabs);
    layout->addWidget(buttons);
}

QWidget *StyleCheckDialog::progressSection()
{
    QGridLayout *grid = nullptr;
    QWidget *tab = section("sc_group_progress", "Patch progressbar-liquid-glass", grid);

    addRow(grid, "60 %", progressBar("sc_pb_60", 0, 100, 60), nativeProgress("ns_pb_60", 60, false));
    addRow(grid, "70 of 20...120", progressBar("sc_pb_offset", 20, 120, 70));
    addRow(grid, "reset", progressBar("sc_pb_reset", 0, 100, -1), nativeProgress("ns_pb_0", 0, false));
    addRow(grid, "busy", progressBar("sc_pb_busy", 0, 0, 0), nativeProgress("ns_pb_busy", 0, true));

    // like a download bar: indeterminate first, then determinate
    QProgressBar *done = progressBar("sc_pb_busydone", 0, 0, 0);
    addRow(grid, "busy, then 30 %", done);

    QTimer::singleShot(1000, done, [done] {
        done->setRange(0, 100);
        done->setValue(30);
    });

    QProgressBar *disabled = progressBar("sc_pb_disabled", 0, 100, 60);
    disabled->setEnabled(false);
    addRow(grid, "disabled 60 %", disabled);

    return tab;
}

QWidget *StyleCheckDialog::buttonSection()
{
    QGridLayout *grid = nullptr;
    QWidget *tab = section("sc_group_buttons", "Patch small-pushbutton-margins", grid);

    addRow(grid, "regular", pushButton("sc_btn_regular", "Push Button", Qt::WA_MacNormalSize),
           nativeButton("ns_btn_regular", @"Push Button", NSControlSizeRegular));
    addRow(grid, "small", pushButton("sc_btn_small", "Small Button", Qt::WA_MacSmallSize),
           nativeButton("ns_btn_small", @"Small Button", NSControlSizeSmall));
    addRow(grid, "mini", pushButton("sc_btn_mini", "Mini Button", Qt::WA_MacMiniSize),
           nativeButton("ns_btn_mini", @"Mini Button", NSControlSizeMini));
    addRow(grid, "small, long title", pushButton("sc_btn_small_long", "Small button with a longer title", Qt::WA_MacSmallSize),
           nativeButton("ns_btn_small_long", @"Small button with a longer title", NSControlSizeSmall));
    addRow(grid, "small, disabled", pushButton("sc_btn_small_disabled", "Disabled", Qt::WA_MacSmallSize, false),
           nativeButton("ns_btn_small_disabled", @"Disabled", NSControlSizeSmall, false));

    return tab;
}

QWidget *StyleCheckDialog::spinSection()
{
    QGridLayout *grid = nullptr;
    QWidget *tab = section("sc_group_spin",
                           "Patches spinbox-arrows, textfield-heights, textfield-insets, textfield-stepper", grid);

    // a Qt spin box as wide as the AppKit field and stepper next to it; the stepper stays within its frame, so only
    // the field side gets the outset
    auto spinRow = [&](const char *caption, QSpinBox *qt, QWidget *native) {
        qt->setFixedWidth(native->width() + kBezelOutset);
        addRow(grid, caption, qt, native);
    };

    spinRow("regular", spinBox("sc_spin_regular", Qt::WA_MacNormalSize), nativeStepper("ns_spin_regular", NSControlSizeRegular));
    spinRow("small", spinBox("sc_spin_small", Qt::WA_MacSmallSize), nativeStepper("ns_spin_small", NSControlSizeSmall));
    spinRow("mini", spinBox("sc_spin_mini", Qt::WA_MacMiniSize), nativeStepper("ns_spin_mini", NSControlSizeMini));

    QDoubleSpinBox *real = named(new QDoubleSpinBox, "sc_spin_double");
    real->setRange(0, 100);
    real->setValue(42.5);
    addRow(grid, "double", real);

    spinRow("disabled", spinBox("sc_spin_disabled", Qt::WA_MacNormalSize, false),
            nativeStepper("ns_spin_disabled", NSControlSizeRegular, false));

    return tab;
}

QWidget *StyleCheckDialog::comboSection()
{
    QGridLayout *grid = nullptr;
    QWidget *tab = section("sc_group_combos", "QCocoaComboBox of qcocoacontrols next to a plain QComboBox", grid);

    // The same items in every list: a plain one, a separator, two with an icon, a disabled one. QMacStyle draws both
    // closed Qt lists the same way, they differ when open: QComboBox shows a list drawn by Qt, QCocoaComboBox an
    // NSMenu, like the AppKit pop-up button next to it
    const QIcon icon = style()->standardIcon(QStyle::SP_DriveHDIcon);

    auto fill = [&icon](QComboBox *combo) {
        combo->addItem("Automatic");
        combo->insertSeparator(1);
        combo->addItem(icon, "CPU Core Average");
        combo->addItem(icon, "GPU Cluster 1");
        combo->addItem("Disabled item");

        if (QStandardItemModel *model = qobject_cast<QStandardItemModel *>(combo->model()))
            model->item(combo->count() - 1)->setEnabled(false);
    };

    QComboBox *qtList = named(new QComboBox, "sc_combo_qt");
    fill(qtList);
    addRow(grid, "Qt list", qtList);

    QCocoaComboBox *nativeList = named(new QCocoaComboBox, "sc_combo_native");
    fill(nativeList);
    addRow(grid, "native list", nativeList, nativePopUp("ns_combo", icon));

    return tab;
}

QWidget *StyleCheckDialog::viewSection()
{
    QVBoxLayout *layout = nullptr;
    QWidget *tab = page("sc_group_views", "Patch itemview-checkboxes", layout);

    // checked, unchecked, partially checked, checked and disabled; the first row is selected
    const Qt::CheckState states[] = {Qt::Checked, Qt::Unchecked, Qt::PartiallyChecked, Qt::Checked};

    QStandardItemModel *fans = new QStandardItemModel(0, 2, tab);
    fans->setHorizontalHeaderLabels({"Fan", "Speed"});

    for (int i = 0; i < 4; ++i)
    {
        QStandardItem *item = new QStandardItem(QString("Fan %1").arg(i + 1));
        item->setCheckable(true);
        item->setCheckState(states[i]);
        item->setEnabled(i != 3);

        fans->appendRow({item, new QStandardItem(QString("%1 rpm").arg(1200 + i * 300))});
    }

    QTableView *table = named(new QTableView, "sc_table");
    table->setModel(fans);
    table->verticalHeader()->hide();
    table->horizontalHeader()->setStretchLastSection(true);
    table->selectRow(0);
    table->setFixedSize(240, 140);

    QStandardItemModel *sensors = new QStandardItemModel(tab);
    QStandardItem *group = new QStandardItem("Sensors");
    group->setCheckable(true);
    group->setCheckState(Qt::PartiallyChecked);

    for (int i = 0; i < 3; ++i)
    {
        QStandardItem *item = new QStandardItem(QString("Sensor %1").arg(i + 1));
        item->setCheckable(true);
        item->setCheckState(states[i]);
        group->appendRow(item);
    }

    sensors->appendRow(group);

    QTreeView *tree = named(new QTreeView, "sc_tree");
    tree->setModel(sensors);
    tree->setHeaderHidden(true);
    tree->expandAll();
    tree->setCurrentIndex(sensors->index(0, 0, sensors->index(0, 0)));
    tree->setFixedSize(180, 140);

    QListWidget *list = named(new QListWidget, "sc_list");

    for (int i = 0; i < 4; ++i)
    {
        QListWidgetItem *item = new QListWidgetItem(QString("Item %1").arg(i + 1), list);
        item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
        item->setCheckState(states[i]);

        if (i == 3)
            item->setFlags(item->flags() & ~Qt::ItemIsEnabled);
    }

    list->setCurrentRow(0);
    list->setFixedSize(140, 140);

    QHBoxLayout *views = new QHBoxLayout;
    views->addWidget(table);
    views->addWidget(tree);
    views->addWidget(list);
    views->addStretch();

    // the patch doesn't touch plain check boxes: they are here to compare with the ones in item views
    QCheckBox *checked = named(new QCheckBox("Checked"), "sc_check_on");
    checked->setChecked(true);

    QCheckBox *unchecked = named(new QCheckBox("Unchecked"), "sc_check_off");

    QCheckBox *mixed = named(new QCheckBox("Mixed"), "sc_check_mixed");
    mixed->setTristate(true);
    mixed->setCheckState(Qt::PartiallyChecked);

    QCheckBox *disabled = named(new QCheckBox("Disabled"), "sc_check_disabled");
    disabled->setChecked(true);
    disabled->setEnabled(false);

    QHBoxLayout *qtBoxes = new QHBoxLayout;
    qtBoxes->addWidget(new QLabel("Qt"));

    for (QCheckBox *checkBox : {checked, unchecked, mixed, disabled})
        qtBoxes->addWidget(checkBox);

    qtBoxes->addStretch();

    QHBoxLayout *nativeBoxes = new QHBoxLayout;
    nativeBoxes->addWidget(new QLabel("AppKit"));
    nativeBoxes->addWidget(nativeCheckBox("ns_check_on", @"Checked", NSControlStateValueOn));
    nativeBoxes->addWidget(nativeCheckBox("ns_check_off", @"Unchecked", NSControlStateValueOff));
    nativeBoxes->addWidget(nativeCheckBox("ns_check_mixed", @"Mixed", NSControlStateValueMixed));
    nativeBoxes->addWidget(nativeCheckBox("ns_check_disabled", @"Disabled", NSControlStateValueOn, false));
    nativeBoxes->addStretch();

    layout->addLayout(views);
    layout->addLayout(qtBoxes);
    layout->addLayout(nativeBoxes);
    layout->addStretch();

    return tab;
}

QWidget *StyleCheckDialog::editSection()
{
    QGridLayout *grid = nullptr;
    QWidget *tab = section("sc_group_edits", "Patches lineedit-focus-ring, textfield-heights, textfield-insets", grid);

    m_focusEdit = lineEdit("sc_edit_focused", "Focused line edit");
    addRow(grid, "focused", m_focusEdit, nativeTextField("ns_edit_regular", @"Text field", NSControlSizeRegular));

    addRow(grid, "normal", lineEdit("sc_edit_normal", "Line edit"));

    // the text at the end of the field: how far it stays from the other edge of the bezel
    QLineEdit *right = lineEdit("sc_edit_right", "Aligned right");
    right->setAlignment(Qt::AlignRight | Qt::AlignVCenter);
    addRow(grid, "aligned right", right,
           nativeTextField("ns_edit_right", @"Aligned right", NSControlSizeRegular, true, NSTextAlignmentRight));

    QLineEdit *custom = lineEdit("sc_edit_custom", "Custom background");
    QPalette palette = custom->palette();
    palette.setColor(QPalette::Base, QColor("#fff2b3"));
    palette.setColor(QPalette::Text, Qt::black);
    custom->setPalette(palette);
    addRow(grid, "custom base", custom);

    QLineEdit *placeholder = lineEdit("sc_edit_placeholder", QString());
    placeholder->setPlaceholderText("Placeholder");
    addRow(grid, "placeholder", placeholder);

    addRow(grid, "small", lineEdit("sc_edit_small", "Small line edit", Qt::WA_MacSmallSize),
           nativeTextField("ns_edit_small", @"Small text field", NSControlSizeSmall));

    QLineEdit *disabled = lineEdit("sc_edit_disabled", "Disabled");
    disabled->setEnabled(false);
    addRow(grid, "disabled", disabled, nativeTextField("ns_edit_disabled", @"Disabled", NSControlSizeRegular, false));

    return tab;
}

QWidget *StyleCheckDialog::pullDownSection()
{
    QGridLayout *grid = nullptr;
    QWidget *tab = section("sc_group_pulldowns", "QCocoaButtonActionMenu of qcocoacontrols", grid);

    // a choice of presets with its title and an action button with an icon only; the AppKit samples have the same
    // items and the size they ask for themselves
    QMenu *presets = new QMenu(tab);
    presets->addAction("Automatic");
    presets->addAction("A rather long preset name");

    QCocoaButtonActionMenu *preset = new QCocoaButtonActionMenu(nullptr);
    preset->setObjectName("sc_pd_text");
    preset->setMenu(presets);
    preset->setText("A rather long preset name");
    preset->setProperty(kPullDownMenu, QVariant::fromValue(presets));

    addRow(grid, "text", preset,
           nativePullDown("ns_pd_text", @"A rather long preset name", @[@"Automatic", @"A rather long preset name"], false));

    QMenu *actions = new QMenu(tab);
    actions->addAction("Rename");

    QCocoaButtonActionMenu *action = new QCocoaButtonActionMenu(nullptr);
    action->setObjectName("sc_pd_icon");
    action->setIconPosition(QCocoaButton::IconOnly);
    action->setMenu(actions);
    action->setIcon(QCocoaIcon::Action);
    action->setProperty(kPullDownMenu, QVariant::fromValue(actions));

    addRow(grid, "icon only", action, nativePullDown("ns_pd_icon", @"", @[@"Rename"], true));

    return tab;
}

QWidget *StyleCheckDialog::tabSection()
{
    QGridLayout *grid = nullptr;
    QWidget *tab = section("sc_group_tabs", "QTabWidget without patches, as QMacStyle draws it", grid);

    addRow(grid, "regular", tabWidget("sc_tabs_regular", Qt::WA_MacNormalSize),
           nativeTabs("ns_tabs_regular", NSControlSizeRegular));
    addRow(grid, "small", tabWidget("sc_tabs_small", Qt::WA_MacSmallSize), nativeTabs("ns_tabs_small", NSControlSizeSmall));

    // an app at work often leaves only the current tab enabled; NSTabView has no disabled tabs
    QTabWidget *disabled = tabWidget("sc_tabs_disabled", Qt::WA_MacNormalSize);
    disabled->setTabEnabled(1, false);
    disabled->setTabEnabled(2, false);
    addRow(grid, "disabled tabs", disabled);

    return tab;
}

QWidget *StyleCheckDialog::cocoaTabSection()
{
    QCocoaTabWidget *regular = cocoaTabWidget("sc_cocoa_tabs_regular", Qt::WA_MacNormalSize);

    const QString checks = regular->hasNativeTabBar()
        ? "QCocoaTabWidget of qcocoacontrols next to NSTabView"
        : "QCocoaTabWidget of qcocoacontrols, a plain QTabWidget here: its native bar needs macOS 26 and Liquid Glass";

    QGridLayout *grid = nullptr;
    QWidget *tab = section("sc_group_cocoatabs", checks, grid);

    addRow(grid, "regular", regular, nativeTabs("ns_cocoa_tabs_regular", NSControlSizeRegular));
    addRow(grid, "small", cocoaTabWidget("sc_cocoa_tabs_small", Qt::WA_MacSmallSize),
           nativeTabs("ns_cocoa_tabs_small", NSControlSizeSmall));

    // as an app leaves it while it works: AppKit 27.0 draws the disabled tabs of this bar like the enabled ones
    QCocoaTabWidget *disabled = cocoaTabWidget("sc_cocoa_tabs_disabled", Qt::WA_MacNormalSize);
    disabled->tabBar()->setTabEnabled(1, false);
    disabled->tabBar()->setTabEnabled(2, false);
    addRow(grid, "disabled tabs", disabled);

    QObject::connect(regular, &QTabWidget::currentChanged, this, [this] { ++m_cocoaTabChanges; });

    return tab;
}

QWidget *StyleCheckDialog::cocoaControlSection()
{
    QGridLayout *grid = nullptr;
    QWidget *tab = section("sc_group_cocoacontrols",
                           "Controls of qcocoacontrols, native views in a Qt layout, next to the same AppKit controls", grid);

    // the help button of the main window of MFC
    QCocoaButton *help = named(new QCocoaButton(nullptr), "sc_cb_help");
    help->setBezelStyle(QCocoaButton::HelpButton);
    addRow(grid, "help button", help, nativeWidget(nativeButton(@"", NSBezelStyleHelpButton), "ns_cb_help"));

    // the buttons of the popovers of MFC
    QCocoaButton *textured = named(new QCocoaButton(nullptr), "sc_cb_textured");
    textured->setBezelStyle(QCocoaButton::TexturedRounded);
    textured->setText("More Info");
    addRow(grid, "textured rounded", textured,
           nativeWidget(nativeButton(@"More Info", NSBezelStyle(QCocoaButton::TexturedRounded)), "ns_cb_textured"));

    // the Auto and Custom switch of a fan in MFC; QCocoaSegmentedButton takes the small font
    QCocoaSegmentedButton *segmented = named(new QCocoaSegmentedButton, "sc_cb_segmented");
    segmented->setSegmentStyle(QCocoaSegmentedButton::SegmentStyleRounded);
    segmented->setSegmentCount(2);
    segmented->setTrackingMode(QCocoaSegmentedButton::NSSegmentSwitchTrackingSelectOne);
    segmented->setSegmentTitle(0, "Auto");
    segmented->setSegmentTitle(1, "Custom…");
    segmented->setSegmentChecked(0, true);

    NSSegmentedControl *nativeSegmented = [NSSegmentedControl segmentedControlWithLabels:@[@"Auto", @"Custom…"]
                                                                            trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                                  target:nil action:nil];
    nativeSegmented.segmentStyle = NSSegmentStyleRounded;
    nativeSegmented.font = [NSFont controlContentFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
    nativeSegmented.selectedSegment = 0;
    [nativeSegmented sizeToFit];
    addRow(grid, "segmented", segmented, nativeWidget(nativeSegmented, "ns_cb_segmented"));

    QCocoaSlider *slider = named(new QCocoaSlider, "sc_cb_slider");
    slider->setRange(0, 100);
    slider->setValue(40);
    slider->setFixedWidth(kSliderWidth);
    addRow(grid, "slider", slider,
           nativeWidget([NSSlider sliderWithValue:40 minValue:0 maxValue:100 target:nil action:nil], "ns_cb_slider",
                        kSliderWidth));

    // the contents of QCocoaBox are Qt widgets inside the native box
    QCocoaBox *box = named(new QCocoaBox, "sc_cb_box");
    box->setTitle("Box");
    box->setContentWidget(new QLabel("Contents"));
    box->setFixedSize(kBoxWidth, kBoxHeight);

    NSBox *nativeBox = [[[NSBox alloc] initWithFrame:NSMakeRect(0, 0, kBoxWidth, kBoxHeight)] autorelease];
    nativeBox.title = @"Box";
    NSTextField *contents = [NSTextField labelWithString:@"Contents"];
    contents.frameOrigin = NSMakePoint(8, 8);
    [nativeBox.contentView addSubview:contents];
    addRow(grid, "box", box, nativeWidget(nativeBox, "ns_cb_box", kBoxWidth, kBoxHeight));

    // the buttons under a list, as in System Settings: add, remove and an empty disabled segment up to the width
    QWidget *gradient = new QWidget;
    gradient->setObjectName("sc_cb_gradient");
    QVBoxLayout *column = new QVBoxLayout(gradient);
    column->setContentsMargins(0, 0, 0, 0);
    column->setSpacing(0);

    QListWidget *list = new QListWidget;
    list->addItems({"Silent", "Default"});
    list->setFixedSize(kBoxWidth, 52);

    QCocoaGradientButton *buttons = new QCocoaGradientButton;
    buttons->setSegmentCount(2);
    buttons->setSegmentIcon(0, QCocoaIcon::Add);
    buttons->setSegmentIcon(1, QCocoaIcon::Remove);
    buttons->attachToWidget(list);

    column->addWidget(list);
    column->addWidget(buttons);

    NSSegmentedControl *nativeGradient = [[[NSSegmentedControl alloc] initWithFrame:NSZeroRect] autorelease];
    nativeGradient.segmentStyle = NSSegmentStyleSmallSquare;
    nativeGradient.trackingMode = NSSegmentSwitchTrackingMomentary;
    nativeGradient.segmentCount = 3;
    [nativeGradient setImage:[NSImage imageNamed:NSImageNameAddTemplate] forSegment:0];
    [nativeGradient setImage:[NSImage imageNamed:NSImageNameRemoveTemplate] forSegment:1];
    [nativeGradient setEnabled:NO forSegment:2];
    [nativeGradient setWidth:24 forSegment:0];
    [nativeGradient setWidth:24 forSegment:1];
    [nativeGradient setWidth:kBoxWidth - 52 forSegment:2];
    [nativeGradient sizeToFit];
    addRow(grid, "gradient buttons", gradient, nativeWidget(nativeGradient, "ns_cb_gradient"));

    return tab;
}

QWidget *StyleCheckDialog::cocoaWindowSection()
{
    QVBoxLayout *layout = nullptr;
    QWidget *tab = page("sc_group_cocoawindows",
                        "Windows of qcocoacontrols: QCocoaPopover, QCocoaMessageBox, QCocoaPreferencesDialog and a popover "
                        "from the menu bar,\nas MFC shows them. With --menus the tour opens and shoots each", layout);

    QGridLayout *grid = new QGridLayout;
    grid->setColumnStretch(2, 1);
    layout->addLayout(grid);
    layout->addStretch();

    QPushButton *popover = pushButton("sc_open_popover", "Popover…", Qt::WA_MacNormalSize);
    connect(popover, &QPushButton::clicked, this, [this, popover] { openPopover(popover); });
    addRow(grid, "popover", popover);

    QPushButton *alert = pushButton("sc_open_alert", "Alert…", Qt::WA_MacNormalSize);
    connect(alert, &QPushButton::clicked, this, [this] { runAlert(); });
    addRow(grid, "alert, a sheet", alert);

    QPushButton *preferences = pushButton("sc_open_preferences", "Preferences…", Qt::WA_MacNormalSize);
    connect(preferences, &QPushButton::clicked, this, [this] { openPreferences(); });
    addRow(grid, "preferences", preferences);

    return tab;
}

QCocoaPopover *StyleCheckDialog::openPopover(QWidget *anchor)
{
    // a popover of its own for each click; the closed ones stay with the window
    QCocoaPopover *popover = new QCocoaPopover(this, popoverContents());
    popover->show(anchor);

    return popover;
}

int StyleCheckDialog::runAlert()
{
    // with a parent the alert is a sheet of its window, in a modal loop of AppKit
    QCocoaMessageBox box(QMessageBox::Question, "Style Check", "Delete the preset “Silent”?",
                         QMessageBox::Yes | QMessageBox::No, this);
    box.setInformativeText("Its fans go back to the automatic control.");
    box.setCheckBox(new QCheckBox("Don't ask again"));
    box.setDefaultButton(QMessageBox::Yes);

    return box.exec();
}

QDialog *StyleCheckDialog::openPreferences()
{
    QCocoaPreferencesDialog *dialog = new QCocoaPreferencesDialog(this);
    dialog->setAttribute(Qt::WA_DeleteOnClose);
    dialog->addPage(new SamplePreferencesPage("General", QCocoaIcon::PreferencesGeneral));
    dialog->addPage(new SamplePreferencesPage("Advanced", QCocoaIcon::Advanced), true);

    dialog->show();
    dialog->raise();
    dialog->activateWindow();

    return dialog;
}

void StyleCheckDialog::shootPopover()
{
    QWidget *anchor = findChild<QWidget *>("sc_open_popover");
    activate();

    QCocoaPopover *popover = openPopover(anchor);
    const CGWindowID window = popoverWindow();
    const QRect area(anchor->mapToGlobal(QPoint(0, 0)), anchor->size());

    // a transient popover closes on Escape; the line tells whether it did
    shootLater(m_shotDir, "sc_popover", area, Close::Escape, this, [this, popover] {
        QTimer::singleShot(600, this, [this, popover] {
            printf("stylecheck popover escape=%d\n", int(popoverWindow() == 0));
            fflush(stdout);

            popover->close();
            nextMenu();
        });
    }, [window] { return window; });
}

void StyleCheckDialog::shootAlert()
{
    activate();

    // exec() runs until Return presses the default button
    const CGWindowID main = CGWindowID(reinterpret_cast<NSView *>(winId()).window.windowNumber);
    shootLater(m_shotDir, "sc_alert", QRect(), Close::Return, nullptr, {}, [main] { return frontWindow(main); });

    const int result = runAlert();

    printf("stylecheck alert result=%d yes=%d\n", result, int(result == QMessageBox::Yes));
    fflush(stdout);

    QTimer::singleShot(800, this, &StyleCheckDialog::nextMenu);
}

void StyleCheckDialog::shootPreferences()
{
    QPointer<QDialog> dialog = openPreferences();
    const CGWindowID window = CGWindowID(reinterpret_cast<NSView *>(dialog->winId()).window.windowNumber);

    // the first page, then the second one the toolbar switches to, and the window closes
    shootLater(m_shotDir, "sc_preferences", QRect(), Close::ByCaller, this, [this, dialog, window] {
        if (dialog)
            QMetaObject::invokeMethod(dialog, "toolbarButtonActivated", Q_ARG(int, 1));

        shootLater(m_shotDir, "sc_preferences-2", QRect(), Close::ByCaller, this, [this, dialog] {
            printf("stylecheck preferences title=\"%s\"\n", dialog ? qPrintable(dialog->windowTitle()) : "");
            fflush(stdout);

            if (dialog)
                dialog->close();

            QTimer::singleShot(600, this, &StyleCheckDialog::nextMenu);
        }, [window] { return window; });
    }, [window] { return window; });
}

void StyleCheckDialog::shootMenuBarPopover()
{
    // MFC makes the status item itself and gives it to QCocoaMenubarItem. The menu bar places a new item a moment
    // later, and the popover opens under it only then
    NSStatusItem *statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength] retain];
    statusItem.button.image = [NSImage imageWithSystemSymbolName:@"fan" accessibilityDescription:@"Style Check"];

    QTimer::singleShot(1000, this, [this, statusItem] {
        QCocoaMenubarItem *item = new QCocoaMenubarItem(this, WId(statusItem));
        QCocoaPopover *popover = new QCocoaPopover(this, popoverContents());
        popover->setPopoverBehavior(QCocoaPopover::PopoverBehavior::ApplicationDefined);
        popover->show(item);

        QTimer::singleShot(300, this, [this, statusItem, item, popover] {
            const CGWindowID window = popoverWindow();

            // the region under the item, in the coordinates of Qt, which count from the top of the main screen; none
            // if the menu bar has no room for the item
            NSButton *button = statusItem.button;
            QRect area;

            if (button.window)
            {
                const NSRect onScreen = [button.window convertRectToScreen:[button convertRect:button.bounds toView:nil]];
                const CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame);
                area = QRect(qRound(NSMidX(onScreen)) - 200, qRound(top - NSMaxY(onScreen)), 400, qRound(NSHeight(onScreen)));
            }

            printf("stylecheck menubar item=%d,%d popover=%u\n", area.center().x(), area.y(), window);
            fflush(stdout);

            shootLater(m_shotDir, "sc_menubar_popover", area, Close::ByCaller, this, [this, popover, item, statusItem] {
                // the object goes while the popover closes with its animation, which AppKit reports later
                popover->close();
                delete popover; // and its contents
                delete item;

                [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
                [statusItem release];

                QTimer::singleShot(1500, this, &StyleCheckDialog::nextMenu);
            }, [window] { return window; });
        });
    });
}

void StyleCheckDialog::tour(const QString &dir, bool menus)
{
    m_shotDir = dir;
    m_menuShots = menus;

    // the "busy, then 30 %" bar becomes determinate after a second, so the tour starts later
    QTimer::singleShot(2500, this, &StyleCheckDialog::startTour);
}

void StyleCheckDialog::activate()
{
    // An inactive window has no focus ring and gray progress bars: QMacStyle colors them in the active window only
    raise();
    activateWindow();
    [NSApp activateIgnoringOtherApps:YES];

    focusPage();
}

void StyleCheckDialog::focusPage()
{
    // The focus ring is checked on the focused line edit. On the other tabs no control has the focus: QStackedWidget
    // gives it to a control of the new page when it was on the old one, and its focus ring would show in the shot
    if (m_focusEdit->isVisible())
        m_focusEdit->setFocus();
    else if (QWidget *focus = focusWidget())
        focus->clearFocus();
}

void StyleCheckDialog::startTour()
{
    // macOS may not give the focus to an app started from behind another window. Ask again, but no longer than 5 s:
    // then the tabs are shot as they are, in an inactive window. A locked Mac doesn't give it at all
    const bool locked = screenLocked();

    if (!isActiveWindow() && !locked && m_activateAttempts++ < 10)
    {
        activate();
        QTimer::singleShot(500, this, &StyleCheckDialog::startTour);
        return;
    }

    NSWindow *window = reinterpret_cast<NSView *>(winId()).window;
    const NSRect frame = window.frame;
    const NSRect content = [window contentRectForFrameRect:frame];

    // top is the title bar height: a window shot starts at the frame, the control coordinates at the content
    printf("stylecheck ready window=%ld scale=%g top=%g liquidglass=%d scheme=%s locked=%d\n",
           long(window.windowNumber), double(window.backingScaleFactor), double(NSHeight(frame) - NSHeight(content)),
           int(qt_apple_runningWithLiquidGlass()),
           QGuiApplication::styleHints()->colorScheme() == Qt::ColorScheme::Dark ? "dark" : "light", int(locked));
    fflush(stdout);

    nextTab();
}

void StyleCheckDialog::nextTab()
{
    if (++m_tab >= m_tabs->count())
    {
        printf("stylecheck end\n");
        fflush(stdout);

        qApp->quit();
        return;
    }

    m_tabs->setCurrentIndex(m_tab);
    activate();

    // the page lays itself out and the AppKit controls on it show up
    QTimer::singleShot(1000, this, &StyleCheckDialog::shootTab);
}

void StyleCheckDialog::shootTab()
{
    QWidget *page = m_tabs->currentWidget();
    const QString tab = page->objectName().mid(kTabPrefix.size());

    // A window that becomes active again without a focus widget gives the focus to the first control of the page, so
    // the focus is settled once more just before the shot
    focusPage();

    printf("stylecheck tab %s active=%d focus=%d\n", qPrintable(tab), int(isActiveWindow()), int(m_focusEdit->hasFocus()));

    // the page itself, which the analyzer crops, and the controls on it; those on the hidden pages of the tab widgets
    // on the Tabs tab are left out
    QList<QWidget *> widgets = page->findChildren<QWidget *>();
    widgets.prepend(page);

    for (QWidget *widget : std::as_const(widgets))
    {
        const QString name = widget->objectName();

        if (!widget->isVisible() || (!name.startsWith("sc_") && !name.startsWith("ns_")))
            continue;

        const QPoint at = widget->mapTo(this, QPoint(0, 0));

        printf("stylecheck rect %s %d %d %d %d\n", qPrintable(name), at.x(), at.y(), widget->width(), widget->height());
    }

    fflush(stdout);

    // the indeterminate bars move from frame to frame; nothing moves on the other tabs
    const int frames = tab == "progress" ? 4 : 1;
    const CGWindowID window = CGWindowID(reinterpret_cast<NSView *>(winId()).window.windowNumber);
    const QByteArray dir = m_shotDir.toUtf8();
    const QByteArray name = tab.toUtf8();

    // the frames are shot from another thread: the main one keeps the bars moving meanwhile
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        QByteArray taken;

        for (int frame = 1; frame <= frames; ++frame)
        {
            if (frame > 1)
                [NSThread sleepForTimeInterval:0.25];

            const QByteArray file = name + '-' + QByteArray::number(frame) + ".png";

            if (shootWindow(window, dir + '/' + file))
                taken += ' ' + file;
        }

        // the analyzer gets these files only, not the ones a previous run left
        printf("stylecheck shots %s%s\n", name.constData(), taken.constData());
        fflush(stdout);

        QMetaObject::invokeMethod(this, &StyleCheckDialog::tabShot, Qt::QueuedConnection);
    });
}

void StyleCheckDialog::tabShot()
{
    const QString tab = m_tabs->currentWidget()->objectName().mid(kTabPrefix.size());

    m_menus = m_menuShots ? menuSteps(tab) : QStringList();

    if (tab == "cocoatabs")
        switchCocoaTab();
    else
        nextMenu();
}

void StyleCheckDialog::switchCocoaTab()
{
    // The third tab of the native bar is clicked: the glass slides to it in about half a second, and QTabWidget shows
    // its page. A window that isn't active may take the click for its activation only
    QTabWidget *tabs = m_tabs->currentWidget()->findChild<QTabWidget *>("sc_cocoa_tabs_regular");
    NSSegmentedControl *bar = nativeTabBar(tabs);

    if (bar)
        postClick(bar, NSMakePoint(NSWidth(bar.bounds) * 5 / 6, NSHeight(bar.bounds) / 2));

    QTimer::singleShot(1200, this, [this, tabs, bar] {
        printf("stylecheck switch sc_cocoa_tabs_regular native=%d current=%d changes=%d segment=%ld active=%d\n",
               int(bar != nil), tabs->currentIndex(), m_cocoaTabChanges, long(bar ? bar.selectedSegment : -1),
               int(isActiveWindow()));
        fflush(stdout);

        const CGWindowID window = CGWindowID(reinterpret_cast<NSView *>(winId()).window.windowNumber);
        const QByteArray file = m_shotDir.toUtf8() + "/cocoatabs-switched.png";

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            shootWindow(window, file);
            QMetaObject::invokeMethod(this, &StyleCheckDialog::nextMenu, Qt::QueuedConnection);
        });
    });
}

void StyleCheckDialog::nextMenu()
{
    if (m_menus.isEmpty())
    {
        nextTab();
        return;
    }

    const QStringList step = m_menus.takeFirst().split(' ');
    const QString name = step.first();

    // the windows of qcocoacontrols open and close in ways of their own
    if (name == "popover")
        return shootPopover();

    if (name == "alert")
        return shootAlert();

    if (name == "preferences")
        return shootPreferences();

    if (name == "menubar")
        return shootMenuBarPopover();
    const bool select = step.size() > 1;
    const QString file = select ? name + "-select" : name;

    QWidget *control = findChild<QWidget *>(name);
    QComboBox *combo = qobject_cast<QComboBox *>(control);
    NSPopUpButton *button = nil;

    if (!combo && control)
    {
        // an AppKit sample, or the pop-up button inside a QCocoaButtonActionMenu, which has the menu of its QMenu
        NSView *sample = nativeViews().value(name);

        if ([sample isKindOfClass:[NSPopUpButton class]])
            button = static_cast<NSPopUpButton *>(sample);
        else if (QMenu *menu = qvariant_cast<QMenu *>(control->property(kPullDownMenu)))
            button = findPopUpButton(reinterpret_cast<NSView *>(winId()).window.contentView, menu->toNSMenu());
    }

    if (!combo && !button)
    {
        printf("stylecheck menu %s: no such list or pull-down button\n", qPrintable(file));
        QTimer::singleShot(0, this, &StyleCheckDialog::nextMenu);
        return;
    }

    activate();

    const QRect area(control->mapToGlobal(QPoint(0, 0)), control->size());

    if (combo && !combo->inherits("QCocoaComboBox"))
    {
        // The list of QComboBox doesn't block: the tour goes on when the other thread has shot it and posted Escape.
        // Half a second later the key has reached the list, and if it hasn't, the list is closed here
        shootLater(m_shotDir, file, area, select ? Close::NextItem : Close::Escape, this, [this, combo] {
            QTimer::singleShot(500, this, [this, combo] {
                combo->hidePopup();
                nextMenu();
            });
        });

        combo->showPopup();
        return;
    }

    shootLater(m_shotDir, file, area, select ? Close::NextItem : Close::Escape);

    if (combo)
    {
        int activated = 0;
        const QMetaObject::Connection counter = connect(combo, &QComboBox::activated, combo, [&activated] {
            ++activated;
        });

        combo->showPopup(); // returns when the menu is closed

        disconnect(counter);

        if (select)
            printf("stylecheck select %s current=%d text=\"%s\" activated=%d\n", qPrintable(name),
                   combo->currentIndex(), qPrintable(combo->currentText()), activated);
    }
    else
        [button performClick:nil]; // returns when the menu is closed

    fflush(stdout);
    QTimer::singleShot(800, this, &StyleCheckDialog::nextMenu);
}
