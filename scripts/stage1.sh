#!/bin/bash -eux

# # Update motd settings
cat >>/etc/update-motd.d/00-figlet<<"EOF"
#! /bin/bash

myhostname=$(hostname -s)
myhostname="$(tr '[:lower:]' '[:upper:]' <<< ${myhostname:0:1})${myhostname:1}"
figlet -c -W ${myhostname}
EOF
chmod 0755 /etc/update-motd.d/00-figlet

# Set default shell to zsh
chsh -s /usr/bin/zsh root