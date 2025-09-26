# Ubuntu 24.04 Hyper-V Vagrant Image

### Intro
I tried several Ubuntu 24.04 images available on Vagrant registry for Hyper-V, but none seemed to work so I made my own. There are no major customizations, mostly just removing unnecessary items. 

### [Vagrant Registry](https://portal.cloud.hashicorp.com/vagrant/discover/mscreations/ubuntu2404)

### How to use this box with Vagrant

#### Step 1

Option 1: Create a Vagrantfile and initiate the box

```
vagrant init mscreations/ubuntu2404 --box-version 2025.09.26
```

Option 2: Open the Vagrantfile and replace the contents with the following

```
Vagrant.configure("2") do |config|
  config.vm.box = "mscreations/ubuntu2404"
  config.vm.box_version = "2025.09.26"
end
```

#### Step 2

Bring up your virtual machine

```
vagrant up
```
