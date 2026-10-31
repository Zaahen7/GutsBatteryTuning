#!/system/bin/sh

#
# Tweaks Config
#
zram2zstd="true" # Change ZRAM to ZSTD algorithm
change_zram_swappiness="true" # Change ZRAM Swappiness XD
ego_rate_limit="true" # Increase the time to decide the CPU frequency
heavy_tb="true" # Less overestimation of a task so less tendency to trigger high frequencies
gpu_hsdelay="true" # Increase the cycles to decide the GPU frequency
min_freq_limit="true" # A cap to prevent apps from keeping the minimum frequency locked too high
net_scheduler="false" # Change WIFI net scheduler to avoid bufferbloat


# Tweaks Values
# Dont change these values if you dont know what they do
zram_swappiness="130"
time_after_boot="180"
ego_rate_limit_big="6"
ego_rate_limit_little="16"
heavy_tb_big="100"
heavy_tb_little="100"
gpu_hsdelay_value="2"
min_freq_limit_big="754000"
min_freq_limit_little="672000"
net_sched="fq_codel"
