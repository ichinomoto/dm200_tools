# apt install
apt-get -y install gh less zip unzip nkf fbcat \
cifs-utils samba smbclient \
fonts-noto-color-emoji fontforge
# - for build
apt-get -y install build-essential bison automake autoconf make cmake gcc
# - for kmscon build
apt-get -y install libudev-dev libxkbcommon-dev libpango1.0-dev pkgconf check

# pip install
apt-get -y install python3-pip pipenv python3-soupsieve
pip install meson ninja --break-system-packages

cat >/tmp/install-nodejs.sh<<'EOT'
#/bin/bash
# nvmをダウンロードしてインストールする：
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
# シェルを再起動する代わりに実行する
\. "$HOME/.nvm/nvm.sh"
# Node.jsをダウンロードしてインストールする：
nvm install 23
EOT
chmod +x /tmp/install-nodejs.sh

# ----- install tailscale -----
curl -o- https://tailscale.com/install.sh | bash

# install metasploit
curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb  | bash

# ----- install fish for debian13 ----- 
echo 'deb http://download.opensuse.org/repositories/shells:/fish:/release:/4/Debian_13/ /' | sudo tee /etc/apt/sources.list.d/shells:fish:release:4.list
curl -fsSL https://download.opensuse.org/repositories/shells:fish:release:4/Debian_13/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/shells_fish_release_4.gpg > /dev/null
apt-get update && apt-get -y install fish

## ----- fish customize ----- 
/usr/bin/fish -c "curl -sL https://git.io/fisher | source && fisher install jorgebucaran/fisher"
/usr/bin/fish -c "fisher update"
/usr/bin/fish -c "fisher install IlanCosman/tide@v6"

# ----- build ----- 
install -m 777 -g 1000 -o 1000 -d /repo
cd /repo
ARCH=arm
CFLAGS="-mfloat-abi=hard -mfpu=neon-vfpv4 -O3"
## ----- kmscon ----- 
git clone --single-branch -b main https://github.com/Aetf/libtsm && cd libtsm
meson setup build/
meson install -C build/
ldconfig
cd ..

git clone --single-branch -b main https://github.com/Aetf/kmscon && cd kmscon
meson setup -Dbackspace_sends_delete=true build/
meson install -C build/
cd ..

systemctl disable getty@tty1.service
systemctl enable kmsconvt@tty1.service

mkdir -p /usr/local/etc/kmscon
echo "font-name=UDEV Gothic DZJPDOCNFLG" > /usr/local/etc/kmscon/kmscon.conf

git clone --single-branch -b main https://github.com/yuru7/udev-gothic && cd udev-gothic
fontforge ./fontforge_script.py --jpdoc --nerd-font --liga --dot-zero
mkdir -p /usr/share/fonts/udevGothic/
cp build/* /usr/share/fonts/udevGothic/
fc-cache -fv
cd ..

## ----- zlib ----- 
git clone --single-branch -b master https://github.com/madler/zlib && cd zlib
LDSHARED="arm-linux-gnueabi-gcc -shared -Wl,-soname,libz.so.1" ./configure --prefix=/usr --shared
while [ ! `make -j$nproc` ]; do
done
make prefix=${SYSROOT}/usr install
ldconfig
cd ..

## ----- openssl ----- 
VERSION=3.6.0
wget https://github.com/openssl/openssl/releases/download/openssl-$VERSION/openssl-$VERSION.tar.gz
tar zxf openssl-$VERSION.tar.gz && cd openssl-$VERSION
./Configure --prefix=/usr --openssldir=/etc/ssl threads zlib no-asm '-Wl,-rpath,$(LIBRPATH)' shared
while [ ! `make -j$nproc` ]; do
done
make INSTALL_PREFIX=${SYSROOT} install
cd ..
## openssh

## ----- build update script ----- 
cat >/repo/update.sh<<'EOT'
#!/bin/bash
cd /repo

cd libtsm
git pull
meson setup build/
meson install -C build/
ldconfig
cd ..

cd kmscon
git pull
meson setup -Dbackspace_sends_delete=true build/
meson install -C build/
cd ..

cd zlib
git pull
LDSHARED="arm-linux-gnueabi-gcc -shared -Wl,-soname,libz.so.1" ./configure --prefix=/usr --shared
make -j$nproc
make prefix=${SYSROOT}/usr install
cd ..

EOT
chmod +x /repo/update.sh

# interactive command
echo "------ run it ------"
echo "/tmp/install-nodejs.sh" > ${HOME}/doit.txt
echo "fish-shell> 'tide configure'" >> ${HOME}/doit.txt
echo "tailscale up" >> ${HOME}/doit.txt
echo "gh auth login" >> ${HOME}/doit.txt
echo "gh auth setup-git" >> ${HOME}/doit.txt

exit 0
