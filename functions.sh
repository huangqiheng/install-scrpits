#!/bin/dash

select_subpath()
{
	local BOOT_PATH="$1"
	mkdir -p "${BOOT_PATH}"

	while true; do
		if [ ! "X$2" = 'X' ]; then
			if [ $(echo -n "$2" | wc -m) -gt 3 ]; then
				FUNC_RESULT="$2"
				break
			else
				log_r 'Directory name too short'
				exit 1
			fi
		fi

		options=$(ls -1p "${BOOT_PATH}" | grep / | grep -v 'Downloads' | sed 's/.$//')

		if [ "X$options" = 'X' ]; then
			while true; do
				read -p "Please enter Dir Name : " user_enter

				if [ $(echo -n "$user_enter" | wc -m) -gt 3 ]; then
					FUNC_RESULT="$user_enter"
					break
				fi
				log_y 'String length Must > 3'
			done
			break
		fi

		echo "$options" | nl 
		echo ''
		read -p "Select config INDEX : " user_select
		FUNC_RESULT=$(echo "$options" | sed -n "${user_select}p")
		break
	done

	mkdir -p "${BOOT_PATH}/Downloads"
	mkdir -p "${BOOT_PATH}/${FUNC_RESULT}"
}

docker_home()
{
	check_docker
	if [ "$1" = 'auto' ]; then
		FUNC_RESULT='auto'
		mkdir -p "$CACHE_DIR/$EXEC_NAME/$FUNC_RESULT"
	else
		select_subpath $CACHE_DIR/$EXEC_NAME "$1"
	fi

	[ $(whoami) = 'root' ] && chownUser "$CACHE_DIR/$EXEC_NAME"

	SubHome="$CACHE_DIR/$EXEC_NAME/$FUNC_RESULT"
	SubName=$(rm_space "$FUNC_RESULT")
}


x11_forward_server()
{
	log_g 'setting ssh server'
	check_apt xauth

	set_conf /etc/ssh/sshd_config
	set_conf X11Forwarding yes ' '
	set_conf X11DisplayOffset 10 ' '
	set_conf X11UseLocalhost no ' '

	cat /var/run/sshd.pid | xargs kill -1
}

x11_forward_client()
{
	log_g 'setting ssh client'
	cat > $UHOME/.ssh/config <<EOL
Host *
  ForwardAgent yes
  ForwardX11 yes
EOL
}

setup_polipo()
{
	socksport=$1
	webport=$2
	check_apt polipo

	set_conf '/etc/polipo/config'
	set_conf socksParentProxy "127.0.0.1:${socksport}"
	set_conf socksProxyType socks5
	set_conf proxyAddress '::0'
	set_conf proxyPort "$webport"

	service polipo restart
}


setup_tor()
{
	socksproxy=$1
	check_apt tor

	set_conf /etc/tor/torrc
	set_conf Socks5Proxy "$socksproxy" ' '
	set_conf SOCKSPort '0.0.0.0:9050' ' '
	set_conf /etc/tor/torsocks.conf
	set_conf TorAddress '0.0.0.0'
	systemctl restart tor
}


build_hostapd()
{
	if cmd_exists hostapd; then
		log_g 'hostapd has been installed.'
		return
	fi

	check_apt pkg-config

	cd $CACHE_DIR

	git clone https://github.com/tgraf/libnl-1.1-stable.git
	cd libnl-1.1-stable
	./configure
	make
	make install

	cd $CACHE_DIR
	git clone http://w1.fi/hostap.git
	cd hostap/hostapd
	cp defconfig .config
	make
	make install
}

sslocal_ports()
{
	check_apt net-tools
	netstat -plunt | grep LISTEN |  grep ss-local | awk '{print $4}' | awk -F: '{print $2}'
}

run_sslocal()
{
	local opts="${1:--v}"
	local inputScript="$(cat /dev/stdin)"

	if ! cmd_exists ss-local; then
		check_sudo
		check_apt shadowsocks-libev

		if pgrep -x "ss-server" >/dev/null; then
			systemctl stop shadowsocks-libev.service
			systemctl disable shadowsocks-libev.service
		fi
	fi

	echo "$inputScript" > /tmp/sslocal.json
	inputServer=$(get_ssserver /tmp/sslocal.json)
	echo "Connect to $inputServer"

        ss-local "$opts" -c /tmp/sslocal.json
}

install_ssredir()
{
	check_apt haveged rng-tools shadowsocks-libev

	if [ ! -f /etc/shadowsocks-libev/bwghost.json ]; then
		read -p "Please input Shadowsocks server: " inputServer 

		if [ -z "$inputServer" ]; then
			log 'inputed server error'
			exit 1
		fi

		read -p "Input PASSWORD: " inputPass

		if [ -z "$inputPass" ]; then
			log 'pasword must be set'
			exit 2
		fi

		cat > /etc/shadowsocks-libev/bwghost.json <<EOL
{
	"server":"${inputServer}",
	"password":"${inputPass}",
        "mode":"tcp_and_udp",
        "server_port":16666,
        "local_address": "0.0.0.0",
        "local_port":6666,
        "method":"xchacha20-ietf-poly1305",
        "timeout":300,
        "fast_open":false
}
EOL
	else
		inputServer=$(get_ssserver /etc/shadowsocks-libev/bwghost.json)
	fi

	log_y "shadowsocks server: $inputServer"

	systemctl enable shadowsocks-libev-redir@bwghost
	systemctl daemon-reload
	systemctl start shadowsocks-libev-redir@bwghost
}

get_ssserver()
{
	grep '"server":' "$1" | tr '":,' ' ' | awk -F' ' '{print $2}'
}

install_terminals()
{
	check_apt xterm 
	check_apt lxterminal
	check_apt tmux

	# xrdb -merge ~/.Xresources
	# Ctrl-Right mouse click for temporary change of font size
	# select to copy, and shift+insert or shift+middleClick to paste
	cat > ${UHOME}/.Xresources <<-EOL
	XTerm*utf8:true
	XTerm*utf8Title:true
	XTerm*cjkWidth:true
	XTerm*faceName:DejaVu Sans Mono:pixelsize=12
	XTerm*faceNameDoublesize:WenQuanYi Zen Hei Mono:pixelsize=13
	XTerm*selectToClipboard:true
	XTerm*inputMethod:fcitx
EOL
	chownUser ${UHOME}/.Xresources
	xinitrc "xrdb -merge ${UHOME}/.Xresources"
}

install_wps()
{
	if cmd_exists wps; then
		log_g "wps has been installed."
		return
	fi

	check_apt unzip

	cd $CACHE_DIR
	wget http://kdl.cc.ksosoft.com/wps-community/download/6757/wps-office_10.1.0.6757_amd64.deb
	dpkg -i wps-office_10.1.0.6757_amd64.deb

	cd $DATA_DIR
	unzip wps_symbol_fonts.zip -d /usr/share/fonts/wps-office

	ratpoisonrc "bind C-p exec /usr/bin/wps"
}

setup_objconv()
{
	if cmd_exists objconv; then
		log_g "objconv has been installed"
		return
	fi

	cd $CACHE_DIR
	if [ ! -d objconv ]; then
		git clone https://github.com/vertis/objconv.git
	fi

	cd objconv

	g++ -o objconv -O2 src/*.cpp  -Wno-narrowing -Wno-format-overflow

	cp objconv /usr/local/bin
}

cloudinit_remove()
{
	if [ ! -d /etc/cloud/ ]; then
		log_y 'cloud-init isnt exists'
		return
	fi

	log_g 'datasource_list: [ None ]' | sudo -s tee /etc/cloud/cloud.cfg.d/90_dpkg.cfg
	apt-get purge -y cloud-init
	rm -rf /etc/cloud/
	rm -rf /var/lib/cloud/
}

install_riot() 
{
	check_apt lsb-release wget apt-transport-https
	
	if ! cmd_exists riot-web; then
		check_sudo
		wget -O /usr/share/keyrings/riot-im-archive-keyring.gpg https://packages.riot.im/debian/riot-im-archive-keyring.gpg
		echo "deb [signed-by=/usr/share/keyrings/riot-im-archive-keyring.gpg] https://packages.riot.im/debian/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/riot-im.list
		apt update -y
		check_apt riot-web
	fi

	check_cmdline riot <<-EOF
	#!/bin/dash
	riot-web
EOF

	echo 'Just type cmd: riot'
}


install_astrill()
{
	if cmd_exists astrill; then
		log_g "astrill has been installed."
		return
	fi

	cd $CACHE_DIR

	# check_apt 
	check_apt libgtk2.0-0
	apt --fix-broken install
	check_apt libcanberra-gtk-module
	check_apt gtk2-engines-pixbuf gtk2-engines-murrine 
	check_apt gnome-themes-standard
	apt --yes autoremove
	
	if [ -f "$DATA_DIR/astrill-setup-linux64.deb" ]; then
		dpkg -i "$DATA_DIR/astrill-setup-linux64.deb"
		ratpoisonrc "bind C-a exec /usr/local/Astrill/astrill"
		ln -sf /usr/local/Astrill/astrill /usr/local/bin/astrill
		return 0
	else
		log_y 'FIXME: download astrill-setup-linux64.deb please'
		return 1
	fi
}

setup_github_go()
{
	local owner="$1"
	local cmd="$2"

	empty_exit $owner 'github owner' 

	if [ "X$cmd" = 'X' ]; then
		IFS=/; set -- $(echo "$owner"); IFS=
		owner="$1"
		cmd="$2"
	fi

	empty_exit $cmd 'github repo' 

	if cmd_exists "$cmd"; then
		log_g "$cmd has been installed"
		return 0
	fi

	setup_golang
	go get "github.com/$owner/$cmd"

	gopath=$(go env GOPATH)

	local cmdPath="$gopath/bin/$cmd"
	if [ -f "$cmdPath" ]; then
		ln -sf "$cmdPath" /usr/local/bin/
		return 0
	else
		log_r "$cmd install failure"
		return 1
	fi
}

setup_pup()
{
	setup_github_go ericchiang pup
}

setup_gotty()
{
	setup_github_go yudai gotty
}

setup_golang()
{
	if cmd_exists go; then
		log_g 'golang is installed'
		return 0
	fi

	if [ "$1" = "" ]; then
		if ! apt_exists golang-go; then
			check_update ppa:longsleep/golang-backports
		fi
		check_apt golang-go
		return 1
	fi

	cd $CACHE_DIR
	wget https://dl.google.com/go/go${1}.linux-amd64.tar.gz
	tar -C /usr/local -xzf go${1}.linux-amd64.tar.gz
	echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
	echo 'export PATH=$PATH:$UHOME/go/bin' >> /etc/profile

	return 2
}

setup_typescript()
{
	setup_nodejs
	check_npm_g typescript
}


echo_block()
{
	local begincode="$1"
	local endcode="$2"
	local src="$(sed -n '/^\s*'$begincode'/,/^\s*'$endcode'/p' $EXEC_SCRIPT)"
	echo $src
}


setup_nodejs()
{
	if cmd_exists node; then
		log_g "node has been installed"
		return
	fi

	version=${1:-'10'}

	curl -sL https://deb.nodesource.com/setup_${version}.x | sudo -E bash -
	check_apt nodejs
}

setup_ffmpeg3()
{
	if need_ffmpeg 3.3.0; then
		log_y 'need to update ffmpeg'
		apt purge -y ffmpeg 
		check_update ppa:jonathonf/ffmpeg-3
	fi

	check_apt ffmpeg libav-tools x264 x265

	log_g "Now ffmpeg version is: $(ffmpeg_version)"
}

need_ffmpeg()
{
	local current_version=$(ffmpeg_version)
	[ ! $? ] && return 0
	version_compare $current_version $1
	[ ! $? -eq 1 ] && return 0
	return 1
}

version_compare() 
{
	dpkg --compare-version "$1" eq "$2" && return 0
	dpkg --compare-version "$1" lt "$2" && return 1
	return 2
}

ffmpeg_version()
{
	if ! cmd_exists ffmpeg; then
	       	return 1
	fi

	IFS=' -'
	set -- $(ffmpeg -version | grep "ffmpeg version")
	echo $3
	[ ! -z $3 ]
}
