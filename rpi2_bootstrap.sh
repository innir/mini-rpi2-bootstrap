#!/bin/sh

# Are we running as root?
if [ "$(id -u)" -ne "0" ] ; then
  echo "error: this script must be executed with root privileges!"
  exit 1
fi

# Execute command in chroot
chroot_exec() {
  LANG=C LC_ALL=C DEBIAN_FRONTEND=noninteractive chroot ${DIR} $*
}

# Load config file if present
if [ -r "./config" ] ; then
  echo "Loading local config ..."
  . ./config
fi

### Begin config parameters
DIR=${DIR:="image"}
QEMU_BINARY=${QEMU_BINARY:="/usr/bin/qemu-arm-static"}
DEFLOCAL=${DEFLOCAL:="de_DE.UTF-8"}
TIMEZONE=${TIMEZONE:="Europe/Berlin"}
# Install these packages already during bootstrap to be able to tweak their
# configuration before installing the other packages
EARLY_PACKAGES="apt-transport-https,console-setup,flash-kernel,locales,u-boot-rpi,u-boot-tools"
# Only install these packages afer copying all modifications
PACKAGES=${PACKAGES:="cryptsetup linux-image-armmp rng-tools ssh wget"}
# Packages to customize the system
CUSTOM_PACKAGES=${CUSTOM_PACKAGES:=""}
### End config parameters

# Base debootstrap (unpack only)
debootstrap --arch=armhf --foreign --include="${EARLY_PACKAGES}" stretch "${DIR}" https://deb.debian.org/debian/

# Copy qemu emulator binary to chroot
install -m 755 -o root -g root "${QEMU_BINARY}" "${DIR}${QEMU_BINARY}"

# Complete the bootstrapping process
chroot_exec /debootstrap/debootstrap --second-stage

# Install config files
rsync --chown=root:root -a boot/ "${DIR}/boot/"
rsync --chown=root:root -a etc/ "${DIR}/etc/"
rsync --chown=root:root -a usr/ "${DIR}/usr/"

# Copy u-boot binary
cp "${DIR}/usr/lib/u-boot/rpi_2/u-boot.bin" "${DIR}/boot/firmware/"

# Mount required filesystems
mount -t proc none "${DIR}/proc"
mount -t sysfs none "${DIR}/sys"

# Mount pseudo terminal slave if supported by Debian release
if [ -d "${DIR}/dev/pts" ] ; then
  mount --bind /dev/pts "${DIR}/dev/pts"
fi

# Setting up timezone and ntp
echo ${TIMEZONE} > "${DIR}/etc/timezone"
chroot_exec systemctl enable systemd-timesyncd

# Generate locales for en_US.UTF-8 and the default locale
chroot_exec echo "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8, ${DEFLOCAL} UTF-8" | debconf-set-selections
sed -i "/en_US.UTF-8/s/^#//" "${DIR}/etc/locale.gen"
sed -i "/${DEFLOCAL}/s/^#//" "${DIR}/etc/locale.gen"
chroot_exec locale-gen
chroot_exec update-locale LANG="${DEFLOCAL}"

# Set keyboard layout to default locale
KEB="${DEFLOCAL%%"${DEFLOCAL#??}"}" # get the first two chars from ${DEFLOCAL}
sed -i "s/^XKBLAYOUT.*/XKBLAYOUT=\"${KEB}\"/" "${DIR}/etc/default/keyboard"

# Set the charmap to UTF-8
chroot_exec echo "console-setup console-setup/charmap47 select UTF-8" | debconf-set-selections
sed -i 's/^CHARMAP.*/CHARMAP="UTF-8"/' "${DIR}/etc/default/console-setup"

# Update package lists and installed packages
chroot_exec apt update
chroot_exec apt dist-upgrade -y
# Install the rest of the packages
chroot_exec apt install -y ${PACKAGES} ${CUSTOM_PACKAGES}
# Removing unused packages and cleaning the apt cache
chroot_exec apt autoremove
chroot_exec apt clean

# Download current Raspberry Pi 2 firmware
chroot_exec fw-update

# Setting up the network
chroot_exec systemctl enable systemd-networkd
chroot_exec systemctl enable systemd-resolved
rm -f "${DIR}/etc/resolv.conf"
chroot_exec ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

# Enable serial console
chroot_exec systemctl enable serial-getty\@ttyAMA0.service

# Setting a password for root
echo ""
echo "Choose a password for 'root' ..."
chroot_exec passwd

# Clean up all temporary mount points
echo "removing temporary mount points ..."
umount -l "${DIR}/proc" 2> /dev/null
umount -l "${DIR}/sys" 2> /dev/null
umount -l "${DIR}/dev/pts" 2> /dev/null

