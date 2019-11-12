FROM debian:buster

RUN apt-get update && apt-get install -y \
    libxrender1 \
    libxtst6 \
    && rm -rf /var/lib/apt/lists/*

ADD arduino-1.8.10-linux64.tar.xz /
# FIXME Should I run /arduino-1.8.10/arduino-linux-setup.sh?  That
# sets up the necessary udev rules etc. for several boards.

RUN ln -s /arduino-1.8.10/arduino{,-builder} /usr/local/bin/

# The "staff" group gets /dev/ttyACM*.  I haven't checked /dev/ttyUSB*.
RUN useradd -m -U -G staff --uid 1000 user

USER user
WORKDIR /home/user
CMD ["arduino"]
