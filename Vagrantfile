# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  config.vm.box = "ubuntu/xenial64"
  config.vm.provider "virtualbox" do |vb|
     vb.memory = "4096"
  end
  config.vm.provision "shell", privileged: false, inline: <<-SHELL
    sudo apt-get update && sudo apt-get upgrade
    sudo apt-get install -y git build-essential unzip libsnappy-dev

    # Install latest Nim and bootstrap it
    git clone https://github.com/nim-lang/Nim.git
    cd Nim
    git clone --depth 1 https://github.com/nim-lang/csources
    cd csources && sh build.sh
    cd ..
    bin/nim c koch
    ./koch boot -d:release

    # Fix up path to see nim and binaries installed by nimble 
    echo 'export PATH="$HOME/Nim/bin:$HOME/.nimble/bin:$PATH"' >> ~/.profile
    export PATH="$HOME/Nim/bin:$HOME/.nimble/bin:$PATH"

    # Then install nimble
    ./koch nimble # nim e install_nimble.nims

    # Let it refresh the package list
    nimble refresh

    # Use nimble to install spry
    nimble install spry
  SHELL
end
