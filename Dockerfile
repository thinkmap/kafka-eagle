FROM openjdk:8-alpine3.9

ENV KE_HOME=/opt/kafka-eagle
ENV EAGLE_VERSION=2.1.0

ADD entrypoint.sh /usr/bin

# 设置时区
RUN apk --no-cache add tzdata \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

RUN sed -i 's#dl-cdn.alpinelinux.org#mirrors.aliyun.com#g' /etc/apk/repositories && \
    apk --update add wget curl gettext tar unzip bash sqlite && \
    apk update --no-cache ; rm -rf /var/cache/apk/* && \
    mkdir /opt/kafka-eagle -p && cd /opt && \
    wget https://github.com/smartloli/kafka-eagle-bin/archive/v${EAGLE_VERSION}.tar.gz && \
    tar zxvf v${EAGLE_VERSION}.tar.gz -C kafka-eagle --strip-components 1 && rm -f v${EAGLE_VERSION}.tar.gz && \
    cd kafka-eagle;tar zxvf efak-web-${EAGLE_VERSION}-bin.tar.gz --strip-components 1 && rm -f efak-web-${EAGLE_VERSION}-bin.tar.gz  && \
    chmod +x /opt/kafka-eagle/bin/ke.sh && \
    mkdir -p /hadoop/kafka-eagle/db



EXPOSE 8048 8080

ENTRYPOINT ["entrypoint.sh"]

WORKDIR /opt/kafka-eagle
