# <img src="https://user-images.githubusercontent.com/1423657/57624925-31f08780-7593-11e9-9e1e-2f876efa23ac.png" width=300 alt="sbcOS">

**SBC-OS** is an open-source drop-in replacement for many existing commercial Session Border Controllers designed for performance and resource optimization

### Features
 
1. NAT fix including NAT ping
2. SIP analyze and normalizing (SIP/VoIP Firewall) 
3. PIKE - limits (selfilter)
4. Topology hiding
5. Header manipulation
6. SIP TLS -> SIP
7. RTP Relay (kernel space) including QOS. Amazing performance. Around 10K CC on
1U server like DELL R360.
8. RTP transcoding, RTP Recording  (user space)
9. SRTP->RTP and vice-versa
10. WebRTC and IMS support including diameter.
11. IP Trunking / Registration Trunking
12. Monitoring and statistics including RTP/RTCP MOS/QOS (Homer/Hepic)
13. Internal statistics / CPU/Memory/Network usage
14. Full IPv4 IPv6 support. 

### Optional Features
NB! For the (Lawful Interception) LI, please contact info@qxip.net


# sbcOS PXE/Netboot Documentation

## 📅 Overview

This document describes the PXE network boot architecture of **sbcOS v2.0**. The system is based on Alpine Linux and is booted via iPXE. Dynamic configuration is handled by a server-side PHP script (`boot.php`) that provides tailored boot parameters and overlay files for each host.

---

## 🚀 Boot Architecture Summary

1. PXE/iPXE boot → iPXE script is loaded.
2. iPXE fetches `boot.php` with MAC/hostname as parameters.
3. `boot.php` dynamically generates kernel, initramfs, and boot options.
4. Alpine Linux is started with custom packages and configuration (`apkovl`).

---

## 🌐 PXE and TFTP Setup

A typical PXE environment consists of:

* **DHCP server**: provides network boot instructions.
* **TFTP server**: serves iPXE binaries and configuration.
* **Web server (HTTP)**: delivers `boot.php`, overlays, and packages.

Example DHCP configuration:

```dhcpd
filename "ipxe.efi";               # or pxelinux.0
next-server 10.255.3.2;            # TFTP server IP
```

Place the iPXE binary and `undionly.kpxe` or `ipxe.efi` in `/srv/tftp/`.

---

## 🌐 iPXE Example

```ipxe
#!ipxe

echo +----- NETBOOT ----------------------------------------------
echo |hostname: ${hostname}, next-server: ${next-server}
echo |mac.....: ${net0/mac} /
echo +------------------------------------------------------------

goto booturl

:booturl
chain http://10.255.3.2/boot.php?mac=${net0/mac}&hostname=${hostname}
```

---

## 🔧 Example Output from `boot.php`

```ipxe
kernel http://10.255.3.2/alpine/v3.11.6/releases/x86_64/netboot-3.11.6/vmlinuz-lts \
  modules=loop,squashfs quiet nomodeset alpine_repo=http://10.255.3.2/alpine/v3.11.6/main \
  pkgs=bonding,coreutils,... ssh_key=yes \
  modloop=http://10.255.3.2/alpine/.../modloop-lts \
  rootflags=size=6G \
  modules=loop,squshfs,igb,e1000e ip=dhcp::::dproxy3.fra:eth4: \
  console=ttyS1,115200n8r console=tty0 \
  apkovl=http://10.255.3.2/boot-config/a0:36:9f:e7:6a:e2/config.tar.gz
initrd http://10.255.3.2/alpine/.../initramfs-lts
boot
```

---

## 📚 Parameter Description

| Parameter     | Description                                      |
| ------------- | ------------------------------------------------ |
| `mac`         | MAC address of the client                        |
| `hostname`    | Hostname (provided by DHCP or iPXE)              |
| `apkovl`      | Alpine overlay archive with custom `/etc` config |
| `pkgs`        | Alpine packages to install at boot time          |
| `modloop`     | Kernel modules image                             |
| `alpine_repo` | Alpine package repository                        |
| `console`     | Active consoles (e.g., serial, tty0)             |
| `ssh_key`     | Enables SSH access on first boot                 |

---

## 🌐 Server-Side Logic of `boot.php`

The PHP script performs the following:

1. Retrieves MAC/hostname from GET parameters.
2. Logs requests via `syslog()`.
3. Assembles appropriate boot settings for the node.
4. Outputs iPXE commands with `echo`.

---

## 🛡 Security & Scaling

* Protect `boot.php` with IP filtering or tokens.
* MAC-based routing allows per-host configuration.
* Consider HTTPS and web server authentication.
* Supports centralized monitoring/logging (e.g., rsyslog, telegraf).

---

## 🔁 Future Ideas

* Integrate with a database for host inventory.
* Web UI for editing node configurations.
* Management API for automation.
* Live debug mode for boot diagnostics.

---

## ✅ Conclusion

`sbcOS` uses a flexible combination of PXE + iPXE + dynamic PHP to deploy and provision SBC nodes at scale. The architecture supports rapid deployment, centralized control, and robust configuration management.

More details: [https://github.com/voiceboys/sbcOS/tree/version\_2.0](https://github.com/voiceboys/sbcOS/tree/version_2.0)


