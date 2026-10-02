#!/usr/bin/ruby
#

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
  'debian-12' => {
    :libvirt => {
      :box => "cloud-image/debian-12",
    },
  },
  'debian-13' => {
    :libvirt => {
      :box => "cloud-image/debian-13",
    },
  },
  'centos-9-stream' => {
    :libvirt => {
      :box => "centos-stream-9",
      :box_url => "https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-Vagrant-Libvirt-9-latest.x86_64.vagrant-libvirt.box",
    },
  },
  'centos-10-stream' => {
    :libvirt => {
      :box => "centos-stream-10",
      :box_url => "https://cloud.centos.org/centos/10-stream/x86_64/images/CentOS-Stream-Vagrant-Libvirt-10-latest.x86_64.vagrant-libvirt.box",
    },
  },
  'fedora-43' => {
    :libvirt => {
      :box => "fedora-cloud-base-43-1.6",
      :box_url => "https://download.fedoraproject.org/pub/fedora/linux/releases/43/Cloud/x86_64/images/Fedora-Cloud-Base-Vagrant-libvirt-43-1.6.x86_64.vagrant.libvirt.box",
    },
  },
  'fedora-44' => {
    :libvirt => {
      :box => "fedora-cloud-base-44-1.7",
      :box_url => "https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Vagrant-libvirt-44-1.7.x86_64.vagrant.libvirt.box",
    },
  },
  'archlinux' => {
    :libvirt => {
      :box => "cloud-image/arch-linux",
      :provision => [
        # Upgrading the kernel removes the modules of the running one, which
        # libvirt needs for creating the bridges of its virtual networks.
        {:name => 'upgrade system', :reboot => true, :inline => <<-EOC},
          pacman -Syu --noconfirm --noprogressbar
        EOC
      ],
    },
  },
  'opensuse-leap' => {
    :libvirt => {
      :box => "opensuse-leap-16.0",
      :box_url => "https://download.opensuse.org/distribution/leap/16.0/appliances/Leap-16.0-Minimal-VM.x86_64-Vagrant.box",
      :provision => [
        # kernel-default-base lacks the sch_htb module, without which libvirt
        # fails to start networks as it adds an htb qdisc to their bridges.
        {:name => 'install full kernel', :reboot => true, :inline => <<-EOC},
          zypper --non-interactive install --force-resolution kernel-default
        EOC
      ],
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
