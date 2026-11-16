# A window with the Qt controls that need care on macOS: the ones the QMacStyle patches of qt-build-tools change and
# the native controls of qcocoacontrols, each next to the same AppKit control. How to build and check it is in README.md

TEMPLATE = app
TARGET = StyleCheck

QT += widgets
CONFIG += c++20

QMAKE_MACOSX_DEPLOYMENT_TARGET = 12

# The window runs on this Mac only, so it is built for its architecture alone, and qcocoacontrols for the same one
isEmpty(QMAKE_APPLE_DEVICE_ARCHS): QMAKE_APPLE_DEVICE_ARCHS = $$QMAKE_HOST.arch

HEADERS += StyleCheckDialog.h
SOURCES += main.cpp
OBJECTIVE_SOURCES += StyleCheckDialog.mm

# qcocoacontrols is taken from the working copy next to this repository, as in our source tree, or from QCOCOACONTROLS
QCOCOACONTROLS = $$(QCOCOACONTROLS)
isEmpty(QCOCOACONTROLS): QCOCOACONTROLS = $$clean_path($$PWD/../common/qcocoacontrols)
!exists($$QCOCOACONTROLS/qcocoacontrols.pro): error("qcocoacontrols not found in $$QCOCOACONTROLS, set QCOCOACONTROLS")

# The library is built by its own project into this build, with the configuration and the architecture of the window.
# Not next to its sources: our apps build it there with their own settings
QCOCOACONTROLS_OUT = $$OUT_PWD/qcocoacontrols
QCOCOACONTROLS_LIB = $$QCOCOACONTROLS_OUT/libqcocoacontrols.a

CONFIG(debug, debug|release): QCOCOACONTROLS_CONFIG = debug
else: QCOCOACONTROLS_CONFIG = release

qcocoacontrols.target = $$QCOCOACONTROLS_LIB
qcocoacontrols.commands = mkdir -p $$shell_quote($$QCOCOACONTROLS_OUT) && cd $$shell_quote($$QCOCOACONTROLS_OUT) && \
    $$QMAKE_QMAKE $$shell_quote($$QCOCOACONTROLS/qcocoacontrols.pro) CONFIG+=$$QCOCOACONTROLS_CONFIG \
    -after DESTDIR=$$shell_quote($$QCOCOACONTROLS_OUT) \"QMAKE_APPLE_DEVICE_ARCHS=$$QMAKE_APPLE_DEVICE_ARCHS\" && \
    $(MAKE)
qcocoacontrols.depends = FORCE
QMAKE_EXTRA_TARGETS += qcocoacontrols
PRE_TARGETDEPS += $$QCOCOACONTROLS_LIB

INCLUDEPATH += $$QCOCOACONTROLS
LIBS += $$QCOCOACONTROLS_LIB -ObjC -framework AppKit
