#!/bin/sh
# Route AFE -> ADDA -> MT6358 DAC -> loudspeaker and unmute the external amp.
for i in $(seq 1 40); do [ -e /dev/snd/controlC0 ] && break; sleep 0.25; done
/usr/local/bin/ctlroute C0 SET "ADDA_DL_CH1 DL1" "ADDA_DL_CH2 DL1" >/dev/null 2>&1
/usr/local/bin/ctlenum /dev/snd/controlC0 SET "DAC In Mux" "Normal Path" >/dev/null 2>&1
/usr/local/bin/ctlenum /dev/snd/controlC0 SET "HPL Mux" "LoudSPK Playback" >/dev/null 2>&1
/usr/local/bin/ctlenum /dev/snd/controlC0 SET "HPR Mux" "LoudSPK Playback" >/dev/null 2>&1
exit 0
