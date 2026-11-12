// Copyright (C) 2021 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick
import QtQuick.VirtualKeyboard
import QtQuick.VirtualKeyboard.Components
import QtQuick.Layouts

KeyboardLayout {
    inputMode: InputEngine.InputMode.Latin
    sharedLayouts: ['symbols']
    keyWeight: 160
    readonly property real normalKeyWidth: normalKey.width
    readonly property real functionKeyWidth: mapFromItem(normalKey, normalKey.width / 2, 0).x
    KeyboardRow {
        Layout.fillHeight: true
        Key { Layout.minimumHeight: 0; key: Qt.Key_Escape; text: "Esc" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F1; text: "F1" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F2; text: "F2" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F3; text: "F3" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F4; text: "F4" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F5; text: "F5" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F6; text: "F6" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F7; text: "F7" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F8; text: "F8" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F9; text: "F9" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_F10; text: "F10" }
    }
    KeyboardRow {
        Layout.fillHeight: true
        spacing: 12
        Key { Layout.minimumHeight: 0; text: "~" }
        Key { Layout.minimumHeight: 0; key: Qt.Key_1; text: "1"; alternativeKeys: "!1"; smallText: "!"; smallTextVisible: true }
        Key { Layout.minimumHeight: 0; key: Qt.Key_2; text: "2"; alternativeKeys: "@2"; smallText: "@"; smallTextVisible: true }
        Key { Layout.minimumHeight: 0; key: Qt.Key_3; text: "3"; alternativeKeys: "#3"; smallText: "#"; smallTextVisible: true }
        Key { Layout.minimumHeight: 0; key: Qt.Key_4; text: "4"; alternativeKeys: "$4"; smallText: "$"; smallTextVisible: true }
        Key { Layout.minimumHeight: 0; key: Qt.Key_5; text: "5"; alternativeKeys: "%5"; smallText: "%"; smallTextVisible: true }
        Key { Layout.minimumHeight: 0; key: Qt.Key_6; text: "6"; alternativeKeys: "^6"; smallText: "^"; smallTextVisible: true }
        Key { Layout.minimumHeight: 0; key: Qt.Key_7; text: "7"; alternativeKeys: "&7"; smallText: "&"; smallTextVisible: true }
        Key { Layout.minimumHeight: 0; key: Qt.Key_8; text: "8"; alternativeKeys: "*8"; smallText: "*"; smallTextVisible: true }
        Key { Layout.minimumHeight: 0; key: Qt.Key_9; text: "9"; alternativeKeys: "(9"; smallText: "("; smallTextVisible: true }
        Key { Layout.minimumHeight: 0; key: Qt.Key_0; text: "0"; alternativeKeys: ")0"; smallText: ")"; smallTextVisible: true }
        BackspaceKey {
            Layout.minimumHeight: 0
            weight: normalKeyWidth
            Layout.fillWidth: false
        }
    }
    KeyboardRow {
        Layout.fillHeight: true
        Key {
            Layout.minimumHeight: 0
            key: Qt.Key_Tab
            text: "Tab"
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
    }
    KeyboardRow {
        Layout.fillHeight: true
        KeyboardRow {
            Layout.fillHeight: true
            Layout.preferredWidth: functionKeyWidth
            Layout.fillWidth: false
            Key {
                Layout.minimumHeight: 0
                text: "Caps"
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
                Layout.fillWidth: false
            }
            FillerKey {
                Layout.minimumHeight: 0
            }
        }
    }
    KeyboardRow {
        Layout.fillHeight: true
        ShiftKey {
            Layout.minimumHeight: 0
            weight: normalKeyWidth
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
            weight: normalKeyWidth
            Layout.fillWidth: false
            text: "."
            alternativeKeys: ","
            smallText: ","
            smallTextVisible: true
        }
        ShiftKey {
            Layout.minimumHeight: 0
            weight: normalKeyWidth
            Layout.fillWidth: false
        }
    }
    KeyboardRow {
        Layout.fillHeight: true
        SymbolModeKey {
            Layout.minimumHeight: 0
            weight: normalKeyWidth
            Layout.fillWidth: false
        }
        ChangeLanguageKey {
            Layout.minimumHeight: 0
            weight: normalKeyWidth
            Layout.fillWidth: false
        }
        Key {
            Layout.minimumHeight: 0
            key: Qt.Key_Left
            text: "←"
            weight: normalKeyWidth * 0.55
            Layout.fillWidth: false
        }
        Key {
            Layout.minimumHeight: 0
            key: Qt.Key_Up
            text: "↑"
            weight: normalKeyWidth * 0.55
            Layout.fillWidth: false
        }
        Key {
            Layout.minimumHeight: 0
            key: Qt.Key_Down
            text: "↓"
            weight: normalKeyWidth * 0.55
            Layout.fillWidth: false
        }
        Key {
            Layout.minimumHeight: 0
            key: Qt.Key_Right
            text: "→"
            weight: normalKeyWidth * 0.55
            Layout.fillWidth: false
        }
        SpaceKey {
            Layout.minimumHeight: 0
        }
        HideKeyboardKey {
            Layout.minimumHeight: 0
            weight: normalKeyWidth * 0.7
            Layout.fillWidth: false
        }
        EnterKey {
            Layout.minimumHeight: 0
            weight: normalKeyWidth
            Layout.fillWidth: false
        }
    }
}
