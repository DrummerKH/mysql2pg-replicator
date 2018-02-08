FROM ruby:2.3.3

WORKDIR /var/www/gdm-replicator

RUN apt-get update && \
    apt-get install wget

# Install Postgres repo
RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main' >> /etc/apt/sources.list.d/pgdg.list
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

RUN apt-get update && \
    apt-get install -y \
        postgresql-server-dev-9.5 \
        mysql-client \
        libcurl3 \
        libcurl3-gnutls \
        libcurl4-openssl-dev

# Ruby bundler gem
RUN gem install bundler

# Copy Gem files
COPY Gemfile      /var/www/gdm-replicator
COPY Gemfile.lock /var/www/gdm-replicator

# Install other gems
RUN bundler install

#ENTRYPOINT ["tail" , "-f", "/dev/stdout"]
CMD ["ruby", "replicator.rb", "run"]