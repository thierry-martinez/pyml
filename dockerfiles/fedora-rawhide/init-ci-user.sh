set -ex
adduser --shell /bin/bash ci
echo ci ALL=\(ALL\) NOPASSWD:ALL >>/etc/sudoers
