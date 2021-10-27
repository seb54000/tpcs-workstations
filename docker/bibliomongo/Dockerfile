FROM debian:stable-slim
RUN set -x \
    && apt-get update \
    && apt-get install -y libcurl4 procps net-tools openssl ca-certificates iputils-ping \
    && mkdir -p /mongo
COPY mongodb-org-server_4.2.6_amd64.deb /mongo
COPY mongodb-org-shell_4.2.6_amd64.deb  /mongo

RUN cd /mongo \
    && dpkg -i /mongo/mongodb-org-server_4.2.6_amd64.deb \
    && dpkg -i /mongo/mongodb-org-shell_4.2.6_amd64.deb \
    && mkdir -p /data/db /data/var/log/mongodb /data/configdb \
    && chown -R mongodb:mongodb /data/db

COPY mongod.conf /data/configdb

CMD mongod --config /data/configdb/mongod.conf