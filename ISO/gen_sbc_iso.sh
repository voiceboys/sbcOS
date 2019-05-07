cd /tmp/sbc-data-15062 && /usr/bin/mkisofs -o /tmp/sbc-x86_64.iso -v -J -R -D -A sbc -V sbc -no-emul-boot -boot-info-table -boot-load-size 4 -b sbc/boot/isolinux.bin -c sbc/boot/isolinux.boot .
