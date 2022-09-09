set -ex
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive \
  apt-get install --yes wget xz-utils gcc pkg-config make zlib1g-dev \
    libssl-dev libffi-dev
wget https://www.python.org/ftp/python/3.11.0/Python-3.11.0rc1.tar.xz
tar -xf Python-3.11.0rc1.tar.xz
cd Python-3.11.0rc1
./configure --enable-optimizations --enable-shared --with-openssl
make
sudo make install
sudo LD_LIBRARY_PATH=/usr/local/lib pip3 install numpy
