# vagrant-libvirt-qa
Scripts for QA


## How to test a distro

    ruby boxes.rb | jq -r 'keys[]'
    vagrant up ubuntu-22.04

or in a container, as CI does:

    export VAGRANT_DEFAULT_PROVIDER=docker VAGRANT_LIBVIRT_DRIVER=qemu
    vagrant up --no-provision ubuntu-22.04
    vagrant provision ubuntu-22.04
