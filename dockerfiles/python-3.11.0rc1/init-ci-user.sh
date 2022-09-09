set -ex
apt-get update
apt-get install --yes sudo
adduser --disabled-password --gecos ci --shell /bin/bash ci
echo ci ALL=\(ALL\) NOPASSWD:ALL >>/etc/sudoers
