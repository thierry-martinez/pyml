sudo dnf update --assumeyes
sudo dnf install --assumeyes opam git pip
opam init --disable-sandboxing
opam install stdcompat --yes
