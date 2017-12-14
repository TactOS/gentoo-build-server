#!/bin/bash
GBS_DIR=/var/lib/gbs
mkdir -p ${GBS_DIR}/ccache
mkdir -p ${GBS_DIR}/distfiles
mkdir -p ${GBS_DIR}/packages
mkdir -p ${GBS_DIR}/repos

docker pull gentoo/stage3-amd64:latest
docker build docker -t gentoo:gbs
cid=$(docker run --rm -v ${GBS_DIR}/distfiles:/usr/portage/distfiles -v ${GBS_DIR}/repos:/var/db/repos:ro -idt gentoo:gbs)
docker exec ${cid} emerge dev-util/ccache
docker exec ${cid} emerge app-portage/gentoolkit
docker exec ${cid} emerge net-misc/curl
docker commit ${cid} gentoo:gbs
