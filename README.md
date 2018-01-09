# Minimal full disc encryption bootstrap for Raspberry Pi 2

The script bootstraps Debian Stretch, sets up the most important bits and makes
it easy to run an full encrypted unmodified Debian on the Raspberry Pi 2.

The resulting system is *very* basic, you need to be able to secure it, to add 
users etc.


## Dependencies

On Debian you need to install these packages:

* debootstrap
* rsync
* qemu-user-static


## Customizing the script

In the script `rpi2_bootstrap.sh` you find some variables to change timezone,
locale, installed packages and the like, they should be pretty self explanatory.

To do further customization you can add and/or modify files in the directories
`boot`, `etc` and `usr`. Their content is copied into the resulting system.


# Bootstrapping

To bootstrap the whole thing into directory `DIR`, run:

```
sudo ./rpi2_bootstrap.sh
```


## Setting a root password

You should now set a root password:

`passwd --root DIR root`


## Partitioning your sdcard

The approach relies on a three partition layout of the sdcard:

* `/dev/mmcblk0p1`, *Firmware partition*, VFAT, ~50 MB
* `/dev/mmcblk0p2`, *Boot partition*, EXT4, ~100 MB
* `/dev/mmcblk0p3`, *Encrypted root partition*, LUKS, > 1 GB
  - It's assumed that a EXT4 file system exists within the LUKS partition which
    is accessible as `/dev/mapper/root`


## Copying the bits to your sdcard

1. Everything in `/boot/firmware` should be copied to `/dev/mmcblk0p1`
2. Everything in `/boot` should be copied to `/dev/mmcblk0p2`
3. Everything else should be copied to `/dev/mapper/root`

The easiest way to achieve this is to mount the partitions as follows and use
rsync to copy the data:

```
mkdir sdcard
mount /dev/mapper/root sdcard
mount /dev/mmcblk0p1 sdcard/boot
mount /dev/mmcblk0p2 sdcard/boot/firmware

rsync -a DIR/ sdcard/
```


## Fixing up the initramdisk and making the Raspberry Pi boot

Unfortunately the first boot will fail, but it's pretty easy to fix. During
boot you will hit the initramfs prompt `(initramfs)` you have to unlock the
encrypted root partition to continue the boot process:

```
cryptsetup luksOpen /dev/mmcblk0p3 root
exit
```

After booting the Raspberry Pi you have to fix the initramfs:

`update-initramfs -k all`

Reboot to check if everything works.
