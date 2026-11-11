/* compat stub for MTK AEE/AED debug interface (drivers/misc/mediatek/aee) -- not in mainline */
#ifndef __COMPAT_AEE_H__
#define __COMPAT_AEE_H__
#define DB_OPT_WCN_ISSUE_INFO 0
void aee_kernel_dal_show(char *str);
int aee_kernel_warning_api(char *file, int line, int option, char *module, char *detail, const char *fmt, ...);
int aed_combo_exception(const int *excp_type, int len, const int *data, int data_len, const char *info);
int aed_combo_exception_api(const int *excp_type, int len, const int *data, int data_len, const char *info, int option);
#endif
