# sbcOS


for everybody who has got a USB stick on KW 2019: the SBC-OS has been
installed already. You can boot your server or laptop using this stick
```
user: root
password: plusnet

```

enjoy!


The image is already in ISO, so just run a shell script inside and generate
an ISO image or copy the data to your USB stick and go to sbc/boot and run
bootinst.sh. The script will make your USB stick bootable. Dont forget to install genisoimage!


How to build the system manualy:

The system requires Ubuntu 18 or Debian 9!

Required packages (Debian 9)

```
apt-get install whois dirmngr multistrap reprepro binutils squashfs-tools genisoimage
```

clone the repository, go to SbcOS and run:

```
./build_root.sh
```

dont forget to install: multistrap, reprepo and whois (mkpasswd)

The script will create a rootfs squashfs image.

After go to root directory and run script:

```
./build

```

it will generate two directories in your /tmp:
sbc-data-XXXX
sbc-initrfs-XXXX

and two scripts: that make an ISO image for you 


If you have any question, dont hesistate contact us!

The Project will soon move to an another repository! This is just a start!



