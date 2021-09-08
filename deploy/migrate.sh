#!/bin/bash

set -e

PREFIX=metastore
DUMP_FILE=${PREFIX}.dump.sql
BUILD_SCRIPT=build.sh
DUMMY_PASS=${PREFIX}_pass

# Passwords can be found on the pod in the env vars.
# grep for PASS. It will be something like $DBNAME_PASSWORD. Save
# that in the file below or just write it in directly

#Set args from migrate script if provided
SRC_POD_ADDR=${1:-postgres-558b5f557d-bkcwn}
SRC_PG_DBNAME=${2:-$prefix}
SRC_PG_USER=${3:-$PREFIX_user}
SRC_PG_PASS=${4:-$DUMMY_PASS}
    

usage () {
    echo "Usage: ./migrate.sh <pod-addr> <db-name> <db-user> <pwd-path>"
    echo "   pod-addr: Location of the Pod for kubectl"
    echo "   db-name: Name of the database to connect to"
    echo "   db-user: Name of the database user (with pg_dump access)"
    echo "   pwd: <db-user> password or the location of the file where it is stored"
}

error () {
    if [[ $? > 0 ]]; 
    then
        'echo "\"${last_command}\" command failed with exit code $?."'
    fi
}

trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap error EXIT

if [[ $SRC_POD_ADDR == *"help"* ]]; then
    usage
    exit
fi

#Check actual value for pass supplied and whether its a path or not
if [[ $SRC_PG_PASS != $DUMMY_PASS && $SRC_PG_PASS == *"/"* ]]; 
then 
    SRC_PG_PASS_PATH=${SRC_PG_PASS}
    SRC_PG_PASS=$(head -n 1 $SRC_PG_PASS);
else
    SRC_PG_PASS_PATH=$~/.aws/pod_pg_password
    echo ${SRC_PG_PASS}  > ${SRC_DB_PASS_PATH}
    chmod 600 ${SRC_DB_PASS_PATH}
fi


#Setup Destination
DST_PG_PASS_PATH=~/.aws/rds_pg_password
# Send; database name, database user, database password (indirectly)
# to new db setup so that naming is consistent for migrating users
ARGS="${SRC_PG_DBNAME} ${SRC_PG_USER} ${DST_PG_PASS_PATH}"
IFS=',' read -ra RES <<< $( . ${BUILD_SCRIPT} ${ARGS} | tail -n 1)

DST_PG_HOST=${RES[0]}
DST_PG_DBNAME=${RES[1]}
DST_PG_USER=${RES[2]}
DST_PG_PASS=$(cat ${RES[3]})

# Dump
kubectl exec -t ${SRC_POD_ADDR} -- env PGPASSWORD=${SRC_PG_PASS} \
    pg_dumpall -h localhost -U ${SRC_PG_USER} > ${DUMP_FILE}

# Restore
PGPASSWORD=${DST_PG_PASS} psql -U ${DST_PG_USER} \
    -h ${DST_PG_HOST} -f ${DUMP_FILE} ${DST_PG_DBNAME}
    
