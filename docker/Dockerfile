FROM ubuntu:latest

WORKDIR /var/www/gdm-replicator

RUN apt-get update && \
    apt-get install -y \
        mysql-client \
        curl \
        python3

RUN ln /usr/bin/python3 /usr/bin/python

ADD docker/deploy.sh /tmp/deploy.sh
RUN chmod +x /tmp/deploy.sh

ENTRYPOINT ["/tmp/deploy.sh"]