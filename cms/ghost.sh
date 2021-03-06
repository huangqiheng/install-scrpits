#!/bin/bash

. $(dirname $(readlink -f $0))/basic_functions.sh

check_bash

GHOST_PATH=/var/www/ghost
GHOST_USER=ghostblog
GHOST_PASS=ghostblogpass
MYSQL_ROOT=ghostroot
DEV_MODE=1
GHOST_INSTALL='ghost install --local'

main () 
{
	check_update
	setup_nodejs

	check_npm_g ghost ghost-cli@latest

	if [ "$1" = "dev" ]; then
		if [ -n "$2" ]; then
			GHOST_PATH="$2"
		fi
	elif [ "$1" = "idc" ]; then
		DEV_MODE=0
		if [ -n "$2" ]; then
			GHOST_PATH="$2"
		fi
	else
		if [ -n "$1" ]; then
			GHOST_PATH="$1"
		fi
	fi

	if [ $DEV_MODE -eq 1 ]; then
		check_apt sqlite3

		check_npm_g nodemon nodemon@latest
		check_npm_g gscan gscan
	else
		GHOST_INSTALL='ghost install'
		setup_mysql
		setup_nginx

	fi

	if ! user_exists $GHOST_USER; then
		adduser --home "/home/$GHOST_USER" --gecos "" --disabled-password $GHOST_USER
		echo "$GHOST_USER:$GHOST_PASS" | chpasswd
		usermod -aG sudo $GHOST_USER
	fi

	mkdir -p $GHOST_PATH
	chmod 775 $GHOST_PATH
	chown $GHOST_USER:$GHOST_USER $GHOST_PATH

	runuser -l $GHOST_USER -c "cd $GHOST_PATH; $GHOST_INSTALL"
}

setup_nginx()
{
	check_apt nginx

	if ufw_actived; then
		ufw allow 'Nginx Full'
		ufw reload
	fi
}

setup_mysql()
{
	check_apt debconf-utils

	debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_ROOT"
	debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_ROOT"
	check_apt mysql-server
}

setup_nodejs()
{
	if cmd_exists /usr/bin/node; then
		log "node has been installed"
		return
	fi

	curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
	check_apt nodejs
}

main "$@"; exit $?
