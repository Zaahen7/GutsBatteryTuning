#!/system/bin/sh
MOD_DIR=${0%/*}
if [ -f "$MOD_DIR/config.sh" ]; then
    source "$MOD_DIR/config.sh"
else
    echo "config.sh missing"
    exit 1
fi

echo "Running system checks..."
echo ""

rate0=$(cat /sys/devices/platform/ems/emstune/cur_set 2>/dev/null | grep -A10 "cpufreq gov" | sed -n '4p' | awk '{print $7}')
rate4=$(cat /sys/devices/platform/ems/emstune/cur_set 2>/dev/null | grep -A10 "cpufreq gov" | sed -n '8p' | awk '{print $7}')
htb0=$(cat /sys/devices/platform/ems/emstune/cur_set 2>/dev/null | grep -A10 "cpufreq gov" | sed -n '4p' | awk '{print $3}')
htb4=$(cat /sys/devices/platform/ems/emstune/cur_set 2>/dev/null | grep -A10 "cpufreq gov" | sed -n '8p' | awk '{print $3}')
echo "=== EGO Rate-Limit ==="
echo "Little Cluster: ${rate0}ms"
echo "Big Cluster: ${rate4}ms"
echo "Heavy Task Boost (Little): ${htb0}"
echo "Heavy Task Boost (Big): ${htb4}"
echo ""

minfq0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq_limit 2>/dev/null)
minfq4=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq_limit 2>/dev/null)
echo "=== CPU Min Freq ==="
echo "Little: ${minfq0}"
echo "Big: ${minfq4}"
echo ""

gpuhsdelay=$(cat /sys/devices/platform/10300000.mali/highspeed_delay 2>/dev/null)
zramalgo=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -oE '\[[^]]+\]' | tr -d '[]')
mem_available_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
mem_available_mb=$(awk "BEGIN { printf \"%.0f\", $mem_available_kb/1024 }")

echo "=== Additional Info ==="
echo "GPU Highspeed Delay: ${gpuhsdelay}"
echo "Zram Algorithm: ${zramalgo}"
echo "Zram Swappiness: $(cat /proc/sys/vm/swappiness 2>/dev/null)"
echo "RAM Available: ${mem_available_mb}MB"
echo ""

echo "Module made by @Zaahen7"

if [ ! -f "$MOD_DIR/.applied" ]; then
    echo "Some tweaks not applied yet."
    echo ""
    exit 0
fi

# ===== Update module description =====
ZSTD_PART=""; RL_PART=""; HTB_PART=""; GPU_PART=""; MINFQ_PART=""; SWAP_PART=""; NETSCH_PART=""

if [ "$zram2zstd" = "true" ]; then
    zstd_state="❌"
    [ "$zramalgo" = "zstd" ] && zstd_state="✅"
    ZSTD_PART="ZSTD ${zstd_state}"
fi

if [ "$ego_rate_limit" = "true" ]; then
    rl_state="❌"
    [ "$rate4" = "$ego_rate_limit_big" ] && [ "$rate0" = "$ego_rate_limit_little" ] && rl_state="✅"
    RL_PART="RL ${rl_state}"
fi

if [ "$heavy_tb" = "true" ]; then
    htb_state="❌"
    [ "$htb4" = "$heavy_tb_big" ] && [ "$htb0" = "$heavy_tb_little" ] && htb_state="✅"
    HTB_PART="HTB ${htb_state}"
fi

if [ "$gpu_hsdelay" = "true" ]; then
    gpu_hs_state="❌"
    [ "$gpuhsdelay" = "$gpu_hsdelay_value" ] && gpu_hs_state="✅"
    GPU_PART="GPU ${gpu_hs_state}"
fi

if [ "$min_freq_limit" = "true" ]; then
    minfq_state="❌"
    [ "$minfq0" = "$min_freq_limit_little" ] && [ "$minfq4" = "$min_freq_limit_big" ] && minfq_state="✅"
    MINFQ_PART="MINFQ ${minfq_state}"
fi

if [ "$change_zram_swappiness" = "true" ]; then
    swappiness_state="❌"
    [ "$(cat /proc/sys/vm/swappiness 2>/dev/null)" = "$zram_swappiness" ] && swappiness_state="✅"
    SWAP_PART="SWAP ${swappiness_state}"
fi

if [ "$net_scheduler" = "true" ]; then
    net_sch_state="❌"
    tc qdisc show dev wlan0 2>/dev/null | grep -q "$net_sched" && net_sch_state="✅"
    NETSCH_PART="NET ${net_sch_state}"
fi

STATUS=""
for part in "$ZSTD_PART" "$RL_PART" "$HTB_PART" "$GPU_PART" "$MINFQ_PART" "$SWAP_PART" "$NETSCH_PART"; do
    [ -n "$part" ] && STATUS="${STATUS:+$STATUS }$part"
done

[ -z "$STATUS" ] && STATUS="No tweaks enabled"

sed -i "s|^description=.*|description=$STATUS|" "$MOD_DIR/module.prop"
echo "Module Status Updated: $STATUS"
echo ""
exit 0