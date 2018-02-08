#!/usr/bin/env bash

echo 'Waiting while mysql server is up'
./docker/wait-for-it.sh ${MYSQL_HOSTNAME}:${MYSQL_PORT} -- echo 'Mysql is up'

dbexist=`mysql -p${MYSQL_PASSWORD} -u ${MYSQL_USERNAME} -h ${MYSQL_HOSTNAME} --port ${MYSQL_PORT} -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = 'transactions'"`

if [ -z "$dbexist" ]; then
    mysql -p${MYSQL_PASSWORD} -u ${MYSQL_USERNAME} -h ${MYSQL_HOSTNAME} --port ${MYSQL_PORT} -e 'CREATE DATABASE transactions'
    mysql -p${MYSQL_PASSWORD} -u ${MYSQL_USERNAME} -h ${MYSQL_HOSTNAME} --port ${MYSQL_PORT} -D transactions < docker/mysql/transactions.sql
fi

echo 'RabbitMQ preparations'
./docker/wait-for-it.sh ${RABBITMQ_HOSTNAME}:15672 -- echo 'RabbitMQ is up'

echo 'Download rabbitmq admin'
curl http://${RABBITMQ_HOSTNAME}:15672/cli/rabbitmqadmin > ../rbmqadmin.sh
chmod +x ../rbmqadmin.sh

echo 'Create REPLICATOR vhost'
../rbmqadmin.sh -u ${RABBITMQ_USERNAME} -p ${RABBITMQ_PASSWORD} -H ${RABBITMQ_HOSTNAME} declare vhost name=${RABBITMQ_VHOST}

echo 'Add permissions to REPLICATOR vhost'
../rbmqadmin.sh -u ${RABBITMQ_USERNAME} -p ${RABBITMQ_PASSWORD} -H ${RABBITMQ_HOSTNAME} declare permission vhost=${RABBITMQ_VHOST} user=${RABBITMQ_USERNAME} configure=.* write=.* read=.*
