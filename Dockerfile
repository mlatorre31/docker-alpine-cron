FROM jfloff/alpine-python:3.8-slim

RUN  echo "http://dl-cdn.alpinelinux.org/alpine/v$ALPINE_VERSION/community" >> /etc/apk/repositories ;

COPY build-requirements.txt /
COPY apk-requirements.txt /
COPY requirements.txt /

RUN /entrypoint.sh \
    -a dcron

RUN \
    echo "**** setup dcron ****" && \
    mkdir -p /var/log/cron && \
    mkdir -m 0644 -p /var/spool/cron/crontabs && \
    touch /var/log/cron/cron.log && \
    mkdir -m 0644 -p /etc/cron.d && \
    echo "**** install app ****" && \
    mkdir -p \
    /app/

COPY /scripts/* /

ENTRYPOINT ["/docker-entry.sh"]
CMD ["/docker-cmd.sh"]
