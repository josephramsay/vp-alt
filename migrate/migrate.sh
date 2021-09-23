#!/bin/bash

set -e

# Read utility functions
UTIL_SCRIPT=util.sh
. ${UTIL_SCRIPT}
BUILD_SCRIPT=build.sh
META_SCRIPT=meta.sh
DUMP_FILE=${PROJECT_NAME}.dump.sql

DUMMY_USER=${PROJECT}_user
DUMMY_PASS=${PROJECT}_pass
DUMMY_NAME=${PROJECT}_db

# Passwords can be found on the pod in the env vars.
# grep for PASS. It will be something like $DBNAME_PASSWORD. Save
# that in the file below or just write it in directly

#Set args from migrate script if provided
POD_DB_HOST=${1:-postgres-558b5f557d-bkcwn}
POD_DB_NAME=${2:-$DUMMY_NAME}
POD_DB_USER=${3:-$DUMMY_USER}
POD_DB_PASS=${4:-$DUMMY_PASS}


usage () {
    echo "Main entry point to the datbase migration function. Dumps contents of an existing Kubernetes pod \
    database and builds and populates new RDS instance. Additionally builds metastore and trino services to \
    access this database"
    echo "Usage: ./migrate.sh <pod-addr> <db-name> <db-user> <db-pwd-path>"
    echo "   pod-addr: Location of the Pod for kubectl"
    echo "   db-name: Name of the database to connect to"
    echo "   db-user: Name of the database user (with pg_dump access)"
    echo "   db-pwd-path: <db-user> password OR the location of the file where it is stored"
}

if [[ $1 == *"help"* ]]; then
    usage
    exit
fi

trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap finally EXIT

#Check actual value for pass supplied and whether its a path or not
if [[ $POD_DB_PASS != $DUMMY_PASS ]];
then
    if [[ $POD_DB_PASS == *"/"* ]]; 
    then 
        #The provided pass is actually a path
        POD_DB_PASS_PATH=${POD_DB_PASS}
        POD_DB_PASS=$(head -n 1 $POD_DB_PASS_PATH);
    else
        #Assume this is a valid password
        echo ${POD_DB_PASS} > ${DEF_SRC_PASS_PATH}
        chmod 600 ${DEF_SRC_PASS_PATH}
    fi
else
    #No password supplied (ie. its the dummy, use the def path)
    POD_DB_PASS=$(head -n 1 $DEF_SRC_PASS_PATH);
fi

#Setup Destination

# Send; database name, database user, database password (indirectly)
# to new db setup so that naming is consistent for migrating users
ARGS="${POD_DB_NAME} ${POD_DB_USER} ${DEF_DST_PASS_PATH}"
IFS=',' read -ra RES <<< $( . ${BUILD_SCRIPT} ${ARGS} | tail -n 1)

RDS_DB_HOST=${RES[0]}
RDS_DB_NAME=${RES[1]}
RDS_DB_USER=${RES[2]}
RDS_DB_PASSWORD_PATH=${RES[3]}
RDS_DB_PASSWORD=$(cat ${RES[3]})

# Dump from KuDB
kubectl exec -t ${POD_DB_HOST} -- env PGPASSWORD=${POD_DB_PASS} \
    pg_dumpall -h localhost -U ${POD_DB_USER} > ${DUMP_FILE}

# Restore to RDS
PGPASSWORD=${RDS_DB_PASSWORD} psql -U ${RDS_DB_USER} \
    -h ${RDS_DB_HOST} -f ${DUMP_FILE} ${RDS_DB_NAME}
    
# Build Metastore/Trino
ARGS="${RDS_DB_HOST} ${RDS_DB_NAME} ${RDS_DB_PASSWORD_PATH}"
IFS=',' read -ra RES <<< $( . ${META_SCRIPT} ${ARGS} | tail -n 1)