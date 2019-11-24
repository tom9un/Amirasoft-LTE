#!/bin/sh
# Copyright (C) 2012-2014 Amarisoft
# LTEENB system config version 2015-10-28

# Run once as root after the boot to init CPUs for UHD and LTEENB

# Check root access
if [ `id -u` != 0 ] ; then 
    echo -e "\033[33mWarning, script must be run with root permissions\033[0m"
    exit 1
fi

# Disable on demand service on Ubuntu
if [ -e "/etc/lsb-release" ] ; then
    grep -i Ubuntu /etc/lsb-release
    if [ "$?" = "0" ]; then
        service ondemand stop
    fi
fi

########################################################################
# set the "performance" governor for all CPUs to have the highest
# clock frequency
for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor ; do 
  echo performance > $f
done

########################################################################
# With some video drivers (DRM KMS drivers), the cable polling blocks
# one CPU during a few tens of ms every few seconds. We disable it
# here.
if [ -f /sys/module/drm_kms_helper/parameters/poll ] ; then
  echo N > /sys/module/drm_kms_helper/parameters/poll
fi

########################################################################
# increase network buffers
sysctl -w net.core.rmem_max=50000000
sysctl -w net.core.wmem_max=1048576

