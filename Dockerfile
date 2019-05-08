# use builder image to compile ledisdb (without GCO)
FROM golang:1.9-alpine3.6 as builder

# Setup the Environment
ENV GOPATH=/root/go \
    PATH=${PATH}:/usr/local/go/bin:/root/go/bin \
    GOSU_VERSION=1.10

RUN apk add --no-cache git bash gcc alpine-sdk build-base wget gnupg

#build LedisDB
RUN mkdir -p /root/dist ${GOPATH} \
    && cd ${GOPATH} \
    && mkdir -p src/github.com/siddontang \
    && cd src/github.com/siddontang \
    && git clone https://github.com/siddontang/ledisdb \
    && cd ledisdb \
    && go get -d ./... \
    && go build -i -o /build/bin/ledis-server cmd/ledis-server/* \
    && go build -i -o /build/bin/ledis-cli cmd/ledis-cli/* \
    && go build -i -o /build/bin/ledis-benchmark cmd/ledis-benchmark/* \
    && go build -i -o /build/bin/ledis-dump cmd/ledis-dump/* \
    && go build -i -o /build/bin/ledis-load cmd/ledis-load/* \
    && go build -i -o /build/bin/ledis-repair cmd/ledis-repair/*

# grab gosu for easy step-down from root
# https://github.com/tianon/gosu/releases
RUN set -ex; \
    dpkgArch="$(uname -m)"; \
    if [ "$dpkgArch" == "x86_64" ]; then dpkgArch="amd64"; fi; \
    wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
    wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
    export GNUPGHOME="$(mktemp -d)"; \
    gpg --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
    gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
    chmod +x /usr/local/bin/gosu


# done building - now create a tiny image with a statically linked Ledis
FROM alpine:3.6

# Setup the Environment
ENV GOPATH=/root/go \
    PATH=${PATH}:/usr/local/go/bin:/root/go/bin

ADD config/config-docker.toml /config.toml

COPY --from=builder /build/bin/ledis-* /bin/
COPY --from=builder /usr/local/bin/gosu /bin/

RUN addgroup -S ledis && \
    adduser -S -G ledis ledis && \
    mkdir /datastore && \
    chown ledis:ledis /datastore && \
    chmod 444 /config.toml && \
    gosu nobody true

VOLUME /datastore

ADD entrypoint.sh /bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]

EXPOSE 6380 11181

CMD ["ledis-server", "--config=/config.toml"]
