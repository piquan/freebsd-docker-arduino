*THIS IS AN EXPERIMENT FOR EXPERIENCED DEVELOPERS.  DO NOT EXPECT SUPPORT.*

# FreeBSD Docker Arduino

The Arduino IDE is a common platform for a lot of new microcontroller projects, especially now that there's ARM support.  For instance, many of the boards designed by [Adafruit](https://www.adafruit.com/) use the Arduino tools.

There are several ways to use the Arduino IDE on FreeBSD, but all of them (including this project) have varying drawbacks.  These are discussed below.

This project is experimental.  I have a number of devices ([Arduinos](https://www.arduino.cc/), [GPU-accelerated SoCs](https://www.nvidia.com/en-us/autonomous-machines/embedded-systems/), [PIC microcontrollers](https://www.microchip.com/design-centers/microcontrollers), [FPGAs](https://www.adafruit.com/product/451), _etc._) that all have their own complicated SDKs.  While nearly any microcontroller vendor supports Linux as the development system, few support FreeBSD.  While a lot of people like Linux for the desktop and FreeBSD for servers, I enjoy using FreeBSD on my desktop.  This project is my first stab at using Docker containers to run a Linux-based SDK on a FreeBSD system.  I chose the Arudino as my first stab because it's quite simple: it can be programmed entirely by a single USB serial port, and the USB programming port is exposed by a separate chip than the main processor (so when the main processor resets, the USB port doesn't).

As an experimental project, this is not well-supported.  If you're not doing the simplest things possibile (like programming an genuine Arduino Uno), don't expect it to work for you.

I apologize in advance, but this isn't a project for anybody who can't dig into problems.  I don't plan on spending a lot of time responding to issues that aren't accompanied by pull requests.  I hope to spend most of my time expanding the basic concepts to related projects, such as handling non-Arduino microcontroller IDEs.  If you're new to FreeBSD, Arduino, or Docker, then this project might not be for you.  If a you have a pretty decent understanding of these technologies, then go ahead and submit clear issues or (much better) PRs.

## Brief background for design components

There are two parts to Docker: there's the frontend `docker` command, and there's the backend Docker Engine.  The `docker` command simply interprets the command line, and passes instructions to a Docker Engine instance.  On Linux, the Docker Engine is typically running on the same machine.

The Docker Engine is implemented using a lot of very Linux-specific technologies.  The design does not require this; for instance, [SmartOS](https://www.joyent.com/smartos) implements the Docker Engine API, but with a completely different SmartOS-specific backend, to get the isolation of VMs with the low overhead of containers.  This has, as far as I know, not been implemented elsewhere.  Hence, almost all Docker stacks run atop Linux.

These technologies Docker Engine uses are so Linux-specific that they aren't available with the [FreeBSD Linuxulator](https://www.freebsd.org/doc/handbook/linuxemu.html), and certainly aren't part of Windows or Mac OS X.

To provide developers with the ability to work on Windows or OS X, Docker created Docker Machine.  This creates a VM running Linux, which runs the Docker Engine.  The `docker` command-line tool is configured to talk to the VM, and the VM runs the containers.  (The Docker Machine mechanism can also be used to provision and run containers using VMs on cloud providers, such as [Amazon AWS](https://docs.docker.com/machine/drivers/aws/) and [Google Compute Engine](https://docs.docker.com/machine/drivers/gce/).)

Docker Machine typically runs the VM using a bootable CD image called [boot2docker](https://github.com/boot2docker/boot2docker).  This is an extremely small ISO (45MB), based on [Tiny Core Linux](https://tinycorelinux.net/), that just runs the Docker Engine.

Most of the boot2docker filesystem isn't persisted; every time the VM is restarted, most of the filesystem is rebuilt from the ISO.  Docker Machine does create two volumes within the VM to persist data across reboots.  The first is `/var/lib/docker`, which holds Docker Engine's data: images, volumes, and so forth.  The other is `/var/lib/boot2docker`, which typically only holds cryptographic keys, and also can be used to hold scripts to execute on machine startup, and other assets.  (During installation, we'll install a kernel module and the script to load it to `/var/lib/boot2docker`.)

Normally, the Docker Machine VM is configured so that the host's `/home` directory is available on the VM as `/hosthome`.  Then, Docker containers can be started to import directories from `/hosthome`, to gain access to the host's `/home`.  Here, we use this to share the user's `~/.arduino15` and `~/Arduino` directories.  Note that this is a two-level share: first, the outer (FreeBSD) host's `/home` is shared within the Docker Machine VM as `/hosthome`.  Second, the Docker Machine VM's `/hosthome/$USER/Arduino` is imported within the Docker container as `/home/user/Arduino`.

By default, Docker Machine doesn't share any devices with the host.  The instructions below will configure the USB device sharing needed to program an Arduino.

Also by default, Docker containers don't share any devices with their host (in our case, that's the Docker Machine VM).  The `arduino` script in this distribution shares the `/dev/ttyACM0` device with the container.

## Alternatives

There is a [FreeBSD port of the Arduino IDE](https://www.freshports.org/devel/arduino18/), but it comes with limitations.  Notably, it doesn't have the managers for external boards and libraries.

The Arduino IDE can run under the FreeBSD Linux emulator, but it doesn't see the FreeBSD serial devices.

`arduino-builder` (included in the Arduino distribution) can also run
under the FreeBSD Linux emulator (if it's
[rebranded](https://www.freebsd.org/doc/handbook/linuxemu-lbc-install.html)),
but I couldn't get the flash step working.

The project you're looking at now is more complex than the other alternatives.  It runs the Docker Engine in a Linux VM (the usual way to run Docker on FreeBSD), and runs the Arduino IDE within a Docker image.  These instructions discuss how to configure the VM appropriately, and a script is supplied to forward the X connections and device files.

## Drawbacks to this solution

Since the Docker container is largely isolated from the host system, it can be difficult to share files.  Docker Machine will share the host's `/home` filesystem to the VM as `/hosthome`, and containers can be configured to import that into the container.  This Arduino project uses this to share the user's `~/.arduino15` and `~/Arduino` between host and guest, but other files (such as `~/Downloads`) are not visible.

If files are being shared, it's important to have the UID inside the guest be the same as the UID of the host.  The current project sets the UID at the time the Docker image is built; hence, the Docker image cannot be shared among multiple users.  There are mechanisms to ease this, but none of them are seamless.

Having VMs access hardware is notoriously finicky, particularly with USB devices.  Most hypervisors (such as VirtualBox) implement "USB passthru" more like "USB relay": the hypervisor tries to access the device using the host OS's typical mechanisms for that device class (such as, for a serial port, by opening `/dev/ttyUSB0`), and then emulate a USB controller with a serial device attached.

Some microcontrollers, such as the Arduino, can be programmed entirely over a normal serial protocol, and have a separate IC that manages the USB connection.  More complicated devices, such as a prototype FPGA, may require more direct access to the USB device.  Also, during the process of programming, a device might disappear and reappear with different identifiers (such as one identifier when it's in recovery mode, another when it's running, _etc._).  Since Docker devices typically need to exist when the container is started (so they can be listed in `--device` flags), this may make it difficult to program complex devices.  Passing through the entire USB controller using bhyve may make that easier.

# Installation instructions

If you have a slow connection, you might want to start downloading the Arduino IDE now.  If you already have Docker working, you can also run `docker pull boot2docker/boot2docker:TAG`, where the tag is the boot2docker version that docker-machine is using.  It's probably not `latest`; it's likely to be the [most recent non-beta non-rc version](https://hub.docker.com/r/boot2docker/boot2docker/tags).  It's a 2GB download, so if you're just reading these sources first, it's good to get started.

## Install and configure Docker Machine

These installation instructions assume you're using the VirtualBox driver for Docker Machine.  This is the default driver, and is well-supported.

While these instructions are based around VirtualBox, the favorite hypervisor in the BSD community is [bhyve](https://wiki.freebsd.org/bhyve).  There is [a Docker Machine driver for bhyve](https://github.com/swills/docker-machine-driver-bhyve), but it's early yet.  I haven't tried using it.  Notably, bhyve doesn't support USB passthrough on a per-device basis; [you need to pass through an entire USB controller](https://baitisj.blogspot.com/2018/01/iohyve-bhyve-usb-controller-passthrough.html).  Many motherboards have multiple USB controllers connected to different ports, so this may be a viable solution for you.  Indeed, passing through the entire USB controller may solve several problems with traditional USB passthrough that might come up when programming microcontrollers.

1. Install the following (from ports or packages):
   * [docker](https://www.freshports.org/sysutils/docker)
   * [docker-machine](https://www.freshports.org/sysutils/docker-machine)
   * [virtualbox-ose](https://www.freshports.org/emulators/virtualbox-ose)
     (You can use virtualbox-ose-nox11 if you like).

2. Follow the instructions in VirtualBox's pkg-message, including the USB steps.  As of this writing, these are:
   * Add `vboxdrv_load="YES"` to `/boot/loader.conf`
   * Add yourself to `vboxusers`, _e.g._, `pw groupmod vboxusers -m piquan`
   * Add yourself to `operator`, _e.g._, `pw groupmod operator -m piquan`
   * Add to `/etc/devfs.rules` (create if it doesn't exist):

         [system=10]
         add path 'usb/*' mode 0660 group operator

   * Enable the new rule by adding `devfs_system_ruleset="system"` to
     `/etc/rc.conf`.
   * Either reboot, or kldload the module, restart devfs, and re-login.

3. Create the VM you'll be using for Docker Machine:

       docker-machine create default
       
   (Some docker-machine commands use "default" as the default VM name if one isn't specified, so that's the name I use.  If you have several VMs, that might be a poor name.)

4. Set the environment variables to tell the `docker` command to connect to your Docker Machine instance:
   
       eval $(docker-machine env)
       
   (That's for sh or bash; I don't know the syntax for csh.)

   You'll need to repeat this step in each new shell window you open.

## Install the CDC-ACM kernel module in the VM

Most post-Uno Arduinos (and other microcontrollers) identify themselves using the CDC device class, which creates `/dev/ttyACM0` nodes in Linux.  Others use the serial device class, which uses a different driver, and creates `/dev/ttyUSB0` nodes.  For more on the difference, see https://rfc1149.net/blog/2013/03/05/what-is-the-difference-between-devttyusbx-and-devttyacmx/

While boot2docker's Linux kernel has the `usbserial` module installed (which creates `/dev/ttyUSB0`), it does not have `cdc_acm` (which creates `/dev/ttyACM0`).

Since the Arduino IDE will be running with the boot2docker kernel, it's important to install the `cdc_acm` module.

1. Check the kernel version running in your VM:

       docker-machine ssh default uname -r

2. Look up that kernel version in the [list of boot2docker releases](https://github.com/boot2docker/boot2docker/releases) to identify the boot2docker release you're using.

3. In the checked-out version of this repo you're using, edit `boot2docker-acm/Dockerfile` to indicate the appropriate boot2docker release.
   
3. Make sure you've got at least 3 GB free in your docker-machine VM (the default disk size is 20 GB), and enough space on your host machine for the VM disk to expand by 3 GB.

4. If you haven't yet, or if you've logged out and back in, rerun `eval $(docker-machine env)`.  The install step below will use Docker to build the Linux cdc_acm kernel module.

5. It might be a good idea to pre-pull the base boot2docker build image.  That lets you rerun the install script a few times in case of problems, without a big download each time.
   
       docker pull boot2docker/boot2docker:TAG
   
   (where the `TAG` is the same as you put in the Dockerfile earlier).

   If you do, make yourself a note to delete it with `docker rmi` once you've got everything working.

5. From the `boot2docker-acm` directory, run `./install.sh`.  This will perform several steps:
     1. Download a 2GB Docker image, the image that was used to compile the boot2docker release.
     2. Compile the cdc_acm kernel module.
     3. Copy the cdc_acm kernel module to your Docker Machine VM, arrange for it to be loaded at boot, and load it.

## Modify the VM to enable USB support

1. Shut down the VM so you can modify it (obviously, while you don't have any important containers running).
   
       docker-machine stop

2. Modify the VM to enable USB support.

       VBoxManage modifyvm default --usb on
       
3. Add new USB filters for the devices you want to use with the Arduino IDE.  This is easiest with the VirtualBox GUI, but you can also do the same with the CLI.  For instance, to add all products with the Arduino USB VID (2341), use:
   
       VBoxManage usbfilter add 0 --target default --name Arduino --vendorid 2341
   
   Depending on your personal preference, you may want to also add the FTDI VID (0403).  On the other hand, you may prefer to add individual devices with their particular serial numbers.
   
4. Start the VM again.

       docker-machine start

## Build the Arduino Docker image

1. Download the [latest release of the Arduino IDE](https://www.arduino.cc/en/Main/Software).  You'll want the Linux 64-bit version (not ARM).
   
2. Save it in the same directory as this README.

3. Edit the Dockerfile in this directory to reflect the Arduino version (both in the filename in the `ADD` line, and the directory name in the `RUN ln -s` line).
   
4. If your FreeBSD user id is not 1000, edit the `useradd` line in the Dockerfile accordingly.  You may also want to change the username to match yours, so that invoking `arduino /home/piquan/Arduino/Blink/Blink.ino` will find the right file inside the container.
   
5. Build the image.  Use a different tag if you like.

       docker build --tag=arduino .

   If you are using a different image tag than `arduino`, then edit the `image` line in the `arduino` script (in the same directory as this README) accordingly.

## Install the script (optional)

The `arduino` script can stand alone.  You can copy it somewhere convenient (such as `~/.local/bin`, if that's in your `$PATH`), and delete the rest of this distribution.

I haven't tested this, but you should be able to install icons and file associations.  To do this, extract from the Arduino distribution the following:
* `lib/desktop.template`
* `lib/icons/`
* `lib/arduino-arduinoide.xml`
* `lib/arduino.png`
* `lib/appdata.xml`
* `install.sh`

`lib` should be in the same directory as the `arduino` script (the one that was in the same directory as this README, before you moved it elsewhere).  Then, run the `install.sh` script.  This will set up the appropriate icons and associations.

# Using the image

You can simply run the `arduino` script to launch the Arduino IDE.

The container will have access to your FreeBSD box's `~/Arduino` directory (the default location for source files and libraries), and also your `~/.arduino15` directory (which holds your preferences and third-party board packages for all Arduino versions after 1.5).

Similar to `docker run`, you can give a custom command to the `arduino` script.  For instance, if you want [to use `arduino-builder`](https://github.com/arduino/arduino-builder), you can run the `arduino` script as `arduino arduino-builder -compile ...`.  This will not try to connect to your X display, but will try to connect to the Arduino device.

# When to re-install

If you recreate (delete then create) your docker-machine VM, you'll need to repeat all of these steps (except installing docker-machine).

If you upgrade your docker-machine VM (using `docker-machine upgrade`), you'll need to rebuild and reinstall the CDC-ACM module.

# Bugs

The script won't work if `$DISPLAY` is not of the form `:0` where `0` can be any number.  In particular, while it will work with `:1` or `:10` (as you may see with multiple users under a login manager, or with VNC), it won't work with `localhost:10` (which you'll see with ssh) or with `other-host:0`.  This is not a fundamental limitation; I just haven't bothered to fix it yet.

Currently, this script assumes that your Arduino is on `/dev/ttyACM0` (inside the Docker Machine VM).  This can be fixed without difficulty.

Your Arduino must be plugged in before you start the Arduino IDE, and must keep the same device node (_e.g._, `/dev/ttyACM0`) for the entire session.  This is not easily fixed.

If your device isn't programmed entirely over `/dev/ttyACM0`, this script won't work.  This works fine for a typical device like an Arduino Uno.  It hasn't yet been tested in more unusual circumstances, such as an [Adafruit Feather M4](https://www.adafruit.com/product/3857) or other SAMD-based devices using the UF2 bootloader.

Speaking of Adafruit's boards: if you're just using [CircuitPython](https://learn.adafruit.com/welcome-to-circuitpython) or something similar, you don't need the Arduino IDE: you can just copy your programs to the virtual disk.  If you're trying to reflash CircuitPython itself, or anything else you have to do in bootloader mode (mostly, uploading a `.UF2` file), FreeBSD might not recognize the disk.  The upstream UF2 bootloader recently accepted [a patch for this](https://github.com/microsoft/uf2-samdx1/pull/81), but it may take some time before it makes its way to the downstream repos.  Additionally, while the bootloader will load patches to the bootloader itself, you end up with a chicken-and-egg problem.  Because of the design of VirtualBox's USB sharing, anything that FreeBSD can't recognize will also be unrecognizable to any VMs.  (bhyve doesn't have that issue, but requires you to share an entire USB controller, as described above.)  In that case, you may want to load the post-patch bootloader using a Linux system such as a Raspberry Pi.  Once the new bootloader is installed, you can use your FreeBSD box for the remainder of your development.

# Licensing

This project is copyright 2019 by Joel Ray Holveck.  It is licensed under the [MIT license](https://opensource.org/licenses/MIT); see the `LICENSE` file for details.  If this causes difficulty with an open-source use case, feel free to contact me.
