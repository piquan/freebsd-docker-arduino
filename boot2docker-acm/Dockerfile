# The version number to use here can usually be found by looking at
# the kernel version running inside docker-machine, and comparing it
# to the releases in https://github.com/boot2docker/boot2docker/releases .

FROM boot2docker/boot2docker:19.03.4
RUN make -C /usr/src/linux modules CONFIG_USB_ACM=m SUBDIRS=drivers/usb/class
CMD [ -t 1 ] && exec bash || exec cat /usr/src/linux/drivers/usb/class/cdc-acm.ko
