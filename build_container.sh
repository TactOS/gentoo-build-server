#!/bin/bash
GBS_DIR=/home/user/work/git/gentoo-build-server/gbs
mkdir -p ${GBS_DIR}/repos
mkdir -p ${GBS_DIR}/distfiles

docker pull gentoo/stage3-amd64:latest
docker build docker -t gentoo:gbs
cid=$(docker run --rm -v ${GBS_DIR}/distfiles:/usr/portage/distfiles -v ${GBS_DIR}:/var/db/repos/gentoo:ro -d -i -t gentoo:gbs)
docker exec ${cid} emerge ccache
docker exec ${cid} emerge gentoolkit
docker commit ${cid} gentoo:gbs
