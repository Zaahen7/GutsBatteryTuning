
#!/system/bin/sh

MOD_DIR="${0%/*}"

# ===== Load Configuration =====
if [ -f "$MOD_DIR/config.sh" ]; then
    . "$MOD_DIR/config.sh"
else
    echo "ERROR: config.sh missing"
    exit 1
fi

echo "Running system checks..."
echo ""

# ===== EGO Rate-Limit =====
CUR_SET=$(cat /sys/devices/platform/ems/emstune/cur_set 2>/dev/null)

rate0=$(printf '%s\n' "$CUR_SET" | grep -A10 "cpufreq gov" | sed -n '4p' | awk '{print $7}')
rate4=$(printf '%s\n' "$CUR_SET" | grep -A10 "cpufreq gov" | sed -n '8p' | awk '{print $7}')

htb0=$(printf '%s\n' "$CUR_SET" | grep -A10 "cpufreq gov" | sed -n '4p' | awk '{print $3}')
htb4=$(printf '%s\n' "$CUR_SET" | grep -A10 "cpufreq gov" | sed -n '8p' | awk '{print $3}')

echo "=== EGO Rate-Limit ==="
echo "Little Cluster: ${rate0:-N/A}ms"
echo "Big Cluster: ${rate4:-N/A}ms"
echo "Heavy Task Boost (Little): ${htb0:-N/A}"
echo "Heavy Task Boost (Big): ${htb4:-N/A}"
echo ""

# ===== CPU Min Frequency =====
minfq0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq_limit 2>/dev/null)
minfq4=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq_limit 2>/dev/null)

echo "=== CPU Min Freq ==="
echo "Little: ${minfq0:-N/A}"
echo "Big: ${minfq4:-N/A}"
echo ""

# ===== Additional Information =====
gpuhsdelay=$(cat /sys/devices/platform/10300000.mali/highspeed_delay 2>/dev/null)

zramalgo=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null |
    grep -oE '\[[^]]+\]' | tr -d '[]')

mem_available_kb=$(awk '/MemAvailable:/ {print $2; exit}' /proc/meminfo)
mem_available_mb=$(( ${mem_available_kb:-0} / 1024 ))

swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null)

echo "=== Additional Info ==="
echo "GPU Highspeed Delay: ${gpuhsdelay:-N/A}"
echo "Zram Algorithm: ${zramalgo:-N/A}"
echo "Zram Swappiness: ${swappiness:-N/A}"
echo "RAM Available: ${mem_available_mb}MB"
echo ""

echo "Module made by @Zaahen7"
echo ""

# ===== Applied Check =====
if [ ! -f "$MOD_DIR/.applied" ]; then
    echo "Some tweaks not applied yet."
    echo ""
    exit 0
fi

# ===== Update Module Description =====
ZSTD_PART=""
RL_PART=""
HTB_PART=""
GPU_PART=""
MINFQ_PART=""
SWAP_PART=""
NETSCH_PART=""

# ZSTD
if [ "$zram2zstd" = "true" ]; then
    zstd_state="❌"
    [ "$zramalgo" = "zstd" ] && zstd_state="✅"
    ZSTD_PART="ZSTD ${zstd_state}"
fi

# EGO Rate-Limit
if [ "$ego_rate_limit" = "true" ]; then
    rl_state="❌"

    if [ "$rate4" = "$ego_rate_limit_big" ] &&
       [ "$rate0" = "$ego_rate_limit_little" ]; then
        rl_state="✅"
    fi

    RL_PART="RL ${rl_state}"
fi

# Heavy Task Boost
if [ "$heavy_tb" = "true" ]; then
    htb_state="❌"

    if [ "$htb4" = "$heavy_tb_big" ] &&
       [ "$htb0" = "$heavy_tb_little" ]; then
        htb_state="✅"
    fi

    HTB_PART="HTB ${htb_state}"
fi

# GPU Highspeed Delay
if [ "$gpu_hsdelay" = "true" ]; then
    gpu_hs_state="❌"

    [ "$gpuhsdelay" = "$gpu_hsdelay_value" ] && gpu_hs_state="✅"

    GPU_PART="GPU ${gpu_hs_state}"
fi

# CPU Min Frequency
if [ "$min_freq_limit" = "true" ]; then
    minfq_state="❌"

    if [ "$minfq0" = "$min_freq_limit_little" ] &&
       [ "$minfq4" = "$min_freq_limit_big" ]; then
        minfq_state="✅"
    fi

    MINFQ_PART="MINFQ ${minfq_state}"
fi

# ZRAM Swappiness
if [ "$change_zram_swappiness" = "true" ]; then
    swappiness_state="❌"

    [ "$swappiness" = "$zram_swappiness" ] && swappiness_state="✅"

    SWAP_PART="SWAP ${swappiness_state}"
fi

# Network Scheduler
if [ "$net_scheduler" = "true" ]; then
    net_sch_state="❌"

    tc qdisc show dev wlan0 2>/dev/null | grep -q "$net_sched" &&
        net_sch_state="✅"

    NETSCH_PART="NET ${net_sch_state}"
fi

# ===== Build Status =====
STATUS=""

for part in \
    "$ZSTD_PART" \
    "$RL_PART" \
    "$HTB_PART" \
    "$GPU_PART" \
    "$MINFQ_PART" \
    "$SWAP_PART" \
    "$NETSCH_PART"
do
    [ -n "$part" ] && STATUS="${STATUS:+$STATUS }$part"
done

[ -z "$STATUS" ] && STATUS="No tweaks enabled"

# ===== Update module.prop =====
if [ -f "$MOD_DIR/module.prop" ]; then
    if sed -i "s|^description=.*|description=$STATUS|" "$MOD_DIR/module.prop"; then
        echo "Module Status Updated: $STATUS"
    else
        echo "ERROR: Failed to update module.prop"
    fi
else
    echo "ERROR: module.prop missing"
fi

echo ""
exit 0
