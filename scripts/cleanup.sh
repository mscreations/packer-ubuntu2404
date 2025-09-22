#!/bin/sh -eux


# Delete hyper-v tooling when using different builder
if [ "$PACKER_BUILDER_TYPE" != "hyperv-iso" ]; then
    apt-get -y remove linux-image-virtual linux-tools-virtual linux-cloud-tools-virtual
fi

# Delete virtual box tools artifacts if present
if [ "$PACKER_BUILDER_TYPE" = "virtualbox-iso" ]; then
    if [ -f "$HOME/VBoxGuestAdditions.iso" ]; then
    rm -f "$HOME/VBoxGuestAdditions.iso"
    fi
fi

echo "remove linux-headers"
dpkg --list \
  | awk '{ print $2 }' \
  | grep 'linux-headers' || true \
  | xargs -r apt-get -y purge;

echo "remove specific Linux kernels, such as linux-image-3.11.0-15-generic but keeps the current kernel and does not touch the virtual packages"
dpkg --list \
    | awk '{ print $2 }' \
    | grep 'linux-image-.*-generic' || true \
    | grep -v "$(uname -r)" || true \
    | xargs -r apt-get -y purge;

echo "remove old kernel modules packages"
dpkg --list \
    | awk '{ print $2 }' \
    | grep 'linux-modules-.*-generic' || true \
    | grep -v "$(uname -r)" || true \
    | xargs -r apt-get -y purge;

echo "remove linux-source package"
dpkg --list \
    | awk '{ print $2 }' \
    | grep linux-source || true \
    | xargs -r apt-get -y purge;

# 23.10 gives dependency errors for systemd-dev package
echo "remove all development packages"
dpkg --list \
    | awk '{ print $2 }' \
    | grep -- '-dev\(:[a-z0-9]\+\)\?$' || true \
    | xargs -r -I % apt-get -y purge % || true;

echo "remove docs packages"
dpkg --list \
    | awk '{ print $2 }' \
    | grep -- '-doc$' || true \
    | xargs -r apt-get -y purge;

echo "remove X11 libraries"
apt-get -y purge libx11-data xauth libxmuu1 libxcb1 libx11-6 libxext6;

echo "remove obsolete networking packages"
apt-get -y purge ppp pppconfig pppoeconf;

echo "remove packages we don't need"
apt-get -y purge popularity-contest command-not-found friendly-recovery bash-completion laptop-detect motd-news-config usbutils grub-legacy-ec2

# 22.04+ don't have this
echo "remove the fonts-ubuntu-font-family-console"
apt-get -y purge fonts-ubuntu-font-family-console || true;

# 21.04+ don't have this
echo "remove the installation-report"
apt-get -y purge popularity-contest installation-report || true;

echo "remove the console font"
apt-get -y purge fonts-ubuntu-console || true;

# Exclude the files we don't need w/o uninstalling linux-firmware
echo "==> Setup dpkg excludes for linux-firmware"
cat <<_EOF_ | cat >> /etc/dpkg/dpkg.cfg.d/excludes
path-exclude=/lib/firmware/*
path-exclude=/usr/share/doc/linux-firmware/*
_EOF_

# Delete the massive firmware packages
rm -rf /lib/firmware/*
rm -rf /usr/share/doc/linux-firmware/*

apt-get -y autoremove;
apt-get -y clean;

# Remove docs
rm -rf /usr/share/doc/*

# Remove caches
find /var/cache -type f -exec rm -rf {} \;

# truncate any logs that have built up during the install
find /var/log -type f -exec truncate --size=0 {} \;

# Blank netplan machine-id (DUID) so machines get unique ID generated on boot.
truncate -s 0 /etc/machine-id

# remove the contents of /tmp and /var/tmp
rm -rf /tmp/* /var/tmp/*

# Clear the history
export HISTSIZE=0
rm -f /root/.wget-hsts

echo "force a new random seed to be generated"
rm -f /var/lib/systemd/random-seed

# Whiteout root
count=$(df --sync -kP / | tail -n1  | awk -F ' ' '{print $4}')
count=$(($count-1))
dd if=/dev/zero of=/tmp/whitespace bs=1M count=$count || echo "dd exit code $? is suppressed";
rm /tmp/whitespace

# Whiteout /boot
count=$(df --sync -kP /boot | tail -n1 | awk -F ' ' '{print $4}')
count=$(($count-1))
dd if=/dev/zero of=/boot/whitespace bs=1M count=$count || echo "dd exit code $? is suppressed";
rm /boot/whitespace

set +e
swapuuid="`/sbin/blkid -o value -l -s UUID -t TYPE=swap`";
case "$?" in
    2|0) ;;
    *) exit 1 ;;
esac
set -e

if [ "x${swapuuid}" != "x" ]; then
    # Whiteout the swap partition to reduce box size
    # Swap is disabled till reboot
    swappart="`readlink -f /dev/disk/by-uuid/$swapuuid`";
    /sbin/swapoff "$swappart";
    dd if=/dev/zero of="$swappart" bs=1M || echo "dd exit code $? is suppressed";
    /sbin/mkswap -U "$swapuuid" "$swappart";
fi

sync;