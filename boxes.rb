#!/usr/bin/ruby
#

APT_ENV_VARS = {
  'DEBIAN_FRONTEND': 'noninteractive',
  'DEBCONF_NONINTERACTIVE_SEEN': true,
}

INSTALL_ENV_VARS = {
  'VAGRANT_LIBVIRT_VERSION': ENV.fetch('QA_VAGRANT_LIBVIRT_VERSION', 'latest'),
}

BOXES = {
  'ubuntu-22.04' => {
    :libvirt => {
      :box => "cloud-image/ubuntu-22.04",
    },
  },
  'ubuntu-24.04' => {
    :libvirt => {
      :box => "cloud-image/ubuntu-24.04",
    },
  },
  'ubuntu-26.04' => {
    :libvirt => {
      :box => "cloud-image/ubuntu-26.04",
    },
  },
  'debian-10' => {
    :libvirt => {
      :box => "generic/debian10",
      :provision => [
        {:name => 'disable dns-nameservers', :inline => 'sed -i -e "/^dns-nameserver/g" /etc/network/interfaces', :reboot => true},
        # restarting dnsmasq can require a retry after everything else to come up correctly.
        {:name => 'install dnsmasq', :inline => 'apt update && apt install -y dnsmasq && systemctl restart dnsmasq', :env => APT_ENV_VARS},
      ],
    },
  },
  'debian-11' => {
    :libvirt => {
      :box => "generic/debian11",
      :provision => [
        {:name => 'disable dns-nameservers', :inline => 'sed -i -e "/^dns-nameserver/g" /etc/network/interfaces', :reboot => true},
        # restarting dnsmasq can require a retry after everything else to come up correctly.
        {:name => 'install dnsmasq', :inline => 'apt update && apt install -y dnsmasq && systemctl restart dnsmasq', :env => APT_ENV_VARS},
      ],
    },
  },
  'centos-7' => {
    :libvirt => {
      :box => "generic/centos7",
    },
  },
  'centos-8' => {
    :libvirt => {
      :box => "generic/centos8",
    },
  },
  'centos-8-stream' => {
    :libvirt => {
      :box => "generic/centos8s",
    },
  },
  'centos-9-stream' => {
    :libvirt => {
      :box => "generic/centos9s",
    },
  },
  'fedora-34' => {
    :libvirt => {
      :box => "generic/fedora34",
    },
  },
  'fedora-35' => {
    :libvirt => {
      :box => "generic/fedora35",
    },
  },
  'fedora-36' => {
    :libvirt => {
      :box => "generic/fedora36",
    },
  },
  'archlinux' => {
    :libvirt => {
      :box => "archlinux/archlinux",
    },
  },
  'opensuse-leap' => {
    :libvirt => {
      :box => "opensuse/Leap-15.4.x86_64",
    },
  },
}

DEFAULT_PROVISION = [
  {:name => 'install script', :privileged => false, :path => './scripts/install.bash', :args => ENV['QA_VAGRANT_VERSION'].nil? ? "" : "--vagrant-version #{ENV['QA_VAGRANT_VERSION']}", :env => INSTALL_ENV_VARS},
  {:name => 'setup group', :reset => true, :inline => 'usermod -a -G libvirt vagrant'},
  {:name => 'debug system capabilities', :privileged => false, :inline => 'virsh --connect qemu:///system capabilities'},
  {:name => 'debug uri', :privileged => false, :inline => 'virsh uri'},
]

# Inside a user namespace such as a rootless podman container, libvirt
# can't set the trusted.* xattrs it uses to record the original owner of
# files it relabels, nor chown the device nodes it creates in a private
# /dev for each domain.
DOCKER_POST_INSTALL = [
  {:name => 'configure libvirt for containers', :inline => <<-EOC},
    echo "remember_owner = 0" >> /etc/libvirt/qemu.conf
    echo "namespaces = []" >> /etc/libvirt/qemu.conf
    for service in libvirtd virtqemud; do
      systemctl is-active -q ${service} && systemctl restart ${service}
    done
    true
  EOC
]

if __FILE__ == $0
  require 'json'
  puts JSON.pretty_generate(BOXES)
end
