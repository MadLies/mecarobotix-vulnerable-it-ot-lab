FROM bitnamilegacy/openldap:2.6.10-debian-12-r4

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends ldap-utils iproute2 gosu \
    && rm -rf /var/lib/apt/lists/*
