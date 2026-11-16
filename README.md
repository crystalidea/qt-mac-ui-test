# qt-mac-ui-test

A window with the Qt controls that need care on macOS under Liquid Glass, each next to the same control made with AppKit, one kind of control on a tab:

- the controls the QMacStyle patches of [qt-build-tools](https://github.com/crystalidea/qt-build-tools) change (`patches/qtbase-macstyle-*.patch`);
- the native controls of [qcocoacontrols](https://github.com/crystalidea/qcocoacontrols): the list of `QCocoaComboBox` and the pull-down buttons of `QCocoaButtonActionMenu`;
- `QTabWidget`, which no patch changes yet, next to `NSTabView`.

A script runs the window in the light and dark appearance: the window shoots its tabs one by one and, on request, its open lists and pull-down menus, and the script measures what can be measured without eyes.

## The tabs

| Tab | Checks | What to look at |
|---|---|---|
| Progress | progressbar-liquid-glass | 60 %; 70 of 20…120 (= 50 %); reset: an empty groove; busy; busy, then 30 % a second later; disabled |
| Buttons | small-pushbutton-margins | regular, small, mini, small with a long title, disabled: the title is centered and not clipped |
| Spin boxes | spinbox-arrows, textfield-heights, -insets, -stepper | regular, small, mini, QDoubleSpinBox, disabled: as large as the AppKit field with its stepper, the text as far from the bezel as in AppKit, the stepper of the same size and not clipped |
| Line edits | lineedit-focus-ring, textfield-heights, -insets | as large as the AppKit field, the text as far from the bezel as in AppKit, also aligned right; the focus ring follows the rounded edit; an edit with its own background, with a placeholder, small, disabled |
| Item views | itemview-checkboxes | table, tree, list: checked, unchecked, partially checked, disabled, on the selected row |
| Lists | QCocoaComboBox | closed, QMacStyle draws QComboBox and QCocoaComboBox alike, as large as the AppKit pop-up button. Open, QComboBox shows a list drawn by Qt, and QCocoaComboBox an NSMenu like the one of the AppKit pop-up button: the current item over the text with a check mark, the separator, the icons, the disabled item |
| Pull-downs | QCocoaButtonActionMenu | with a title and with an icon only, next to AppKit pull-down buttons with the toolbar bezel: the same size, the title not clipped, the same menu |
| Tabs | no patch | QTabWidget, regular and small, next to NSTabView with the same three tabs and a check box on each page; a QTabWidget with only the current tab enabled, as an app leaves it while it works (NSTabView can't disable a tab). Look at the tab bar, the selected tab in an active and in an inactive window, the pane under the tabs |

The window keeps its tabs in a QTabWidget too, so the tab bar at the top of it is one more sample.

The bezel of an AppKit text field reaches 1 pt beyond its frame, while QMacStyle draws it inside the widget, so a Qt field takes 2 pt more in a layout than the AppKit one that looks the same. To compare what they look like, the Qt line edits here are 182 pt wide next to AppKit fields of 180 pt, and a spin box is 1 pt wider than the AppKit field and stepper next to it; the QDoubleSpinBox keeps its own width.

The top line of the window shows the Qt version, the style and whether Qt and qcocoacontrols take the Liquid Glass design (`Liquid Glass: Qt yes, qcocoacontrols yes`). The patches take effect only with Qt `yes`, and qcocoacontrols picks the metrics of its controls by its own one. An app gets Liquid Glass when it is built against the macOS 26 SDK or later and runs on macOS 26 or later. qmake doesn't put `UIDesignRequiresCompatibility` into the Info.plist, so nothing opts the window out.

## Build and run

Needs:

- Qt 6.8.5 built by qt-build-tools, with its patches (`/usr/local/Qt-6.8.5` by default);
- qcocoacontrols checked out as `../common/qcocoacontrols`, as in our source tree, or anywhere else with `QCOCOACONTROLS` pointing to it;
- Xcode.

```sh
mkdir -p build && cd build && /usr/local/Qt-6.8.5/bin/qmake ../StyleCheck.pro && make
```

The build first builds qcocoacontrols with its own project into `build/qcocoacontrols`, for the architecture of this Mac and in the configuration of the window. The build our apps keep next to the sources of the library stays untouched.

```sh
build/StyleCheck.app/Contents/MacOS/StyleCheck dark
```

`light` or `dark` sets the appearance, without either the system one is used. The window also has an appearance switch. With `--shots DIR` the window shoots its tabs into `DIR` and quits, and `--menus` adds its open lists and menus (see below).

## Automatic check

```sh
./stylecheck.sh [--menus] [output_dir]
```

The script builds the window and the analyzer when needed (`QMAKE` overrides the qmake path) and starts the window once in each appearance. The window shows its tabs one by one: it gives a tab a second to settle, prints the geometry of its controls and shoots it, the Progress tab four times 0.25 s apart and the other tabs once. The window shoots itself from another thread, so its bars keep moving between the frames. Then the analyzer goes through the shots tab by tab. Everything goes to `shots/` or to the directory given as the argument:

- `light.txt`, `dark.txt`: what the window printed;
- `light/`, `dark/`: the shots of the tabs, `<tab>-<n>.png`, and the crops of the analyzer: each tab without the window around it (`sc_group_<tab>.png`), the table, tree and list, the tab widgets of the Tabs tab (`sc_tabs_*.png`, `ns_tabs_*.png`); with `--menus` also the shots of the menus;
- `build.log`.

What the shots need:

- The app the script runs from (Terminal and the like) needs the Screen Recording permission, otherwise `screencapture` saves an empty window.
- The window has to be active: an inactive window draws the progress bars gray, the edit without the focus ring, and QTabWidget doesn't mark its selected tab. The window asks for the focus before each tab. If macOS doesn't give it (you're typing in another window), the tab is shot as it is and the script marks it `inactive`. Better leave the keyboard and mouse alone for half a minute.
- On a locked Mac the window never becomes active and every tab is shot inactive, which is enough for the sizes and the insets. A locked Mac turns its display off about 30 s after it wakes, and then nothing can be shot, so the script keeps the display on with `caffeinate -u`. The display still goes dark now and then until the next wake, so the window tries a failed shot again for 6 s.

Under `-- <tab>` the analyzer prints:

- `fill`: the filled part of a progress bar, the longest row of saturated pixels against the bar width.
- `busy`: the indeterminate bar in each of the four frames, the length of the moving segment and its start, in points. The position has to change.
- `visible`: the visible size of a control in points, with 2 pt around the widget for what AppKit draws beyond the frame (6 pt around the focused edit for its focus ring). Compare the pairs `sc_…` (Qt) and `ns_…` (AppKit) of the same size.
- `crop`: a crop to look at rather than measure, the item views and the tab widgets.

### Lists and menus

With `--menus` the window opens the lists of the Lists tab and the pull-down menus of the Pull-downs tab right after it shoots the tab, one by one, each Qt control followed by its AppKit sample. It shoots each a second after it opens and closes it with Escape. The shots go next to the shots of the tabs. The window opens the menus itself and closes them with keys it posts to its own event queue, so this works in an inactive window and on a locked Mac. A menu gets up to two shots:

- `<control>-menu.png`, by the number of the menu window. The list of QComboBox comes alone, an NSMenu together with the window under it, cut to the window, so the lists and the pull-down buttons stay at the top of their tabs. This works on a locked Mac too;
- `<control>.png`, the screen around the control with its menu, only when the Mac isn't locked.

The line `stylecheck menu <control> window=N menu=1 region=1` tells which of them was taken. The last step chooses the next item of QCocoaComboBox with Down and Return: `stylecheck select sc_combo_native current=2 text="CPU Core Average" activated=1` means the choice came through as from the list of Qt.

## Reference results

Qt 6.8.5 with the patches of qt-build-tools on macOS 27.0, both appearances: 2026-10-27; QLineEdit and QSpinBox 2026-11-14; the lists, the pull-down buttons and the tabs 2026-11-15 in an inactive window and 2026-11-16 in an active one.

- `fill`: `sc_pb_60` 0.60, `sc_pb_offset` 0.50, `sc_pb_reset` 0.00, `sc_pb_busydone` 0.30; AppKit `ns_pb_60` 0.60.
- `busy`: the segment in Qt is up to 45 pt long and moves. In AppKit the segment changes its length almost to the whole bar, the animation is different.
- Push buttons: Qt and AppKit heights match (24 / 20 / 16 pt), the titles are centered. Qt buttons are wider: regular +5, small +23, mini +7 pt.
- QSpinBox: `visible` 87 × 26, 84 × 24 and 80 × 21 pt, the same as the AppKit field and stepper. The stepper is 20 × 24, 17 × 20 and 13 × 16 pt, as in AppKit, 1 pt from the bezel of the field. The text is 7.5–8 pt from the edge of the bezel, as in AppKit, and the widest value isn't clipped.
- QLineEdit: `visible` 182 × 26 and 182 × 24 pt, the same as the AppKit fields. The text is within half a point of where AppKit has it, 7.5–8 pt from the edge of the bezel at the start and at the end. The focus ring follows the rounded edit and extends 3 pt beyond it (2026-10-27, with the edits 2 pt shorter).
- Check boxes in item views are visible in every state, on the selected row too.
- Combo box lists: closed, QComboBox and QCocoaComboBox are 177 × 24 pt, the AppKit pop-up button 178 × 24. The menu of QCocoaComboBox opens over the control with the current item at its text and shows the check mark, the separator, the icons and the disabled item; choosing an item with the keyboard gives `current=2`, `activated=1`.
- Pull-down buttons: QCocoaButtonActionMenu is 205 × 24 pt with the title and 63 × 24 pt with the icon only, the same as the AppKit pull-down buttons; the menus show the same items.

Differences from AppKit the patches don't fix:

- the progress bar fill is more saturated than in AppKit; at zero AppKit draws a dot, Qt an empty groove;
- small Qt buttons are wider;
- a Qt field takes 2 pt more in a layout than the AppKit field it looks like (see above);
- in an inactive window AppKit draws the arrows of a stepper gray, Qt keeps them black;
- in the dark appearance QLineEdit and the edit field of QSpinBox are filled with `QPalette::Base` up to the corners, so they look square, while the AppKit field is rounded;
- an edit with its own `QPalette::Base` looks different from what one expects: in the light appearance the background is white, in the dark one it is blended with the dark, and the rectangular fill shows in the corners behind the rounded bezel.

QTabWidget, which no patch changes, next to NSTabView of the same size (the Tabs tab):

- QMacStyle draws the tabs with cut pieces of the bezels of NSButton (the selected tab) and NSPopUpButton (the others), as a segmented control of the earlier macOS, with separators between the tabs. In an active window the selected tab is filled with the accent color and has a white title, as in an NSSegmentedControl that selects a value. In an inactive window it is drawn as the others, and only the missing separators next to it tell it;
- the tab bar of NSTabView is an NSSegmentedControl with the `tabs` role that the macOS 27 SDK adds (`NSSegmentedControlRoleTabs`). It raises the selected tab on a light segment of glass, in an inactive window too, and draws no separators. When another tab is chosen, the glass slides to it in about half a second and takes its width. The control is drawn by SwiftUI inside AppKit, so a style that paints QTabBar can copy how it looks at rest, but not the motion;
- the tab bar is 196 × 23 pt in Qt and 210 × 23.5 pt in AppKit with the same titles, the small one 169 × 18 and 182 × 20 pt. Qt puts it at the top edge of the widget, AppKit 4.5 pt lower (2.5 pt the small one);
- the pane of QTabWidget fills the widget from the middle of the tab bar down to its edges, with corners rounded by about 12 pt and no border in the light appearance. NSTabView draws its bezel 7 pt off the sides of its frame and 10 pt off the bottom, with corners rounded by about 4 pt and a hairline border in both appearances;
- a disabled tab: QMacStyle grays its title, NSTabView can't disable a tab. An NSSegmentedControl with the `tabs` role ignores a click on a disabled segment, but on macOS 27.0 draws its title as the title of an enabled one.

## Cleanup

Everything built goes to `build/` and every shot to `shots/`; Git ignores both.
