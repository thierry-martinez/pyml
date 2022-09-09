FROM fedora:rawhide
COPY init-ci-user.sh .
RUN sh init-ci-user.sh
USER ci
WORKDIR /home/ci
COPY install-opam.sh .
RUN sh install-opam.sh
RUN pip install numpy
USER root