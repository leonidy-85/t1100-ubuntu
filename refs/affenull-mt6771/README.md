# refs/affenull-mt6771 — mainline MT6771 DTS, на котором работает PennyOS

Источник: `github.com/affenull2345/linux`, ветка `mt6771` (base 6.4).
Это ядро использует PennyOS на Planet Cosmo (тот же MT6771, тот же стоковый LK):

- `mt6771.dtsi` — `#include "mt8183.dtsi"` + `compatible = "mediatek,mt6771"` +
  удаление cpufreq/cpuidle у CPU;
- `mt6771-planet-cosmocom.dts` — board DTS, 19 КБ: CPU OPP, регуляторы
  (`sram-supply` для cpu/gpu), `&gpu { mali-supply; sram-supply = <&mt6358_vsram_gpu_reg>; }`
  **без** `regulator-coupled-*`, отдельные рельсы с `regulator-always-on`.

Что берём: как именно они включают MT6358/PD/USB/eMMC без coupling — это наш
текущий блокер (после снятия coupling ядро виснет раньше pstore).
