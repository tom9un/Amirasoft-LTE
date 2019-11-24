#!/bin/bash
# Copyright (C) 2012-2015 Amarisoft
# OTS installer version 2015-10-28

# Run this script to install sofwate
#   Place lteXXX-2015-10-28.tar.gz file for eNB, MME, MBMSGW and WWW in same directory

VERSION="2015-10-28"
ETC_CFG="/etc/ltestart.conf"

echo "***************************************"
echo "* Installing Amarisoft LTE 2015-10-28 *"
echo "***************************************"
echo ""

if [ "$1" = "-h" -o "$1" = "--help" ] ; then
    echo "Usage: $0 [<install path (default is /root)>]"
    exit 1
fi

# Check root
user=$(whoami)
if [ "$user" != "root" ]; then
    echo "Sorry $user, you need to be root"
    exit 1
fi


# Check distrib
distrib=""
if [ -e "/etc/fedora-release" ]; then
    distrib="fedora"
    echo "Fedora distribution found"
else
    grep -i Ubuntu /etc/lsb-release
    if [ "$?" = "0" ]; then
        distrib="ubuntu"
        echo "Ubuntu distribution found"
    fi
fi
if [ "$distrib" = "" ] ; then
    echo "Sorry, installation procedure only available on Fedora and Ubuntu distributions."
    exit 1
fi

# Installation directory
IDIR="/root"
if [ "$1" != "" ] ; then
    if [ -d "$1" ] ; then
        IDIR=$(readlink -f "$1")
    else
        echo "$1 does not exist"
        exit 1
    fi
fi

# Previous ?
if [ -e "$ETC_CFG" ] ; then
    IDIR1=$(cat $ETC_CFG | grep IDIR | cut -d '=' -f2)
    if [ "$IDIR1" != "$IDIR" -a "$IDIR1" != "" ] ; then
        read -t 1 -n 1000 discard; # Flush STDIN
        read -p "Previous install was at $IDIR1, do you want to keep previous directory ? [yN] " INSTALL
        if [ "$INSTALL" = "y" ] ; then
            IDIR="$IDIR1"
        fi
    fi
fi


function install_dir
{
    # $1 => install path
    # $2 => dir
    # $3 => name (opt)
    if [ -d "${1}/${2}" ]; then
        rm -Rf ${1}/${2}.bak
        mv ${1}/${2} /${1}/${2}.bak
    fi
    mv ${2} /${1}/

    if [ "${3}" != "" ] ; then
        rm -Rf ${1}/${3}
        ln -s ${1}/${2} /${1}/${3}
    fi
}


step=1

# OTS
OTS="lteots-linux-${VERSION}"
if [ -e "${OTS}.tar.gz" ] ; then
    echo "$step) Add service"

    tar xzf ${OTS}.tar.gz
    case $distrib in
    fedora)
        yum list installed screen 1>/dev/null 2>/dev/null
        if [ "$?" != "0" ] ; then
            yum -q -y install screen
        fi

        # Stop service
        systemctl -q stop lte 2>/dev/null

        cp ${OTS}/lte.service /lib/systemd/system/lte.service
        rm -f /etc/systemd/system/lte.service
        ln -s /lib/systemd/system/lte.service /etc/systemd/system/lte.service
        systemctl -q --system daemon-reload
        systemctl -q enable lte
        systemctl -q enable NetworkManager-wait-online.service

        # Remove old crontab (from old OTS scripts)
        if [ -e "/root/start.sh" ] ; then
            crontab -r
            rm -f /root/start.sh
        fi
        ;;

    ubuntu)
        apt-get -qq install -y screen

        # Remove legacy
        deamon="/etc/init.d/lte.d"
        if [ -e "$deamon" ]; then
            $deamon stop
            update-rc.d lte.d disable
            rm -f $deamon
        fi

        # Stop service (if exists)
        if [ -e "/etc/init/lte.conf" ] ; then
            service lte stop 2>/dev/null
        fi

        cp ${OTS}/lte.conf /etc/init/

        if [ ! -e "/lib/x86_64-linux-gnu/libcrypto.so.10" ] ; then
            ln -s /lib/x86_64-linux-gnu/libcrypto.so.1.0.0 /lib/x86_64-linux-gnu/libcrypto.so.10
        fi
        if [ ! -e "/lib/x86_64-linux-gnu/libssl.so.10" ] ; then
            ln -s /lib/x86_64-linux-gnu/libssl.so.1.0.0 /lib/x86_64-linux-gnu/libssl.so.10
        fi
        ;;
    esac

    # Copy scripts
    cp ${OTS}/ltestart.sh /usr/local/bin/
    cp ${OTS}/ltestop.sh /usr/local/bin/
    cp ${OTS}/ltelogs.sh /usr/local/bin/

    rm -f $ETC_CFG
    cat ${OTS}/ltestart.conf | sed "s'<IDIR>'$IDIR'" > $ETC_CFG

    # Create log dir
    mkdir -p /var/log/lte

    step=$(($step+1))
fi

# Web portal
WWW="ltewww-linux-${VERSION}"
if [ -e "${WWW}.tar.gz" ] ; then
    echo "$step) Install WEB portal"
    case $distrib in
    fedora)
        yum list installed php 1>/dev/null 2>/dev/null
        if [ "$?" != "0" ] ; then
            yum -q -y install php
        fi

        # Allow HTTPD to access common /tmp
        for file in /lib/systemd/system/httpd.service /etc/systemd/system/multi-user.target.wants/httpd.service ; do
            if [ -e "$file" ] ; then
                sed -i.bak -e "s/^PrivateTmp/#PrivateTmp/" $file
            fi
        done
        systemctl --system daemon-reload
        systemctl restart httpd
        WWW_PATH=/var/www/html
        ;;
    ubuntu)
        apt-get -qq install -y apache2
        apt-get -qq install -y php5
        WWW_PATH=/var/www
        ;;
    esac

    # Update
    tar xzf ${WWW}.tar.gz
    install_dir "${WWW_PATH}" "${WWW}" "lte"

    # Redirect
    if [ ! -e "${WWW_PATH}/index.html" ] ; then
        echo "<script>location.href='lte/';</script>" > "${WWW_PATH}/index.html"
    fi

    step=$(($step+1))
fi

# eNB
ENB="lteenb-linux-${VERSION}"
if [ -e "${ENB}.tar.gz" ] ; then
    echo "$step) Install eNB"
    tar xzf ${ENB}.tar.gz
    install_dir "${IDIR}" "${ENB}" "enb"

    # TRX (Except example/uhd)
    for i in $(find . -name "trx_*.tar.gz" -type f | sed "s/\.tar\.gz//") ; do
        TRX_DIR=$(echo "$i" | sed -e 's/^\.\///')
        TRX_NAME=${TRX_DIR:4:-11}

        if [ "${TRX_NAME:0:7}" != "example" -a "${TRX_NAME:0:3}" != "uhd" ] ; then
            read -t 1 -n 1000 discard; # Flush STDIN
            read -p "  Do you want to install TRX driver '${TRX_NAME}' ? [yN] " INSTALL
            if [ "$INSTALL" = "y" ] ; then
                break
            fi
        fi
        TRX_DIR=""
    done

    if [ "$TRX_DIR" != "" ] ; then

        step=$(($step+1))
        echo "$step) Install TRX (${TRX_NAME})"

        rm -Rf $TRX_DIR
        tar xzf ${TRX_DIR}.tar.gz
        TRX_LINK=${TRX_DIR:0:-11}
        install_dir "${IDIR}" "${TRX_DIR}" "${TRX_LINK}"

        # Specific install ?
        if [ -e "${IDIR}/${TRX_LINK}/install.sh" ] ; then
            ${IDIR}/${TRX_LINK}/install.sh ${IDIR}/${ENB}
        fi

        # OTS config
        if [ -d "${OTS}" ] ; then
            if [ -e "${IDIR}/${TRX_DIR}/ltestart.conf" ] ; then
                cat ${IDIR}/${TRX_DIR}/ltestart.conf >> $ETC_CFG
            fi
        fi

    # USRP
    else
        if [ -d "${OTS}" ] ; then
            mkdir ${IDIR}/${ENB}/trx
            for i in n2x0 x3x0 b2x0 ; do
                cat ${OTS}/rrh_check_usrp.sh | sed -e "s/##TYPE##/$i/" > ${IDIR}/${ENB}/config/$i/rrh_check.sh
                chmod --reference ${OTS}/rrh_check_usrp.sh ${IDIR}/${ENB}/config/$i/rrh_check.sh
            done
        fi

        # Check calibration
        if [ ! -d "/root/.uhd/cal" ] ; then
            echo "***************"
            echo "*** Warning ***"
            echo "***************"
            echo ""
            echo "=> It seems that your USRP has not been calibrated on this machine."
            echo "   You need it unless you'll have signal stability issue."
            echo "   Please refer to eNB documentation (Section USRP N200/N210 setup)."
            echo "   Note that if you have two USRP for MIMO, you need to calibrate both."
            echo ""
            echo "Calibration ex:"
            echo "  uhd_cal_rx_iq_balance --args addr=192.168.10.2"
            echo "  uhd_cal_tx_iq_balance --args addr=192.168.10.2"
            echo "  uhd_cal_tx_dc_offset --args addr=192.168.10.2"
            echo ""
        fi
    fi

    step=$(($step+1))
fi

# MME
MME="ltemme-linux-${VERSION}"
if [ -e "${MME}.tar.gz" ] ; then
    echo "$step) Install MME"
    tar xzf ${MME}.tar.gz
    install_dir "${IDIR}" "${MME}" "mme"

    step=$(($step+1))

    # IMS
    IMS_DIR="${IDIR}/mme"
    if [ -e "${IMS_DIR}/lteims" ] ; then
        read -t 1 -n 1000 discard; # Flush STDIN
        read -p "  Do you want to install IMS ? [yN] " IMS
        if [ "$IMS" = "y" ] ; then
            echo "$step) Install IMS"

            (cd $IMS_DIR/config && mv mme.cfg mme-default.cfg && ln -s mme-ims.cfg mme.cfg)
            step=$(($step+1))

            # Stop asterisk in case of old OTS
            if [ "$(pgrep asterisk)" != "" ] ; then
                read -t 1 -n 1000 discard; # Flush STDIN
                read -p "  Do you want disable asterisk ? (recommended) [Yn] " ASTERISK
                if [ "$ASTERISK" == "" -o "$ASTERISK" = "y" -o "$ASTERISK" = "Y" ] ; then
                    chkconfig asterisk off
                    service asterisk stop
                fi
            fi
        else
            echo "IMS_PATH=\"\" # Disabled by OTS install" >> $ETC_CFG
        fi
    fi

fi

# MBMS
MBMS="ltembmsgw-linux-${VERSION}"
if [ -e "${MBMS}.tar.gz" ] ; then
    echo "$step) Install MBMS"
    tar xzf ${MBMS}.tar.gz
    install_dir "${IDIR}" "${MBMS}" "mbms"

    step=$(($step+1))
fi

# End of OTS: start services
if [ -d "${OTS}" ] ; then
    echo "$step) Start service"
    systemctl -q start lte 2>/dev/null

    # Clean
    rm -Rf ${OTS}

    step=$(($step+1))
fi

echo -e "# Last install dir\nIDIR=$IDIR\n" >> $ETC_CFG

