#!/bin/bash

# This script is the main entry point to the datbase migration function. 
# It dumps contents of an existing Kubernetes pod PostgreSQL database and 
# builds + populates a new RDS PostgreSQL instance. Additionally this script
# calls a a function to build metastore and trino services that will to 
# access this new RDS database

set -e

# SETUP

# Read utility functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
UTIL_SCRIPT=util.sh
. ${SCRIPT_DIR}/${UTIL_SCRIPT}
# Set script names
BUILD_SCRIPT=build.sh
META_SCRIPT=meta.sh
DUMP_FILE=${PROJECT_NAME}.dump.sql

# Set dummy user/pass and database names
DUMMY_USER=${PROJECT}_user
DUMMY_PASS=${PROJECT}_pass
DUMMY_NAME=${PROJECT}

# Passwords can be found in the original Ku pod environment vars.
# grep for PASS. It will be something like $DBNAME_PASSWORD. Include 
# it as an argument to this script $4, save it to the file indicated 
# by the POD_DB_PASS_PATH var or write it in directly

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
trap error_report ERR
trap finally EXIT

# Check actual value for pass supplied and whether its a path or not
if [[ $POD_DB_PASS != $DUMMY_PASS ]];
then
    if [[ $POD_DB_PASS == *"/"* ]]; 
    then 
        #The provided pass is probably a path so read the value stored there
        POD_DB_PASS_PATH=${POD_DB_PASS}
        POD_DB_PASS=$(head -n 1 $POD_DB_PASS_PATH);
    else
        #We assume this is a valid password and store it in the default path
        echo ${POD_DB_PASS} > ${DEF_POD_PASS_PATH}
        chmod 600 ${DEF_POD_PASS_PATH}
    fi
else
    #If no password supplied (ie. its the dummy) try to read the default path
    POD_DB_PASS=$(head -n 1 $DEF_POD_PASS_PATH);
fi


capture_namespace
switch_namespace

# SETUP DESTINATION

# Send pod; database name, database user, database password (indirectly)
# to new RDS DB setup script so that naming is consistent for migrating users
ARGS="${POD_DB_NAME} ${POD_DB_USER} ${DEF_DST_PASS_PATH}"
IFS=',' read -ra RES <<< $( . ${BUILD_SCRIPT} ${ARGS} | tail -n 1)

# Read back the RDS; host, db name, user name and password path. 
# If these weren't sent as args they will have been set in the build script
RDS_DB_HOST=${RES[0]}
RDS_DB_NAME=${RES[1]}
RDS_DB_USER=${RES[2]}
RDS_DB_PASSWORD_PATH=${RES[3]}
RDS_DB_PASSWORD=$(cat ${RES[3]})

# TRANSFER DATA

# Perform a pg_dumpall from the Kubernetes pod database
kubectl exec -t ${POD_DB_HOST} -- env PGPASSWORD=${POD_DB_PASS} \
    pg_dumpall -h localhost -U ${POD_DB_USER} > ${DUMP_FILE}

# Restore the dumped file to the newly minted RDS database
PGPASSWORD=${RDS_DB_PASSWORD} psql -U ${RDS_DB_USER} \
    -h ${RDS_DB_HOST} -f ${DUMP_FILE} ${RDS_DB_NAME}
    
# BUILD ACCESS SERVICES

# Call the meta script to build a Metastore/Trino combo
ARGS="${RDS_DB_HOST} ${RDS_DB_PASSWORD_PATH}"
IFS=',' read -ra RES <<< $( . ${META_SCRIPT} ${ARGS} | tail -n 1)

reset_namespace