p='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ctrl.c'
s=open(p).read()
if 't1100_patch_responder' not in s:
    s=s.replace('int t1100_patch_active;','''int t1100_patch_active;

/*
 * T1100 (M41): stand in for the vendor userspace daemon (wmt_launcher/
 * srh_rom_patch) so the *unmodified* multi-patch path runs: patch search
 * succeeds, the patch name and its 4 address bytes are provided, patch_num=1.
 */
static char t1100_responder_name[128] = "ROMv4_be_patch_1_0_hdr.bin";
module_param_string(t1100_responder_name, t1100_responder_name,
		    sizeof(t1100_responder_name), 0444);
static int t1100_patch_responder;
module_param(t1100_patch_responder, int, 0444);
MODULE_PARM_DESC(t1100_patch_responder, "T1100: answer srh_patch/get patch name in-kernel (like wmt_launcher)");''')

    # patch_search: pretend userspace answered
    old_search='''	osal_snprintf(cmdStr, NAME_MAX, "srh_patch");
	iRet = wmt_ctrl_ul_cmd(pDev, cmdStr);'''
    new_search='''	if (t1100_patch_responder) {
		WMT_INFO_FUNC("t1100: srh_patch answered in-kernel\\n");
		return 0;
	}
	osal_snprintf(cmdStr, NAME_MAX, "srh_patch");
	iRet = wmt_ctrl_ul_cmd(pDev, cmdStr);'''
    assert s.count(old_search)==1
    s=s.replace(old_search,new_search)
    open(p,'w').write(s)
    print("wmt_ctrl.c patched (search)")

# get_patch_name: give the file name + address bytes from the header
p2='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ctrl.c'
s2=open(p2).read()
print("get_patch_name body:")
import re
m=re.search(r'INT32 wmt_ctrl_get_patch_name\(P_WMT_CTRL_DATA[^)]*\)\n\{(.*?)\n\}', s2, re.S)
print(m.group(1)[:600] if m else "not found")
