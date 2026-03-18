#!/bin/sh
echo $0 $*
progdir=`dirname "$0"`
cd $progdir
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$progdir
devsd=/dev/mmcblk2
echo "=============================================="
echo "============== USB Storage Mode  ============="
echo "=============================================="

TMP_RUN_PATH=/tmp/usb_storage_app/

echo 1 > /tmp/stay_awake

if [ -e /dev/mmcblk2p1 ]
then
devsd="/dev/mmcblk2p1"
fi

if [ -e /dev/mmcblk1 ]
then
devsd="/dev/mmcblk1"
fi

if [ -e /dev/mmcblk1p1 ]
then
devsd="/dev/mmcblk1p1"
fi

echo SD dev:$devsd

sync
swapoff -a

mkdir $TMP_RUN_PATH
cp usb_storage $TMP_RUN_PATH
cp bg.png $TMP_RUN_PATH
cd $TMP_RUN_PATH

umount -l /mnt/SDCARD
umount -l /mnt/sdcard

echo "usb_ums_en" > /tmp/.usb_config
echo "ums_block=$devsd" >> /tmp/.usb_config
/etc/init.d/S50usbdevice restart

chmod 777 usb_storage
./usb_storage
sync

echo "usb_adb_en" > /tmp/.usb_config
/etc/init.d/S50usbdevice restart
sleep 2
mount $devsd -t exfat /mnt/SDCARD
mount $devsd -t vfat /mnt/SDCARD

rm /tmp/stay_awake
