FROM gentoo/stage3-amd64:latest

RUN rm -rf /etc/portage/package.use
RUN rm -rf /etc/portage/package.mask

RUN rm -rf /etc/portage/make.profile
RUN mkdir -p /etc/portage/make.profile
COPY parent /etc/portage/make.profile

RUN mkdir -p /etc/portage/repos.conf
COPY gentoo.conf /etc/portage/repos.conf

RUN mkdir -p /var/db/repos/gentoo

RUN mkdir -p /usr/portage

COPY make.conf /etc/portage
