set -ex
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive \
  apt-get install --yes wget gcc make
wget https://github.com/ocaml/ocaml/archive/refs/tags/4.14.0.tar.gz
tar -xf 4.14.0.tar.gz
cd ocaml-4.14.0
./configure
make
sudo make install
