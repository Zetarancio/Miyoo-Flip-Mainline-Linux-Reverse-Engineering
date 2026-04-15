#!/bin/sh

killall rtk_hciattach

echo 0 > /sys/class/rfkill/rfkill0/state
echo 0 > /proc/bluetooth/sleep/btwrite
sleep 0.5
echo 1 > /sys/class/rfkill/rfkill0/state
echo 1 > /proc/bluetooth/sleep/btwrite
sleep 0.5

insmod /usr/lib/modules/rtk_btusb.ko
rtk_hciattach -n -s 115200 /dev/ttyS0 rtk_h5 &
