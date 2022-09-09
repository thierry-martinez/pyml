FROM ubuntu
COPY init-ci-user.sh .
RUN sh init-ci-user.sh
USER ci
WORKDIR /home/ci
COPY compile-ocaml-4.14.sh .
RUN sh compile-ocaml-4.14.sh
COPY compile-stdcompat.sh .
RUN sh compile-stdcompat.sh
COPY compile-python-3.11.0rc1.sh .
RUN sh compile-python-3.11.0rc1.sh
