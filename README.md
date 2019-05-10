# sbcOS

SBC-OS is an opensource answer on all marketing noice that sometimes makes
our live complicate. 

SBC-OS is a drop-replace solution for any existing commercial SBC.

SBC-OS is a STACK that includes open-sources components that will give you
next features:

 
1. NAT fix including NAT ping
2. SIP analyze and normalizing (SIP/VoIP Firewall) 
3. PIKE - limits (selfilter)
4. Topology hiding
5. Header manipulation
6. SIP TLS -> SIP
7. RTP Relay (kernel space) including QOS. Amazing perfomance. Around 10K CC on
1U server like DELL R360.
8. RTP transcoding, RTP Recording  (user space)
9. SRTP->RTP and vice-versa
10. WebRTC and IMS support including diameter.
11. IP Trunking / Registration Trunking
12. Monitoring and statistics including RTP/RTCP MOS/QOS (Homer/Hepic)
13. Internal statistics / CPU/Memory/Network usage
14. Full IPv4 IPv6 support. 


NB! For the (Lawful Interception) LI, please contact info@qxip.net


for everybody who has got a USB stick on KW 2019: the SBC-OS has been
installed already. You can boot your server or laptop using this stick
```
user: root
password: plusnet

```

enjoy!


In the repository you will find an ISO directory that contains the files to generate an ISO image, 
so just go there and run a shell script inside and to generate an ISO image or copy the data 
to your USB stick and go to sbc/boot and run bootinst.sh. The script will make your USB stick bootable. 
Dont forget to install genisoimage!


How to build the system manualy:

The system requires Ubuntu 18 or Debian 9!

Required packages (Debian 9 / Ubuntu 18)

```
apt-get install whois dirmngr multistrap reprepro binutils squashfs-tools genisoimage make linux-headers-$(uname -r)
```

clone the repository, go to SbcOS and run:

```
./build_root.sh
```

dont forget to install: multistrap, reprepo, whois (mkpasswd), genisoimage

The script will create a rootfs squashfs image.

After go to root directory and run script:

```
./build

```

it will generate two directories in your /tmp:
sbc-data-XXXX
sbc-initrfs-XXXX

and two scripts: that make an ISO image for you 


Important! Please be sure that your /vmlinuz is pointing to the same version of kernel
that runs now!

```
root@linux:sbcOS# uname -r
4.9.0-8-amd64
root@inux:sbcOS# ls -l /vmlinuz
lrwxrwxrwx 1 root root 26 May  5 23:20 /vmlinuz -> boot/vmlinuz-4.9.0-8-amd64

```

If you have any question, dont hesistate contact us!

The Project will soon move to an another repository! This is just a start!

Thanks Tomas M. <http://www.linux-live.org> for initramfs scripts!

