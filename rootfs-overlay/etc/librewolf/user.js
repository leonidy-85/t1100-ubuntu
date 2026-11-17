// Настройки LibreWolf под Fplus T1100 (MT6771, Mali-G72, 3.5 ГиБ RAM).
// Кладётся как user.js в профиль (~/.config/librewolf/librewolf/<profile>/user.js):
//   tools/host/librewolf-install.sh --prefs-only
// Причины и цифры — docs/browser.md.

// 3.5 ГиБ не тянет Fission-модель «процесс на сайт»: при первом запуске
// браузер поднимал 12 content-процессов и съедал ~470 МиБ только под них.
user_pref("dom.ipc.processCount", 4);

// У panfrost (Mali-G72, без DVFS) EGL-джобы браузера дают
// DATA_INVALID_FAULT в dmesg; WebGL на этой плате нужен редко, а отключение
// ещё и уменьшает площадь атаки. Если понадобятся карты/3D — убрать строку.
user_pref("webgl.disabled", true);
user_pref("gfx.webrender.software", true);
user_pref("gfx.canvas.accelerated", false);

// Первый запуск: не спрашивать «запрашивать английские версии страниц?»
// и не переводить интерфейс сайтов на английский.
user_pref("privacy.spoof_english", 1);
user_pref("intl.accept_languages", "ru-RU, ru, en-US, en");
user_pref("browser.shell.checkDefaultBrowser", false);
