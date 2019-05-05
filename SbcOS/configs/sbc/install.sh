source /target/dbc-cldbase/bin/include.sh
swap_std

VARIANT=$1
DEV=$2

if [ $DEV -eq 1 ]; then
  #install -m 644 $CFGDIR/$VARIANT/config $RFSDIR/squashfs/etc/dbc-$VARIANT/config.properties
  #check_exit_code
  rm $RFSDIR/squashfs/etc/dbc-$VARIANT/dbc.jks
  check_exit_code
fi
