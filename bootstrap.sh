#!/usr/bin/env bash

case "${1}" in
  (--apt|--deb)
    export dist_type=Debian
    sudo apt install ansible
    ansible-galaxy install geerlingguy.docker
   ;;
  (''|*)
    export dist_type=Fedora
    sudo dnf install ansible
    ansible-galaxy install geerlingguy.docker
   ;;
esac
