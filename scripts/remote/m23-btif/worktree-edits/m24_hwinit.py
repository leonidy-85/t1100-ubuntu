#!/usr/bin/env python3
"""M24: hw_init before/after dump + IER readback (repair of a broken edit)."""
import re

p = "/home/l/m23-btif/btif_plat.c"
s = open(p).read()

# 1. repair the broken IER readback block, if it is broken
bad = re.search(r"\t/\* M24: read back the mask.*?BTIF_IER_TXEEN\)\);\n", s, re.S)
if bad and 'missing' not in bad.group(0):
    s = s[:bad.start()] + s[bad.end():]

good = (
    "\t/* M24: read back the mask instead of trusting the write */\n"
    "\tBTIF_INFO_FUNC(\"m23: IER readback 0x%08x (RX=%d TX=%d)\\n\",\n"
    "\t\t       readl((void __iomem *)BTIF_IER(base)),\n"
    "\t\t       !!(readl((void __iomem *)BTIF_IER(base)) & BTIF_IER_RXFEN),\n"
    "\t\t       !!(readl((void __iomem *)BTIF_IER(base)) & BTIF_IER_TXEEN));\n"
)
if "IER readback" not in s:
    s = s.replace("\thal_btif_rx_ier_ctrl(p_btif, true);\n",
                  "\thal_btif_rx_ier_ctrl(p_btif, true);\n" + good, 1)
else:
    # replace whatever broken text sits between the anchor and BTIF_IER_TXEEN
    s = re.sub(r"\n\t/\* M24: read back.*?BTIF_IER_TXEEN\)\);\n",
               "\n" + good, s, flags=re.S)

# 2. before/after dump around hw init
if "hw_init:before" not in s:
    s = s.replace(
        "\tint i_ret = -1;\n\tunsigned long base = p_btif->base;\n\n#if NEW_TX_HANDLING_SUPPORT",
        "\tint i_ret = -1;\n\tunsigned long base = p_btif->base;\n\n"
        "\t/* M24: before -> after, so the UART configuration is on the record. */\n"
        "\tm23_btif_dump(\"hw_init:before\");\n\n#if NEW_TX_HANDLING_SUPPORT", 1)

if "hw_init:after" not in s:
    s = s.replace(
        "\t\tBTIF_INFO_FUNC(\"m23: wak pulse sent\\n\");\n\t}\n",
        "\t\tBTIF_INFO_FUNC(\"m23: wak pulse sent\\n\");\n\t}\n"
        "\tm23_btif_dump(\"hw_init:after\");\n", 1)

open(p, "w").write(s)
print("before=%d after=%d ier=%d" % (s.count("hw_init:before"),
                                     s.count("hw_init:after"),
                                     s.count("IER readback")))
