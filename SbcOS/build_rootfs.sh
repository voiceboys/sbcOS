#!/bin/bash
#
# Author Alexandr Dubovikov <alexandr.dubovikov@gmail.com>


. ../config

TIMEZONE="Etc/CET"
HOSTNAME="plusbc01-live"
ROOTHASH="$(echo ${ROOTPASSWORD} | mkpasswd -5 -s)"

echo "-= build stripped base rootfs for future squashfs"

BASEDIR="${PWD}/build"
PACKAGES="${PWD}/packages"
BINDIR="$BASEDIR/bin"
CFGDIR="${PWD}/configs"
DEBDIR="$BASEDIR/deb"
LOGDIR="$BASEDIR/log"
IMGDIR="$BASEDIR/img"
RFSDIR="$BASEDIR/rfs"
INITRAMFS="${PWD}/../initramfs"
DEBRFSDIR="$BASEDIR/deb-rfs"
BOOTSTRAPDIR="$BASEDIR/deb-rfs/bootstrap"
HOOKSDIR="$BINDIR/hooks"
TMPDIR="$BASEDIR/tmp"
ROOTFS="${RFSDIR}/rootfs"

# copy file to initramfs tree, including
# all library dependencies (as shown by ldd)
# $1 = file to copy (full path)
copy_including_deps()
{
   # if source doesn't exist or target exists, do nothing
   if [ ! -e "$1" -o -e "${RFSDIR}/rootfs"/"$1" ]; then
      return
   fi

   cp -R --parents "$1" "${RFSDIR}/rootfs"
   if [ -L "$1" ]; then
      DIR="$(dirname "$1")"
      LNK="$(readlink "$1")"
      copy_including_deps "$(cd "$DIR"; realpath -s "$LNK")"
   fi

   ldd "$1" 2>/dev/null | sed -r "s/.*=>|[(].*//g" | sed -r "s/^\\s+|\\s+\$//" \
     | while read LIB; do
        copy_including_deps "$LIB"
     done

   for MOD in $(find "$1" -type f | grep .ko); do
      for DEP in $(cat /$LMK/modules.dep | fgrep /$(basename $MOD):); do
         copy_including_deps "/$LMK/$DEP"
      done
   done

   shift
   if [ "$1" != "" ]; then
       copy_including_deps "$@"
   fi
}

check_exit_code() {
  if [ $? -ne 0 ]; then
    (>&2 caller)
    echo " ! error. exiting now."
    exit 1
  fi
}

function extract_deb {
  echo " | extact $1 to $2"
  DATAFILE=$(ar -t "$1" | grep data)
  ar -x "$1" $DATAFILE && tar -C $2 -xaf $DATAFILE && rm $DATAFILE
} 

function depcheck() {
  DEPVARIANT="$1"
  echo " | scan required packages for bin and lib files for variant $DEPVARIANT"
  for i in $(cat $CFGDIR/$DEPVARIANT/install.req); do
    DEBFILE=$(find $DEBDIR -type f -name "${i}_*.deb")
    if [ -n "$DEBFILE" ]; then
       echo " | package: $i - location: $DEBFILE"
    else
       echo " | package: $i - location: NOT FOUND!"
    fi
    echo $DEBFILE >> $TMPDIR/main.install.tmp
    dpkg -c $DEBFILE | egrep -v "^lrwxrwxrwx" | awk '{print $6}' | egrep "(.+lib.+lib.+\.so.*$|bin/)" | sort -u | sed -e "s#^\./#/#g" | LC_ALL=C xargs chroot $RFSDIR/bootstrap/ /usr/bin/ldd {} 2>/dev/null | grep -v ":" | grep -v "dynamic executable" | grep -v "linux-vdso" | awk '{print $1}' | sort -u >> $TMPDIR/main.deps.tmp
  done

  echo " | scan found dependencies for further nested dependencies"
  for i in $(cat $TMPDIR/main.deps.tmp); do
    find $RFSDIR/bootstrap -type f -name "$i" 2> /dev/null | grep -v openjdk-amd64 | sed -e "s#$RFSDIR/bootstrap##g" | LC_ALL=C xargs chroot $RFSDIR/bootstrap/ /usr/bin/ldd 2> /dev/null | grep -v ":" | grep -v "dynamic executable" | grep -v "linux-vdso" | awk '{print $1}' | sort -u >> $TMPDIR/additional.deps.tmp
  done
  sort -u $TMPDIR/additional.deps.tmp > $TMPDIR/additional.deps
  while [ -s "$TMPDIR/additional.deps" ]; do
    echo -n > $TMPDIR/additional.deps.tmp
    for i in $(cat $TMPDIR/additional.deps); do
      grep "$i" $TMPDIR/main.deps.tmp $LOGDIR/install.lib.base > /dev/null 2>&1
      if [ $? -ne 0 ]; then
        find $RFSDIR/bootstrap -type f -name "$i" 2> /dev/null | grep -v openjdk-amd64 | sed -e "s#$RFSDIR/bootstrap##g" | LC_ALL=C xargs chroot $RFSDIR/bootstrap/ /usr/bin/ldd 2> /dev/null | grep -v ":" | grep -v "dynamic executable" | grep -v "linux-vdso" | awk '{print $1}' | sort -u >> $TMPDIR/additional.deps.tmp
        echo $i >> $TMPDIR/main.deps.tmp
      fi
    done
    sort -u $TMPDIR/additional.deps.tmp > $TMPDIR/additional.deps
  done
  sort -u $TMPDIR/main.deps.tmp > $LOGDIR/install.lib.$DEPVARIANT

  echo " | resolve depencencies to debian packages"
  for i in $(cat $LOGDIR/install.lib.$DEPVARIANT); do
    dpkg --admindir=$RFSDIR/bootstrap/var/lib/dpkg -S "$i" | sed -e 's/:.*/_\*\.deb/g' | sort -u | xargs -d '\n' -n 1 find $DEBDIR -type f -name >> $TMPDIR/main.install.tmp
  done
  sort -u $TMPDIR/main.install.tmp > $LOGDIR/install.deb.$DEPVARIANT

  rm $TMPDIR/main.install.tmp $TMPDIR/main.deps.tmp $TMPDIR/additional.deps*
}

function mkdir_if_missing() {
    if [ ! -d "$1" ]; then
        echo " | create directory \"$1\""
        mkdir -p "$1"
        check_exit_code
    fi
}


function init_rootfs() {

	rm -rf $BASEDIR
	mkdir_if_missing $IMGDIR
	mkdir_if_missing $TMPDIR
	mkdir_if_missing $LOGDIR
	mkdir_if_missing $DEBDIR/import
	#mkdir_if_missing $RFSDIR/initramfs
	mkdir_if_missing $RFSDIR/squashfs
	mkdir_if_missing $RFSDIR/bootstrap
	mkdir_if_missing $RFSDIR/rootfs
	mkdir_if_missing $RFSDIR/src
}



function prebuild() {
	echo "use parameter [-debian] for update builder" 
	echo "-= build sbc-repository repository" | tee $LOGDIR/${SCRIPTNAME}_$BUILDDATE.echo

	rm -rf $DEBDIR/pool
	rm -rf $DEBDIR/*
	rm -rf $DEBDIR/dist/sbc-repository/*

	if [ ! -d "${BOOTSTRAPDIR}/etc/apt" ]; then
	        mkdir -p "${BOOTSTRAPDIR}/etc/apt"
	        check_exit_code	        
	fi
	
	cp /etc/apt/trusted.gpg "${BOOTSTRAPDIR}/etc/apt"
	check_exit_code

	cp $CFGDIR/multistrap-bootstrap-debian.conf $CFGDIR/multistrap-bootstrap-current.conf
	sed -i -e "s|##DIR##|${BOOTSTRAPDIR}|g" $CFGDIR/multistrap-bootstrap-current.conf
	sed -i -e "s|##HOOKS##|${HOOKSDIR}|g" $CFGDIR/multistrap-bootstrap-current.conf

	echo " | install current debian stable to setup package repository"
	multistrap -f $CFGDIR/multistrap-bootstrap-current.conf
	check_exit_code

	echo " | create sbc-repository repository based on current debain stable - deleteunreferenced"
	reprepro --basedir $DEBDIR --confdir $CFGDIR includedeb sbc-repository $DEBRFSDIR/bootstrap/var/cache/apt/archives/*.deb
	check_exit_code

	echo " | import kamailio packages into sbc-repository repository"
	reprepro --basedir $DEBDIR --confdir $CFGDIR includedeb sbc-repository $PACKAGES/kamailio/*.deb
	check_exit_code

	echo " | import rtpengine packages into sbc-repository repository"
	reprepro --basedir $DEBDIR --confdir $CFGDIR includedeb sbc-repository $PACKAGES/rtpengine/*.deb
	check_exit_code
	
	echo " | import telegraf packages into sbc-repository repository"
	reprepro --basedir $DEBDIR --confdir $CFGDIR includedeb sbc-repository $PACKAGES/telegraf/*.deb
	check_exit_code
  
	#echo " | import libuv packages into sbc-repository repository"
	#reprepro --basedir $DEBDIR --confdir $CFGDIR includedeb sbc-repository $PACKAGES/liagent/packages/*.deb
	#check_exit_code
	echo " ! done."
}

function buildrootfs() {

	rm -rf $RFSDIR/rootfs
	mkdir_if_missing $RFSDIR/rootfs
	rm $LOGDIR/install.lib.* $LOGDIR/install.deb.*
	touch $LOGDIR/install.lib.base
	depcheck base
	depcheck sbc
	echo " | run depcheck"
	touch "$LOGDIR/install.req.checked"

	echo " | extract debian packages to future base rootfs"
	cd $TMPDIR
	for i in $(cat $LOGDIR/install.deb.base); do
	  extract_deb $i $RFSDIR/rootfs
	done

	echo " | extract sbc packages to future rootfs"
	cd $TMPDIR
	for i in $(cat $LOGDIR/install.deb.sbc); do
	  extract_deb $i $RFSDIR/rootfs
	done

	echo " | cleanup directories from future base rootfs"
	cd $RFSDIR/rootfs/
	check_exit_code
	for i in $(cat $CFGDIR/base/cleanup); do
	  echo $i | egrep "^\/.*" > /dev/null 2>&1
	  if [ $? -ne 0 ]; then
	    rm -rf $i
	  fi
	done
	
	echo " | create default directories for new base rootfs"
	install -m 755 $CFGDIR/init-system $RFSDIR/rootfs/init
	check_exit_code
	mkdir -p $RFSDIR/rootfs/bin
	check_exit_code
	mkdir -p $RFSDIR/rootfs/dev/pts
	check_exit_code
	mkdir -p $RFSDIR/rootfs/etc/network
	check_exit_code
	mkdir -p $RFSDIR/rootfs/etc/default
	check_exit_code
	mkdir -p $RFSDIR/rootfs/etc/network/if-up.d
	check_exit_code
	mkdir -p $RFSDIR/rootfs/etc/scripts
	check_exit_code
	mkdir -p $RFSDIR/rootfs/etc/init.d
	check_exit_code
	mkdir -p $RFSDIR/rootfs/etc/rc.d
	check_exit_code
	mkdir -p $RFSDIR/rootfs/etc/master
	check_exit_code
	mkdir -p $RFSDIR/rootfs/etc/redis
	check_exit_code
	ln -s /run/initramfs/lib/modules $RFSDIR/rootfs/lib/
	check_exit_code
	mkdir -p $RFSDIR/rootfs/lib64
	check_exit_code
	mkdir -p $RFSDIR/rootfs/mnt
	check_exit_code
	mkdir -p $RFSDIR/rootfs/proc
	check_exit_code
	mkdir -p $RFSDIR/rootfs/sbin
	check_exit_code
	mkdir -p $RFSDIR/rootfs/sys
	check_exit_code
	mkdir -p $RFSDIR/rootfs/run/network
	check_exit_code
	mkdir -p $RFSDIR/rootfs/tmp
	check_exit_code
	mkdir -p $RFSDIR/rootfs/usr/bin
	check_exit_code
	mkdir -p $RFSDIR/rootfs/usr/sbin
	check_exit_code
	mkdir -p $RFSDIR/rootfs/lib/lsb
	check_exit_code
	mkdir -p $RFSDIR/rootfs/lib/lsb/init-functions.d
	check_exit_code
	mkdir -p $RFSDIR/rootfs/usr/share
	check_exit_code
	mkdir -p $RFSDIR/rootfs/var/run
	check_exit_code
	mkdir -p $RFSDIR/rootfs/var/spool/rtpengine
	check_exit_code
	mkdir -p $RFSDIR/rootfs/var/spool/backup
	check_exit_code
	mkdir -p $RFSDIR/rootfs/var/lib/voip
	check_exit_code
	mkdir -p $RFSDIR/rootfs/var/lib/redis
	check_exit_code
	mknod $RFSDIR/rootfs/dev/console c 5 1
	mknod $RFSDIR/rootfs/dev/null c 1 3
	mkdir -p -m0755 $RFSDIR/rootfs/var/run/sshd
	mkdir -p -m0755 $RFSDIR/rootfs/run/sshd
	check_exit_code
	mkdir -p $RFSDIR/rootfs/var/echo
	check_exit_code
	touch $RFSDIR/rootfs/var/echo/lastecho
	check_exit_code
	touch $RFSDIR/rootfs/var/echo/wtmp
	check_exit_code
	touch $RFSDIR/rootfs/var/run/utmp
	check_exit_code

	echo " | create dhclient.conf in base rootfs"
	install -m 644 $CFGDIR/dhclient.conf $RFSDIR/rootfs/etc/dhcp/dhclient.conf
	check_exit_code
	touch $RFSDIR/rootfs/var/lib/dhcp/dhclient.leases
	check_exit_code

	echo " | create ntp.conf in base rootfs"
	install -m 644 $CFGDIR/ntp.conf $RFSDIR/rootfs/etc/ntp.conf
	check_exit_code

	echo " | copy password and groupsrootfs"
	mkdir -p $RFSDIR/bootstrap/etc/
	check_exit_code
	cp -Rp $CFGDIR/password/* $RFSDIR/bootstrap/etc/
	check_exit_code

	echo " | create default adjtime file in base rootfs"
	install -m 644 $CFGDIR/adjtime $RFSDIR/rootfs/etc/adjtime
	check_exit_code

	echo " | set time zone to $TIMEZONE"
	echo $TIMEZONE > $RFSDIR/rootfs/etc/timezone
	check_exit_code
	
	echo " | hostname $HOSTNAME"
	echo $HOSTNAME > $RFSDIR/rootfs/etc/hostname
	check_exit_code
	
	echo " | change root password in base rootfs"
	cp $RFSDIR/bootstrap/etc/passwd $RFSDIR/bootstrap/etc/shadow $RFSDIR/bootstrap/etc/group $RFSDIR/bootstrap/etc/gshadow $RFSDIR/rootfs/etc/
	check_exit_code
	sed -i -e "s,^root:[^:]*:,root:$ROOTHASH:," $RFSDIR/rootfs/etc/shadow
	check_exit_code
	sed -i -e "s#\/root:\/bin\/bash#\/root:\/bin\/ash#" $RFSDIR/rootfs/etc/passwd
	check_exit_code

	echo " | install hosts files to future base rootfs"
	install -m 644 $RFSDIR/bootstrap/etc/hosts $RFSDIR/rootfs/etc/hosts
	check_exit_code

	echo " | remove debian script dependencies in dhclient script"
	sed -i -e 's#chown --reference=/etc/resolv.conf#chown root#g' $RFSDIR/rootfs/sbin/dhclient-script
	check_exit_code
	sed -i -e 's#chmod --reference=/etc/resolv.conf#chmod 644#g' $RFSDIR/rootfs/sbin/dhclient-script
	check_exit_code
	sed -i -e 's#run-parts --list#ls -1#g' $RFSDIR/rootfs/sbin/dhclient-script
	check_exit_code

	echo " | install ssh system keys to future base rootfs"
	install -m 644 -D $CFGDIR/inittab $RFSDIR/rootfs/etc/inittab
	check_exit_code
	install -m 644 -D $CFGDIR/redis/redis.conf $RFSDIR/rootfs/etc/redis/redis.conf
	check_exit_code
	install -m 644 -D $CFGDIR/dhcpinterface $RFSDIR/rootfs/etc/dhcpinterface
	check_exit_code	

	cp -Rp $CFGDIR/utility/px $RFSDIR/rootfs/usr/bin/px
	check_exit_code
	
	cp -Rp $CFGDIR/utility/ldd $RFSDIR/rootfs/usr/bin/ldd
	check_exit_code

	echo " | install issue  base rootfs"
	install -m 644 -D $CFGDIR/issue $RFSDIR/rootfs/etc/issue
	check_exit_code

	echo " | install monit system to base rootfs"
	install -m 600 -D $CFGDIR/monitrc $RFSDIR/rootfs/etc/monit/
	check_exit_code
	
	echo " | install rsyslog system to base rootfs"
	install -m 600 -D $CFGDIR/rsyslog.conf $RFSDIR/rootfs/etc/
	check_exit_code

	echo " | install liagent system to base rootfs"
	mkdir -p $RFSDIR/rootfs/usr/liagent
	cp -Rp $CFGDIR/liagent/* $RFSDIR/rootfs/usr/liagent
	check_exit_code

	echo " | install rcS scripts to rootfs"
	install -m 755 -D $CFGDIR/init.d/* $RFSDIR/rootfs/etc/init.d/
	check_exit_code

	cp -Rp $CFGDIR/rc.d/* $RFSDIR/rootfs/etc/rc.d/
	check_exit_code

	echo " | install modprobe to rootfs"
	install -m 755 -D $CFGDIR/sbc/modprobe.conf $RFSDIR/rootfs/etc/modprobe.conf
	check_exit_code

	echo " | install interfaces directory to rootfs"
	cp -Rp $CFGDIR/interfaces/* $RFSDIR/rootfs/etc/network
	check_exit_code

	echo " | setup file permissions for ssh-agent"
	SSH_GROUP=$(grep ssh $RFSDIR/rootfs/etc/group | sed -e 's/.*ssh:x://g' | sed -e 's/:.*//g')
	if [ -z "$SSH_GROUP" ]; then
	  /bin/false
	  check_exit_code
	fi

	chgrp $SSH_GROUP $RFSDIR/rootfs/usr/bin/ssh-agent
	check_exit_code
	chmod 2755 $RFSDIR/rootfs/usr/bin/ssh-agent
	check_exit_code
	
	echo " | install ssh system keys to future base rootfs"
        install -m 600 -D $CFGDIR/ssh/ssh_host_ecdsa_key $RFSDIR/rootfs/etc/ssh/ssh_host_ecdsa_key
        check_exit_code
        install -m 644 -D $CFGDIR/ssh/ssh_host_ecdsa_key.pub $RFSDIR/rootfs/etc/ssh/ssh_host_ecdsa_key.pub
        check_exit_code
        install -m 600 -D $CFGDIR/ssh/ssh_host_rsa_key $RFSDIR/rootfs/etc/ssh/ssh_host_rsa_key
        check_exit_code
        install -m 644 -D $CFGDIR/ssh/ssh_host_rsa_key.pub $RFSDIR/rootfs/etc/ssh/ssh_host_rsa_key.pub
        check_exit_code
        install -m 600 -D $CFGDIR/ssh/ssh_host_ed25519_key $RFSDIR/rootfs/etc/ssh/ssh_host_ed25519_key
        check_exit_code
        install -m 644 -D $CFGDIR/ssh/ssh_host_ed25519_key.pub $RFSDIR/rootfs/etc/ssh/ssh_host_ed25519_key.pub
        check_exit_code
        install -m 644 -D $CFGDIR/ssh/ssh_config $RFSDIR/rootfs/etc/ssh/ssh_config
        check_exit_code
        install -m 644 -D $CFGDIR/ssh/sshd_config $RFSDIR/rootfs/etc/ssh/sshd_config
        check_exit_code
	
	echo " | install root ssh files to future base rootfs"
	install -m 700 -d $RFSDIR/rootfs/root/.ssh
	check_exit_code
		
	#Please make an own one
	install -m 600 $CFGDIR/root/authorized_keys $RFSDIR/rootfs/root/.ssh/authorized_keys
	check_exit_code
	install -m 600 $CFGDIR/root/id_rsa $RFSDIR/rootfs/root/.ssh/id_rsa
	check_exit_code
	install -m 644 $CFGDIR/root/id_rsa.pub $RFSDIR/rootfs/root/.ssh/id_rsa.pub
	check_exit_code

	echo " | install busybox to new base rootfs"
	install -m 755 ${INITRAMFS}/static/busybox $RFSDIR/rootfs/bin/
	check_exit_code
	chroot $RFSDIR/rootfs/ /bin/busybox --install -s
	check_exit_code

	echo " | install ssl certificates to new base rootfs"
	cp -a $RFSDIR/bootstrap/etc/ssl/ $RFSDIR/rootfs/etc/
	check_exit_code

	echo " | install shell profile for PS1 var to new base rootfs"
	install -m 644 $CFGDIR/profile $RFSDIR/rootfs/etc/profile
	check_exit_code

	echo " | install lsb to new base rootfs"
	install -m 755 $CFGDIR/lsb/init-functions $RFSDIR/rootfs/lib/lsb
	check_exit_code

	echo " | install updated upstart"
	install -m 755 $CFGDIR/interfaces/if-down.d/upstart $RFSDIR/rootfs/etc/network/if-down.d/
	check_exit_code
	install -m 755 $CFGDIR/interfaces/if-up.d/ifenslave $RFSDIR/rootfs/etc/network/if-up.d/
	check_exit_code
	install -m 755 $CFGDIR/interfaces/if-up.d/ip $RFSDIR/rootfs/etc/network/if-up.d/
	check_exit_code
	install -m 755 $CFGDIR/interfaces/if-up.d/upstart $RFSDIR/rootfs/etc/network/if-up.d/
	check_exit_code
	install -m 755 $CFGDIR/interfaces/if-up.d/20static-routes $RFSDIR/rootfs/etc/network/if-up.d/
	check_exit_code

	echo " | voice configs"
	install -m 755 $CFGDIR/kamailio/* $RFSDIR/rootfs/usr/sbin/
	check_exit_code
	
	echo " | kamailio configs"
	cp -Rp $CFGDIR/voice/kamailio/* $RFSDIR/rootfs/etc/kamailio/
	check_exit_code
	
	mv $RFSDIR/rootfs/etc/kamailio/kamailio.default $RFSDIR/rootfs/etc/default/kamailio
	
	echo " | rtpengine configs"
	install -m 644 $CFGDIR/voice/rtpengine/rtpengine.conf $RFSDIR/rootfs/etc/rtpengine/
	check_exit_code
	
	echo " | telegraf configs"
	install -m 644 $CFGDIR/voice/telegraf/telegraf.conf $RFSDIR/rootfs/etc/telegraf
	check_exit_code

	#echo " | voice sipgrep"
	#install -m 755 $CFGDIR/sipgrep/* $RFSDIR/rootfs/usr/sbin/
	#check_exit_code

	echo " | kamailio kamctl"
	install -m 755 $CFGDIR/kamailio/* $RFSDIR/rootfs/usr/sbin/
	check_exit_code

	echo " | iproute2 configs"
	install -m 755 $CFGDIR/iproute2/* $RFSDIR/rootfs/etc/iproute2/
	check_exit_code

	echo " | create ramdisk to install packages for squashfs"
	mountpoint -q "$RFSDIR/squashfs" && umount "$RFSDIR/squashfs" -l
	mount -o size=1024M -t tmpfs none "$RFSDIR/squashfs"
	check_exit_code

	# if this is ubuntu, we should copy local xtables binary
	if [ "$UBUNTU" = "true" ]; then
		cp -Rp /sbin/xtables-multi $RFSDIR/rootfs/sbin/xtables-multi
	fi

	echo " | copy base rootfs to squashfs"
	cd $RFSDIR/rootfs
	check_exit_code
	cp -rap [A-z]* $RFSDIR/squashfs
	check_exit_code

	echo " | install firewall config for sbc server"
	install -m 644 -D $CFGDIR/sbc/firewall.conf $RFSDIR/squashfs/etc/firewall.conf
	check_exit_code

	echo " | install interfaces config for sbc server"
	install -m 644 -D $CFGDIR/sbc/interfaces $RFSDIR/squashfs/etc/network/
	check_exit_code
	
	echo " | install routes config for sbc server"
	install -m 644 -D $CFGDIR/sbc/routes $RFSDIR/squashfs/etc/network/
	check_exit_code
	
	echo " | install motd for sbc server"
	install -m 644 -D $CFGDIR/sbc/banner $RFSDIR/squashfs/etc/motd
	check_exit_code
	
	echo " | create squashfs file from directory"
	[ -e $IMGDIR/sbc-public.$BEXT ] && rm $IMGDIR/sbc-public.$BEXT
	mksquashfs $RFSDIR/squashfs $IMGDIR/sbc-public.$BEXT -comp xz -e usr/share/doc/ -e boot -b 1024K -always-use-fragments -keep-as-directory
	check_exit_code

	echo " | umount ramdisk and discard uncompressed squashfs files"
	umount "$RFSDIR/squashfs"
	check_exit_code

	#echo " | copy squashfs image to initramfs"
	#mv $IMGDIR/dbc-sbc.squashfs $RFSDIR/initramfs/sbc-public.sb
	#check_exit_code
	echo " ! done."
}


init_rootfs

prebuild

buildrootfs
