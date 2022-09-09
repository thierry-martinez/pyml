set -ex
sudo apt-get update
sudo apt-get install --yes automake
wget https://github.com/thierry-martinez/stdcompat/releases/download/v19/stdcompat-19.tar.gz
tar -xf stdcompat-19.tar.gz
cd stdcompat-19
./configure
make
