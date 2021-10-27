FROM debian:stable-slim
RUN set -x \
    && apt-get update \
    && apt-get install -y libcurl4 procps net-tools openssl ca-certificates iputils-ping unzip xz-utils \
    && mkdir -p /app /app/bibliotheque
COPY node-v12.16.3-linux-x64.tar.xz /app
COPY bibliotheque /app/bibliotheque
COPY docker-entrypoint.sh /usr/local/bin/

ENV PATH /app/node-v12.16.3-linux-x64/bin:$PATH

RUN cd /app \
    && tar -xJC /app -f node-v12.16.3-linux-x64.tar.xz \
    && cd /app/bibliotheque  \
    && npm install

EXPOSE 3000/tcp

ENTRYPOINT ["docker-entrypoint.sh"]
