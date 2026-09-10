#!/bin/bash
#========================================================================================================================
# https://github.com/ophub/amlogic-s9xxx-openwrt
# Description: Automatically Build OpenWrt
# Function: Diy script (After Update feeds, Modify the default IP, hostname, theme, add/remove software packages, etc.)
# Source code repository: https://github.com/coolsnowwolf/lede / Branch: master
#========================================================================================================================
# ------------------------------- Main source started -------------------------------
#
# Set default IP address
default_ip="192.168.1.1"
ip_regex="^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
# Modify default IP if an argument is provided and it matches the IP format
[[ -n "${1}" && "${1}" != "${default_ip}" && "${1}" =~ ${ip_regex} ]] && {
    echo "Modify default IP address to: ${1}"
    sed -i "/lan) ipad=\${ipaddr:-/s/\${ipaddr:-\"[^\"]*\"}/\${ipaddr:-\"${1}\"}/" package/base-files/*/bin/config_generate
}
# Modify default theme（FROM uci-theme-bootstrap CHANGE TO luci-theme-material）
# sed -i 's/luci-theme-bootstrap/luci-theme-material/g' ./feeds/luci/collections/luci/Makefile
# Add autocore support for armsr-armv8
sed -i 's/TARGET_rockchip/TARGET_rockchip\|\|TARGET_armsr/g' package/lean/autocore/Makefile
# Set etc/openwrt_release
sed -i "s|DISTRIB_REVISION='.*'|DISTRIB_REVISION='R$(date +%Y.%m.%d)'|g" package/lean/default-settings/files/zzz-default-settings
echo "DISTRIB_SOURCEREPO='github.com/coolsnowwolf/lede'" >>package/base-files/files/etc/openwrt_release
echo "DISTRIB_SOURCECODE='lede'" >>package/base-files/files/etc/openwrt_release
echo "DISTRIB_SOURCEBRANCH='master'" >>package/base-files/files/etc/openwrt_release
# Set ccache
# Remove existing ccache settings
sed -i '/CONFIG_DEVEL/d' .config
sed -i '/CONFIG_CCACHE/d' .config
# Apply new ccache configuration
if [[ "${2}" == "true" ]]; then
    echo "CONFIG_DEVEL=y" >>.config
    echo "CONFIG_CCACHE=y" >>.config
    echo 'CONFIG_CCACHE_DIR="$(TOPDIR)/.ccache"' >>.config
else
    echo '# CONFIG_DEVEL is not set' >>.config
    echo "# CONFIG_CCACHE is not set" >>.config
    echo 'CONFIG_CCACHE_DIR=""' >>.config
fi
#
# ------------------------------- Main source ends -------------------------------
# ------------------------------- Other started -------------------------------
#
# Add luci-app-amlogic
rm -rf package/luci-app-amlogic
git clone -b main https://github.com/ophub/luci-app-amlogic.git package/luci-app-amlogic
#
# Apply patch
# git apply ../config/patches/{0001*,0002*}.patch --directory=feeds/luci
#
# ------------------------------- Other ends -------------------------------
#============================================
# Fix open-app-filter for kernel >=6.6
#  - del_timer_sync -> timer_delete_sync (conditional compile)
#  - mark unused variables with __maybe_unused
#============================================
OAF_DIR="./feeds/packages/net/open-app-filter"
if [ -d "${OAF_DIR}" ]; then
    echo "Applying open-app-filter kernel compatibility patch..."
    mkdir -p "${OAF_DIR}/patches"
    cat > "${OAF_DIR}/patches/100-fix-kernel-compat.patch" <<'EOF'
--- a/oaf/src/app_filter.c
+++ b/oaf/src/app_filter.c
@@ -270,7 +270,7 @@ int add_app_feature(int appid, char *name, char *feature)
        char *p = feature;
        char *value;
        int proto = 0;
-       int dst_port = 0;
+       int dst_port __maybe_unused = 0;
        int src_port = 0;
        char *app_name = NULL;
        char *app_id_str = NULL;
@@ -568,7 +568,7 @@ int parse_flow_proto(struct sk_buff *skb, flow_info_t *flow)
        int ret = 0;
        if (flow->proto == IPPROTO_TCP || flow->proto == IPPROTO_UDP)
        {
-               struct nf_conn *ct = NULL;
+               struct nf_conn *ct __maybe_unused = NULL;
        }
@@ -1284,7 +1284,7 @@ u_int32_t app_filter_hook_gateway_handle(struct sk_buff *skb, struct net_device *dev)
        {
                flow_info_t flow;
                int ret = 0;
-               u_int8_t smac[ETH_ALEN];
+               u_int8_t smac[ETH_ALEN] __maybe_unused;

                memset(&flow, 0, sizeof(flow_info_t));
@@ -1565,7 +1565,11 @@ void fini_oaf_timer(void)
 {
-       del_timer_sync(&oaf_timer);
+#if LINUX_VERSION_CODE >= KERNEL_VERSION(6,6,0)
+       timer_delete_sync(&oaf_timer);
+#else
+       del_timer_sync(&oaf_timer);
+#endif
 }
EOF
    echo "open-app-filter patch created: ${OAF_DIR}/patches/100-fix-kernel-compat.patch"
else
    echo "Warning: open-app-filter directory not found at ${OAF_DIR}, skip patch."
fi
