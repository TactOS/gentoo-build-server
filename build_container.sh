#!/bin/bash
GBS_DIR=/var/lib/gbs
mkdir -p ${GBS_DIR}/ccache
mkdir -p ${GBS_DIR}/distfiles
mkdir -p ${GBS_DIR}/packages
mkdir -p ${GBS_DIR}/repos
mkdir -p ${GBS_DIR}/logs

docker pull gentoo/stage3-amd64:latest
docker build docker -t gentoo:gbs
cid=$(docker run --rm -v ${GBS_DIR}/distfiles:/usr/portage/distfiles -v ${GBS_DIR}/repos:/var/db/repos:ro --cap-add=SYS_PTRACE -idt gentoo:gbs)
docker exec ${cid} emerge dev-util/ccache
docker exec ${cid} emerge app-portage/gentoolkit
docker exec ${cid} emerge net-misc/curl
docker exec ${cid} sh -c "echo =app-admin/mongo-tools-3.4.10 ~amd64 >> /etc/portage/package.accept_keywords"
docker exec ${cid} sh -c "echo =dev-db/mongodb-3.4.10 ~amd64 >> /etc/portage/package.accept_keywords"
docker exec ${cid} emerge \=dev-db/mongodb-3.4.10
docker exec ${cid} rm /etc/portage/package.accept_keywords
docker commit ${cid} gentoo:gbs
docker kill ${cid}
