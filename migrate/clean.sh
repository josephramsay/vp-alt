#!/bin/bash

set -e

# Read utility functions
UTIL_SCRIPT=util.sh
. ${SCRIPT_DIR}/${UTIL_SCRIPT}

#Set args from migrate script if provided
RDS_DB_IDENTIFIER=${1}
SUBNET_GROUP_NAME=${2}
SECURITY_GROUP_NAME=${3}
CLEAN_MT=${4:-FALSE}

usage () {
    echo "Usage: ./clean.sh <db-id> <subnet-grp> <sec-grp>"
    echo "   db-identifier: Name of the RDS database to delete"
    echo "   subnet-group: Name of the associated subnet group to delete"
    echo "   security-group: Name of the associated security group to delete"
    echo "   [delete-flag]: Also delete metastore+trino (TRUE/FALSE)"
}

if [[ $1 == *"help"* ]]; then
    usage
    exit
fi

trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap finally EXIT

clean_rds () {
    # If the identifier arguments haven't been provided as args read them from the refs file
    if [[ -z ${RDS_DB_IDENTIFIER} && -z ${SUBNET_GROUP_NAME} && -z ${SECURITY_GROUP_NAME} ]];
    then read_refs;
    fi

    aws rds delete-db-instance --db-instance-identifier ${RDS_DB_IDENTIFIER} \
        --skip-final-snapshot --delete-automated-backups
    aws rds wait db-instance-deleted --db-instance-identifier ${RDS_DB_IDENTIFIER}
    aws rds delete-db-subnet-group --db-subnet-group-name ${SUBNET_GROUP_NAME}
    aws ec2 delete-security-group --group-name ${SECURITY_GROUP_NAME}


}

clean_kube () {
    helm uninstall ${PROJECT_NAME}
}

clean_rds

if [[ ${CLEAN_MT == 'TRUE' }]];then
    clean_kube
fi