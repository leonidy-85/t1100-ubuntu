// Copyright (C) 2021 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick
import QtQuick.Window
import QtQuick.VirtualKeyboard
import QtQuick.VirtualKeyboard.Components
import QtQuick.Layouts

KeyboardLayout {
    inputMode: InputEngine.InputMode.Cyrillic
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
    }
    Timer {
        id: resetShiftTimer
        interval: 0
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
        Key { Layout.minimumHeight: 0; text: "-" }
        Key { Layout.minimumHeight: 0; text: "+"; alternativeKeys: "=+"; smallText: "="; smallTextVisible: true }
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
            displayText: "Tab"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0419
            text: "й"
        }
        Key {
            Layout.minimumHeight: 0
            id: normalKey
            key: 0x0426
            text: "ц"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0423
            text: "у"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x041A
            text: "к"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0415
            text: "е"
            alternativeKeys: "её"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x041D
            text: "н"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0413
            text: "г"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0428
            text: "ш"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0429
            text: "щ"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0417
            text: "з"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0425
            text: "х"
        }
        Key {
            Layout.minimumHeight: 0
            text: "\\"
            alternativeKeys: "|\\"
            smallText: "|"
            smallTextVisible: true
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
                displayText: "Caps"
                functionKey: true
                noKeyEvent: true
                onClicked: InputContext.priv.shiftHandler.capsLockActive = !InputContext.priv.shiftHandler.capsLockActive
                highlighted: InputContext.priv.shiftHandler.capsLockActive
            }
            Key {
                Layout.minimumHeight: 0
                key: 0x0424
                text: "ф"
                weight: normalKeyWidth
                Layout.fillWidth: false
            }
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x042B
            text: "ы"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0412
            text: "в"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0410
            text: "а"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x041F
            text: "п"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0420
            text: "р"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x041E
            text: "о"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x041B
            text: "л"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0414
            text: "д"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0416
            text: "ж"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x042D
            text: "э"
        }
        EnterKey {
            Layout.minimumHeight: 0
            weight: normalKeyWidth
            Layout.fillWidth: false
        }
    }
    KeyboardRow {
        Layout.fillHeight: true
        ShiftKey {
            Layout.minimumHeight: 0
            weight: normalKeyWidth * 1.2
            Layout.fillWidth: false
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x042F
            text: "я"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0427
            text: "ч"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0421
            text: "с"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x041C
            text: "м"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0418
            text: "и"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0422
            text: "т"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x042C
            text: "ь"
            alternativeKeys: "ьъ"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x0411
            text: "б"
        }
        Key {
            Layout.minimumHeight: 0
            key: 0x042E
            text: "ю"
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
            onClicked: keyboard.showLanguagePopup(this, false)
        }
        SpaceKey {
            Layout.minimumHeight: 0
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
