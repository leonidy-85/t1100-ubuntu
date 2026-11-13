#!/bin/sh
# Route AFE -> ADDA -> MT6358 DAC -> loudspeaker and unmute the external amp.
for i in $(seq 1 40); do [ -e /dev/snd/controlC0 ] && break; sleep 0.25; done
/usr/local/bin/ctlroute C0 SET "ADDA_DL_CH1 DL1" "ADDA_DL_CH2 DL1" >/dev/null 2>&1
/usr/local/bin/ctlenum /dev/snd/controlC0 SET "DAC In Mux" "Normal Path" >/dev/null 2>&1
/usr/local/bin/ctlenum /dev/snd/controlC0 SET "HPL Mux" "LoudSPK Playback" >/dev/null 2>&1
/usr/local/bin/ctlenum /dev/snd/controlC0 SET "HPR Mux" "LoudSPK Playback" >/dev/null 2>&1

# Capture: route FE(UL1) -> BE(ADDA) and select the analog microphone.
/usr/local/bin/ctlroute C0 SET "UL1_CH1 ADDA_UL_CH1" "UL1_CH2 ADDA_UL_CH2" >/dev/null 2>&1
/usr/local/bin/ctlenum /dev/snd/controlC0 SET "Mic Type Mux" "ACC" >/dev/null 2>&1
/usr/local/bin/ctlenum /dev/snd/controlC0 SET "ADC L Mux" "Left Preamplifier" >/dev/null 2>&1
/usr/local/bin/ctlenum /dev/snd/controlC0 SET "ADC R Mux" "Right Preamplifier" >/dev/null 2>&1
/usr/local/bin/ctlenum /dev/snd/controlC0 SET "PGA L Mux" "AIN0" >/dev/null 2>&1
/usr/local/bin/ctlenum /dev/snd/controlC0 SET "PGA R Mux" "AIN0" >/dev/null 2>&1
# PGA Volume is an integer control; amixer is present with alsa-utils.
# The codec can still be registering while controlC0 exists, so retry.
if command -v amixer >/dev/null 2>&1; then
	for i in $(seq 1 40); do
		amixer -c0 cget numid=81 >/dev/null 2>&1 && break
		sleep 0.25
	done
	amixer -c0 cset numid=81 4,4 >/dev/null 2>&1
fi
exit 0
