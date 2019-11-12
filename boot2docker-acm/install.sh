#! /bin/sh

set -ex

# The ID of the image in which we'll compile the cdc_acm driver.
iidfile=$(mktemp -t boot2docker-acm-iid)
# Where we'll store the Linux module locally.
kofile=$(mktemp -t boot2docker-acm-cdc-acm.ko)
trap "rm -f $iidfile $kofile" EXIT

# Build the image.  The base image is about 2.3 GB, so this may take a
# long time to download!  After that, actually compiling the image is
# fast.
docker build --iidfile $iidfile .
iid=$(cat $iidfile)
trap "docker rmi $iid ; rm -f $iidfile $kofile" EXIT

# Create a container from that image, so we can extract the Linux
# module.  We don't actually have to start it; the module was compiled
# when the image was created.
container=$(docker create $iid)
trap "docker rm $container ; sleep 0.5 ; docker rmi $iid ; rm -f $iidfile $kofile" EXIT

# Copy the module from that container to the FreeBSD host's /tmp, and
# then into the docker-machine VM.  Most of the docker-machine system
# is non-persistent, but the `/var/lib/boot2docker` persists across
# the docker-machine reboots.
docker cp $container:/usr/src/linux/drivers/usb/class/cdc-acm.ko "$kofile"
docker-machine scp $kofile default:/var/lib/boot2docker/cdc-acm.ko

# Make sure the module can be loaded.
docker-machine ssh default sudo insmod /var/lib/boot2docker/cdc-acm.ko

# Copy and set up the commands to load the kernel module on reboots.
# bootlocal.sh is run every time boot2docker boots.
docker-machine scp bootlocal.sh default:/var/lib/boot2docker/
docker-machine ssh default sudo chown 0:0 /var/lib/boot2docker/cdc-acm.ko /var/lib/boot2docker/bootlocal.sh

