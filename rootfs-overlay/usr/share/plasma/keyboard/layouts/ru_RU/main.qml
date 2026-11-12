// Copyright (C) 2021 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick
import QtQuick.VirtualKeyboard
import QtQuick.VirtualKeyboard.Components
import QtQuick.Layouts

KeyboardLayout {
    sharedLayouts: ['symbols']
    keyWeight: 160
    readonly property real normalKeyWidth: normalKey.width
    readonly property real functionKeyWidth: mapFromItem(normalKey, normalKey.width / 2, 0).x
    KeyboardRow {
        Layout.fillHeight: true
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
    }
    KeyboardRow {
        Layout.fillHeight: true
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
    }
    KeyboardRow {
        Layout.fillHeight: true
        Key {
            Layout.minimumHeight: 0
            key: 0x0424
            text: "ф"
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
    }
    KeyboardRow {
        Layout.fillHeight: true
        ShiftKey {
            Layout.minimumHeight: 0
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
        BackspaceKey {
            Layout.minimumHeight: 0
        }
    }
    KeyboardRow {
        Layout.fillHeight: true
        SymbolModeKey {
            Layout.minimumHeight: 0
            weight: functionKeyWidth
            Layout.fillWidth: false
        }
        ChangeLanguageKey {
            Layout.minimumHeight: 0
            weight: normalKeyWidth
            Layout.fillWidth: false
        }
        Key {
            Layout.minimumHeight: 0
            key: Qt.Key_Comma
            weight: normalKeyWidth
            Layout.fillWidth: false
            text: ","
            smallText: "\u2699"
            smallTextVisible: keyboard.isFunctionPopupListAvailable()
            highlighted: true
        }
        SpaceKey {
            Layout.minimumHeight: 0
        }
        Key {
            Layout.minimumHeight: 0
            key: Qt.Key_Period
            weight: normalKeyWidth
            Layout.fillWidth: false
            text: "."
            alternativeKeys: "!.?"
            smallText: "!?"
            smallTextVisible: true
            highlighted: true
        }
        HideKeyboardKey {
            Layout.minimumHeight: 0
            weight: normalKeyWidth
            Layout.fillWidth: false
        }
        EnterKey {
            Layout.minimumHeight: 0
            weight: functionKeyWidth
            Layout.fillWidth: false
        }
    }
}
