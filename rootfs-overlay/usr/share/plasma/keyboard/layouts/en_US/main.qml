// Copyright (C) 2021 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick
import QtQuick.Window
import QtQuick.VirtualKeyboard
import QtQuick.VirtualKeyboard.Components
import QtQuick.Layouts

KeyboardLayout {
    id: layout
    readonly property real rowHeight: Math.round(Screen.height / 12)
    inputMode: InputEngine.InputMode.Latin
    sharedLayouts: ['symbols']
    keyWeight: 160
    readonly property real normalKeyWidth: normalKey.width
    readonly property real functionKeyWidth: mapFromItem(normalKey, normalKey.width / 2, 0).x
    Connections {
        target: keyboard
        function onActiveChanged() {
            if (keyboard.active)
                resetShiftTimer.restart()
        }
        function onLocaleChanged() {
            resetShiftTimer.restart()
        }
    }
    Timer {
        id: resetShiftTimer
        interval: 120
        onTriggered: {
            InputContext.priv.shiftHandler.shiftActive = false
            InputContext.priv.shiftHandler.capsLockActive = false
        }
    }
    Component.onCompleted: {
        InputContext.priv.shiftHandler.shiftActive = false
        InputContext.priv.shiftHandler.capsLockActive = false
    }

    KeyboardRow {
        Layout.fillHeight: true
        Key { Layout.minimumHeight: 0; key: Qt.Key_Escape; displayText: "Esc" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F1; displayText: "F1" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F2; displayText: "F2" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F3; displayText: "F3" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F4; displayText: "F4" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F5; displayText: "F5" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F6; displayText: "F6" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F7; displayText: "F7" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F8; displayText: "F8" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F9; displayText: "F9" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F10; displayText: "F10" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F11; displayText: "F11"; visible: Screen.width >= Screen.height }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F12; displayText: "F12"; visible: Screen.width >= Screen.height }
    }
    KeyboardRow {
        Layout.fillHeight: true
        KeyboardColumn {
            Layout.fillHeight: true
            KeyboardRow {
                Layout.fillHeight: true
                    Key { Layout.minimumHeight: 0; text: "~" }
                    Key { Layout.minimumHeight: 0; key: Qt.Key_1; text: "1"; alternativeKeys: "!1"; smallText: "!"; smallTextVisible: true }
                    Key { Layout.minimumHeight: 0; key: Qt.Key_2; text: "2"; alternativeKeys: "@2"; smallText: "@"; smallTextVisible: true }
                    Key { Layout.minimumHeight: 0; key: Qt.Key_3; text: "3"; alternativeKeys: "#3"; smallText: "#"; smallTextVisible: true }
                    Key { Layout.minimumHeight: 0; key: Qt.Key_4; text: "4"; alternativeKeys: "$4"; smallText: "$"; smallTextVisible: true }
                    Key { Layout.minimumHeight: 0; key: Qt.Key_5; text: "5"; alternativeKeys: "%5"; smallText: "%"; smallTextVisible: true }
                    Key { Layout.minimumHeight: 0; key: Qt.Key_6; text: "6"; alternativeKeys: "^6"; smallText: "^"; smallTextVisible: true }
            }
        }
        KeyboardColumn { Layout.preferredWidth: 150; Layout.fillHeight: true }
        KeyboardColumn {
            Layout.fillHeight: true
            KeyboardRow {
                Layout.fillHeight: true
                    Key { Layout.minimumHeight: 0; key: Qt.Key_7; text: "7"; alternativeKeys: "&7"; smallText: "&"; smallTextVisible: true }
                    Key { Layout.minimumHeight: 0; key: Qt.Key_8; text: "8"; alternativeKeys: "*8"; smallText: "*"; smallTextVisible: true }
                    Key { Layout.minimumHeight: 0; key: Qt.Key_9; text: "9"; alternativeKeys: "(9"; smallText: "("; smallTextVisible: true }
                    Key { Layout.minimumHeight: 0; key: Qt.Key_0; text: "0"; alternativeKeys: ")0"; smallText: ")"; smallTextVisible: true }
                    Key { Layout.minimumHeight: 0; text: "-" }
                    Key { Layout.minimumHeight: 0; text: "+"; alternativeKeys: "=+"; smallText: "="; smallTextVisible: true }
                    BackspaceKey {
                        Layout.minimumHeight: 0
                        weight: normalKeyWidth
                        Layout.fillWidth: false
                    }
            }
        }
    }
    KeyboardRow {
        Layout.fillHeight: true
        KeyboardColumn {
            Layout.fillHeight: true
            KeyboardRow {
                Layout.fillHeight: true
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_Tab
                        displayText: "Tab"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_Q
                        text: "q"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        id: normalKey
                        key: Qt.Key_W
                        text: "w"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_E
                        text: "e"
                        alternativeKeys: "êeëèé"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_R
                        text: "r"
                        alternativeKeys: "ŕrř"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_T
                        text: "t"
                        alternativeKeys: "ţtŧť"
                    }
            }
        }
        KeyboardColumn { Layout.preferredWidth: 150; Layout.fillHeight: true }
        KeyboardColumn {
            Layout.fillHeight: true
            KeyboardRow {
                Layout.fillHeight: true
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_Y
                        text: "y"
                        alternativeKeys: "ÿyýŷ"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_U
                        text: "u"
                        alternativeKeys: "űūũûüuùú"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_I
                        text: "i"
                        alternativeKeys: "îïīĩiìí"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_O
                        text: "o"
                        alternativeKeys: "œøõôöòóo"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_P
                        text: "p"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        text: "\\"
                        alternativeKeys: "|\\"
                        smallText: "|"
                        smallTextVisible: true
                    }
            }
        }
    }
    KeyboardRow {
        Layout.fillHeight: true
        KeyboardColumn {
            Layout.fillHeight: true
            KeyboardRow {
                Layout.fillHeight: true
                    KeyboardRow {
                        Layout.fillHeight: true
                        Layout.preferredWidth: functionKeyWidth
                        Layout.fillWidth: false
                        Key {
                            Layout.minimumHeight: 0
                            displayText: "Caps"
                            functionKey: true
                            noKeyEvent: true
                            onClicked: InputContext.priv.shiftHandler.capsLockActive = !InputContext.priv.shiftHandler.capsLockActive
                            highlighted: InputContext.priv.shiftHandler.capsLockActive
                        }
                        Key {
                            Layout.minimumHeight: 0
                            key: Qt.Key_A
                            text: "a"
                            alternativeKeys: "aäåãâàá"
                            weight: normalKeyWidth
                            Layout.fillWidth: false
                        }
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_S
                        text: "s"
                        alternativeKeys: "šsşś"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_D
                        text: "d"
                        alternativeKeys: "dđď"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_F
                        text: "f"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_G
                        text: "g"
                        alternativeKeys: "ġgģĝğ"
                    }
            }
        }
        KeyboardColumn { Layout.preferredWidth: 150; Layout.fillHeight: true }
        KeyboardColumn {
            Layout.fillHeight: true
            KeyboardRow {
                Layout.fillHeight: true
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_H
                        text: "h"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_J
                        text: "j"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_K
                        text: "k"
                    }
                    KeyboardRow {
                        Layout.fillHeight: true
                        Layout.preferredWidth: functionKeyWidth
                        Layout.fillWidth: false
                        Key {
                            Layout.minimumHeight: 0
                            key: Qt.Key_L
                            text: "l"
                            alternativeKeys: "ĺŀłļľl"
                            weight: normalKeyWidth
                            Layout.fillWidth: true
                        }
                        EnterKey {
                            Layout.minimumHeight: 0
                            weight: normalKeyWidth
                            Layout.fillWidth: true
                        }
                    }
            }
        }
    }
    KeyboardRow {
        Layout.fillHeight: true
        KeyboardColumn {
            Layout.fillHeight: true
            KeyboardRow {
                Layout.fillHeight: true
                    ShiftKey {
                        Layout.minimumHeight: 0
                        weight: normalKeyWidth * 1.2
                        Layout.fillWidth: false
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_Z
                        text: "z"
                        alternativeKeys: "zžż"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_X
                        text: "x"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_C
                        text: "c"
                        alternativeKeys: "çcċčć"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_V
                        text: "v"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_B
                        text: "b"
                    }
            }
        }
        KeyboardColumn { Layout.preferredWidth: 150; Layout.fillHeight: true }
        KeyboardColumn {
            Layout.fillHeight: true
            KeyboardRow {
                Layout.fillHeight: true
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_N
                        text: "n"
                        alternativeKeys: "ņńnň"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_M
                        text: "m"
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_Period
                        weight: normalKeyWidth * 0.7
                        Layout.fillWidth: false
                        text: "."
                        alternativeKeys: ","
                        smallText: ","
                        smallTextVisible: true
                    }
                    Key {
                        Layout.minimumHeight: 0
                        weight: normalKeyWidth * 0.7
                        Layout.fillWidth: false
                        text: "/"
                        alternativeKeys: "?/"
                        smallText: "?"
                        smallTextVisible: true
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_Up
                        displayText: "↑"
                        repeat: true
                        weight: normalKeyWidth * 0.55
                        Layout.fillWidth: false
                    }
                    ShiftKey {
                        Layout.minimumHeight: 0
                        weight: normalKeyWidth * 1.3
                        Layout.fillWidth: false
                    }
            }
        }
    }
    KeyboardRow {
        Layout.fillHeight: true
        KeyboardColumn {
            Layout.fillHeight: true
            KeyboardRow {
                Layout.fillHeight: true
                    SymbolModeKey {
                        Layout.minimumHeight: 0
                        weight: normalKeyWidth
                        Layout.fillWidth: false
                    }
                    Key {
                        Layout.minimumHeight: 0
                        weight: normalKeyWidth
                        Layout.fillWidth: false
                        keyType: QtVirtualKeyboard.KeyType.ChangeLanguageKey
                        displayText: keyboard.locale.split("_")[0]
                        onClicked: keyboard.changeInputLanguage(false)
                    }
                    Key {
                        Layout.minimumHeight: 0
                        weight: normalKeyWidth * 0.6
                        Layout.fillWidth: false
                        key: Qt.Key_Control
                        displayText: "Ctrl"
                        functionKey: true
                    }
                    Key {
                        Layout.minimumHeight: 0
                        weight: normalKeyWidth * 0.6
                        Layout.fillWidth: false
                        key: Qt.Key_Alt
                        displayText: "Alt"
                        functionKey: true
                    }
                    SpaceKey {
                        Layout.minimumHeight: 0
                    }
            }
        }
        KeyboardColumn { Layout.preferredWidth: 150; Layout.fillHeight: true }
        KeyboardColumn {
            Layout.fillHeight: true
            KeyboardRow {
                Layout.fillHeight: true
                    SpaceKey {
                        Layout.minimumHeight: 0
                    }
                    Key {
                        Layout.minimumHeight: 0
                        weight: normalKeyWidth * 0.6
                        Layout.fillWidth: false
                        key: Qt.Key_Control
                        displayText: "Ctrl"
                        functionKey: true
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_Left
                        displayText: "←"
                        repeat: true
                        weight: normalKeyWidth * 0.55
                        Layout.fillWidth: false
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_Down
                        displayText: "↓"
                        repeat: true
                        weight: normalKeyWidth * 0.55
                        Layout.fillWidth: false
                    }
                    Key {
                        Layout.minimumHeight: 0
                        key: Qt.Key_Right
                        displayText: "→"
                        repeat: true
                        weight: normalKeyWidth * 0.55
                        Layout.fillWidth: false
                    }
                    HideKeyboardKey {
                        Layout.minimumHeight: 0
                        weight: normalKeyWidth * 0.7
                        Layout.fillWidth: false
                    }
            }
        }
    }
}
