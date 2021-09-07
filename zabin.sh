#!/bin/bash
echo
echo '========== Zabbix auto install script v1.0 =========='
echo 'Usage e.g.: sh zabin.sh <DB_password> <server name> [/path/to/pg_directory]'

# Chek password
if [ -z "$1" ]
then
    echo "ERROR: The database password parameter is not found! See usage e.g. "
    exit
fi

# Check server name
if [ -z "$2" ]
then	
   echo "ERROR: The server name parametr is not found. See usage e.g."
   exit
fi
echo
echo "====================================================="
echo "Plaese chek parametrs:"
echo "  Database password: "$1
echo "  Server name: "$2
if [ -n "$3" ]
then
	echo "  DB directory: "$3
else
	echo "  DB directory set to DEFAULT (/var/lib/postgresql/13/main) "
fi
echo
read -p 'if correct press Enter' uservar

echo
echo '=============== ADD repo keys ==============='
# Postgresql
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
# timescaledb
wget --quiet -O - https://packagecloud.io/timescale/timescaledb/gpgkey | sudo apt-key add -

echo
echo '============== ADD repo LISTs =============='
echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" |sudo tee  /etc/apt/sources.list.d/pgdg.list
sudo sh -c "echo 'deb https://packagecloud.io/timescale/timescaledb/debian/ `lsb_release -c -s` main' > /etc/apt/sources.list.d/timescaledb.list"

echo
echo '========= install zabbix server and zabbix agent ========='
wget https://repo.zabbix.com/zabbix/5.4/debian/pool/main/z/zabbix-release/zabbix-release_5.4-1+debian10_all.deb
dpkg -i zabbix-release_5.4-1+debian10_all.deb
apt update && apt install -y zabbix-server-pgsql zabbix-frontend-php php7.3-pgsql zabbix-nginx-conf zabbix-sql-scripts zabbix-agent 

echo
echo '========== Install PosgreSQL 13 and timescaledb =========='
apt install -y postgresql postgresql-contrib timescaledb-2-postgresql-13 rsync
service postgresql stop

# DB directory is change
if [ -n "$3" ]
then
	echo '========== Move PosgreSQL Data directoiry =========='
	#chage opt loaction
	mkdir -p $3
	## drwxr-xr-x  3 postgres    postgres    4096 авг 13 10:42 postgresql
	rsync -av /var/lib/postgresql/13/ $3
	mv /var/lib/postgresql/13/main /var/lib/postgresql/13/main.bak
	###### rm -Rf /var/lib/postgresql/12/main.bak
else
	echo "========== Database catalog is default =========="
fi

echo
echo '========== set postgresql.conf parametrs =========='
#backup
cp -a /etc/postgresql/13/main/postgresql.conf /etc/postgresql/13/main/postgresql.conf.bak

# Data directory
if [ -n "$3" ]
then
	sed -i "/data_directory/c \data_directory = '$3\/main'                # automatic set" /etc/postgresql/13/main/postgresql.conf
fi

#Connection Settings
sed -i "/listen_addresses/c \listen_addresses = ''                # automatic set" /etc/postgresql/13/main/postgresql.conf

service postgresql start

echo
echo '========== Stettings TimescaleDB =========='
timescaledb-tune --quiet --yes
sed -i "/max_connections/c max_connections = 100                  # (change requires restart)" /etc/postgresql/13/main/postgresql.conf

echo
echo '========== Settings postgres user and DB =========='
sudo -u postgres createuser zabbix
sudo -u postgres psql -c "ALTER ROLE zabbix WITH PASSWORD '$1'"
sudo -u postgres createdb -O zabbix zabbix 

echo
echo '========== Settings zabbix server =========='
# Backup
cp -a /etc/zabbix/zabbix_server.conf /etc/zabbix/zabbix_server.conf.bak

### Option: DBHost
sed -i "/DBHost/c DBHost=" /etc/zabbix/zabbix_server.conf

### Option: DBPassword
sed -i "/DBPassword/c \DBPassword=$1" /etc/zabbix/zabbix_server.conf

echo
echo '========== Settings Zabbix frontend =========='
# NGinx
# Backup
cp -a /etc/zabbix/nginx.conf /etc/zabbix/nginx.conf.bak

sed -i "/listen/c \        listen          80;" /etc/zabbix/nginx.conf
sed -i "/server_name/c \        server_name     $2;" /etc/zabbix/nginx.conf

echo
echo '========== INSTALL SQL DATA =========='
zcat /usr/share/doc/zabbix-sql-scripts/postgresql/create.sql.gz | sudo -u zabbix psql zabbix 
echo "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;" | sudo -u postgres psql zabbix
cat /usr/share/doc/zabbix-sql-scripts/postgresql/timescaledb.sql | sudo -u zabbix psql zabbix
echo
echo '================ HBA settings ================='

# backup 
cp -a /etc/postgresql/13/main/pg_hba.conf /etc/postgresql/13/main/pg_hba.conf.bak
sed -i "/local   all             all/c local   all             all                                     md5" /etc/postgresql/13/main/pg_hba.conf

echo ''
echo ''
echo '========== START SERVICES =========='
service postgresql restart
systemctl restart zabbix-server zabbix-agent nginx php7.3-fpm
systemctl enable zabbix-server zabbix-agent nginx php7.3-fpm 


echo
echo "===================INSTALL COMPLITED ======================"
echo 
echo 'http://'$2'/setup.php'
echo "Database username: zabbix"
echo "Database user password: "$1

if [ -n "$3" ]
then
	echo "DB directory: "$3
else
	echo "DB directory: /var/lib/postgresql/13/main "
fi
echo
echo
