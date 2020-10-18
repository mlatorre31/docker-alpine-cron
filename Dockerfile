#FROM frolvlad/alpine-python3
FROM jfloff/alpine-python:3.6

RUN \
    echo "**** install build packages ****" && \
    apk add --no-cache --virtual=build-dependencies \
    gcc \
    musl-dev \
    libffi-dev \
    openssl-dev \
    libressl-dev \
    libxml2-dev && \
#    python3-dev && \
    echo "**** install packages ****" && \
    echo "http://dl-cdn.alpinelinux.org/alpine/v$ALPINE_VERSION/community" >> /etc/apk/repositories ;\
    apk add --no-cache \
    dcron \
    jpeg-dev \
    libxslt-dev && \
    echo "install pip packages ****" && \
    pip install -U \
    apprise \
    pdfplumber \
    scrapy && \
    echo "**** setup dcron ****" && \
    mkdir -p /var/log/cron && \
    mkdir -m 0644 -p /var/spool/cron/crontabs && \
    touch /var/log/cron/cron.log && \
    mkdir -m 0644 -p /etc/cron.d && \
    echo "**** install app ****" && \
    mkdir -p \
    /app/ && \
    echo "**** cleanup ****" && \
    apk del --purge \
    build-dependencies

COPY /scripts/* /

ENTRYPOINT ["/docker-entry.sh"]
CMD ["/docker-cmd.sh"]
