# Contributing

1. Keep the patch series split in two files:

   - `patches/series-upstream` — changes that can be proposed to mainline
     (DTS, panel/bridge drivers, touch, sound, sensors, cpufreq, thermal,
     USB role, fuel gauge, generic bug fixes).
   - `patches/series-vendor` — board bring-up hacks and the MediaTek
     connectivity stack that cannot go upstream.

2. One commit = one idea. Format the subject as `area: what changed`.
3. Do not commit build output, dumps or firmware blobs.
4. For upstream candidates follow the kernel rules: DT bindings, `make
   dt_binding_check`, `checkpatch.pl --strict`, one logical change per
   patch, `Signed-off-by` (DCO).
5. Describe the hardware and the test result in the commit message; a
   patch that cannot be tested on the tablet must say so.
