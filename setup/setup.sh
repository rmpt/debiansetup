#!/bin/bash

# This script must be run as root


UPDATE=1
UPGRADE=1
TRANSMISSION=0
SAMBA=0
SAMBA_USER=clientuser                     # only used if SAMBA=1
JAVA=0
TOMCAT=0
MOUNT=0
NETWORK=0
POSTGRESQL=0
POSTGRESQL_CREATE_USER_AND_DATABASE=0
POSTGRESQL_USER=psqluser                   # only used if POSTGRESQL_CREATE_USER_AND_DATABASE=1
POSTGRESQL_USER_PASSWORD=psqluser_passwd   # only used if POSTGRESQL_CREATE_USER_AND_DATABASE=1
POSTGRESQL_DATABASE=mydatabase             # only used if POSTGRESQL_CREATE_USER_AND_DATABASE=1
OWNCLOUD=0

TOMCAT_VERSION=8.5.0
TOMCAT_FILE=apache-tomcat-$TOMCAT_VERSION.tar.gz
TOMCAT_REPO=http://www.us.apache.org/dist/tomcat/tomcat-8/v$TOMCAT_VERSION/bin/$TOMCAT_FILE
HOME=/home/pi

ME=$(basename $BASH_SOURCE)
LOG_FILE=${ME}.log
SETUP_LOCATION="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function log() {
    echo "$1" >> $HOME/${LOG_FILE}
}

function baseSetup() {
    apt-get install dos2unix
}

function setupTransmission() {
    log "Installing transmission-daemon"
    echo -e "Y" | apt-get install transmission-daemon

    log "Setting up transmission-daemon"
    service transmission-daemon stop
    cd /etc/transmission-daemon/
    cp settings.json settings.json.backup
    sed -i '/download-dir/c\"download-dir": "/media/elements/Downloads", ' settings.json
    sed -i '/incomplete-dir/c\"incomplete-dir": "/media/elements/Downloads", ' settings.json
    sed -i '/rpc-whitelist-enabled/c\"rpc-whitelist-enabled": false, ' settings.json
    sed -i '/script-torrent-done-enabled/c\"script-torrent-done-enabled": true, ' settings.json
    sed -i '/script-torrent-done-filename/c\"script-torrent-done-filename": "/etc/transmission-daemon/post-execute.sh", ' settings.json
    sed -i '/speed-limit-down/c\"speed-limit-down": 1500, ' settings.json
    sed -i '/speed-limit-up/c\"speed-limit-up": 50, ' settings.json
    sed -i '/speed-limit-up-enabled/c\"speed-limit-up-enabled": true, ' settings.json
    sed -i '/utp-enabled/c\"utp-enabled": true ' settings.json                            # we dont need the comma, it's the last configuration line
    sed -i '/rpc-password/c\"rpc-password": "{bfa3f3f398521d4b47211633718a6f6957f3d60fY.Gz2vX2", ' settings.json
    sed -i '/rpc-username/c\"rpc-username": "rmpt", ' settings.json
    sed -i '/port-forwarding-enabled/c\"port-forwarding-enabled": true, ' settings.json
    sed -i '/peer-limit-global/c\"peer-limit-global": 800, ' settings.json
    sed -i '/peer-limit-per-torrent/c\"peer-limit-per-torrent": 200, ' settings.json
    sed -i '/peer-port/c\"peer-port": 51403, ' settings.json
    sed -i '/peer-port-random-high/c\"peer-port-random-high": 51500, ' settings.json
    sed -i '/peer-port-random-low/c\"peer-port-random-low": 51400, ' settings.json
    sed -i '/peer-port-random-on-start/c\"peer-port-random-on-start": true, ' settings.json
    sed -i '/download-queue-size/c\"download-queue-size": 7, ' settings.json
    sed -i '/encryption/c\"encryption": 0, ' settings.json
    log "Changed transmission-daemon settings file content"
    log "$(cat settings.json)"
    log "-- transmission-daemon settings file content end"
    service transmission-daemon start

    log "transmission-daemon setup finished"
}

function setupSamba() {
    log "Installing Samba"
    echo -e "Y" | apt-get install samba samba-common-bin
    log "Setting up Samba"
    service samba stop
    cd /etc/samba/
    echo "[RBHDD]" >> smb.conf
    echo "   path = /media/elements" >> smb.conf
    echo "   writable = yes" >> smb.conf
    log "Changed samba settings file content"
    log "$(cat settings.json)"
    log "-- samba settings file content end"
    service samba start

    log "Adding user "$SAMBA_USER" to unix and samba"
    useradd $SAMBA_USER
    echo -e "internet6\ninternet6" | passwd $SAMBA_USER
    echo -e "internet6\ninternet6" | smbpasswd -a $SAMBA_USER

    log "Samba setup finished"
}

function setupJava(){
   echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" | tee /etc/apt/sources.list.d/webupd8team-java.list
   echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" | tee -a /etc/apt/sources.list.d/webupd8team-java.list
   apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886
   apt-get update
   echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | sudo /usr/bin/debconf-set-selections
   apt-get install oracle-java8-installer
}

function setupTomcat() {
    log "Installing Tomcat"
    adduser \
      --system \
      --shell /bin/bash \
      --gecos 'Tomcat Java Servlet and JSP engine' \
      --group \
      --disabled-password \
      --home /home/tomcat \
      tomcat
    mkdir -p ~/tmp
    cd ~/tmp
    wget $TOMCAT_REPO
    tar xvzf $TOMCAT_FILE
    rm $TOMCAT_FILE
    mkdir -p /usr/share/tomcat8
    mv ~/tmp/apache-tomcat-$TOMCAT_VERSION /usr/share/tomcat8
    chown -R tomcat:tomcat /usr/share/tomcat8
    chmod +x /usr/share/tomcat8/apache-tomcat-$TOMCAT_VERSION/bin/*.sh

    log "Creating /etc/init.d/tomcat"
    cd $SETUP_LOCATION
    
    dos2unix tomcat
    cp tomcat /etc/init.d/tomcat

    cd /etc/init.d/
    chmod 755 tomcat
    update-rc.d tomcat defaults

    service tomcat restart

    log "Tomcat setup finished"
}

function setupMountDevice() {
    log "Setting mount script"

    log "Installing ntfs-3g"
    apt-get install ntfs-3g

    log "Creating elements folder for external drive support"
    mkdir /media/elements

    cd $SETUP_LOCATION
    
    dos2unix mount
    cp mount /etc/init.d/mount
    cd /etc/init.d/
    chmod 755 mount
    update-rc.d mount defaults

    log "Mount setup finished"
}

function setupNetwork() {
    log "Setting eth0 interface parameters"
    IP_BASE="192.168.2."
    cd /etc/network/
    cp interfaces interfaces_backup

    log "Adding "${IP_BASE}"254 to /etc/resolv.conf"
    echo "nameserver "${IP_BASE}"254" >> /etc/resolv.conf

    sed -i '/eth0/c\' interfaces
    echo "auto eth0
    iface eth0 inet static
    address "${IP_BASE}"5
    gateway "${IP_BASE}"254
    netmask 255.255.255.0
    network "${IP_BASE}"0
    broadcast "${IP_BASE}"255" >> interfaces

    log "New interfaces file content"
    log "$(cat interfaces)"
    log "-- interfaces content end"

    log "eth0 interface setup finished"
}

function setupPostgresql(){
   echo 'deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main' >> /etc/apt/sources.list.d/postgresql.list

   wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
   apt-key add -
   apt-get update

   apt-get install postgresql-9.4

  if ((POSTGRESQL_CREATE_USER_AND_DATABASE))
  then
     su - postgres
     psql
     CREATE USER $POSTGRESQL_USER WITH PASSWORD $POSTGRESQL_USER_PASSWORD;
     CREATE DATABASE $POSTGRESQL_DATABASE OWNER $POSTGRESQL_USER;
     \q
     exit
  fi
}

function setupOwnCloud() {
    echo 'deb http://download.opensuse.org/repositories/isv:/ownCloud:/community/Debian_8.0/ /' >> /etc/apt/sources.list.d/owncloud.list
    cd /tmp
    wget http://download.opensuse.org/repositories/isv:ownCloud:community/Debian_8.0/Release.key
    apt-key add - < Release.key
    apt-get update
    apt-get install owncloud

    mkdir -p /media/owncloud
    chown www-data:www-data /media/owncloud
    chmod 750 /media/owncloud


#    mysql --defaults-file=/etc/mysql/debian.cnf

#    CREATE DATABASE owncloud;
#    CREATE USER owncloud@localhost IDENTIFIED BY 'aszxp01';
#    GRANT ALL PRIVILEGES ON owncloud.* TO owncloud@localhost;
#    flush privileges;
#    quit
}

if (($UPDATE));
then
apt-get update
fi

if (($UPGRADE));
then
apt-get upgrade
fi

baseSetup

if (($NETWORK))
then
setupNetwork
fi

if (($TRANSMISSION))
then
setupTransmission
fi

if (($SAMBA))
then
setupSamba
fi

if (($JAVA))
then
setupJava
fi

if (($TOMCAT))
then
setupTomcat
fi

if (($MOUNT))
then
setupMountDevice
fi

if (($POSTGRESQL))
then
setupPostgresql
fi

if (($OWNCLOUD))
then
setupOwnCloud
fi
