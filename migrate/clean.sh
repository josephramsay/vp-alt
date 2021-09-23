#!/bin/bash

set -e

# Read utility functions
UTIL_SCRIPT=util.sh
. ${UTIL_SCRIPT}

#Set args from migrate script if provided
RDS_DB_IDENTIFIER=${1}
SUBNET_GROUP_NAME=${2}
SECURITY_GROUP_NAME=${3}

usage () {
    echo "Usage: ./clean.sh <db-id> <subnet-grp> <sec-grp>"
    echo "   db-name: Name of the database to instantiate"
    echo "   db-user: Name of the initital database user"
    echo "   pwd-path: Location of the file to store the password for <db-user>"
}

if [[ $1 == *"help"* ]]; then
    usage
    exit
fi

trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap finally EXIT

clean_up () {
    # If the identifier arguments haven't been provided as args read them from the refs file
    if [[ -z ${RDS_DB_IDENTIFIER} && -z ${SUBNET_GROUP_NAME} && -z ${SECURITY_GROUP_NAME} ]];
    then read_refs;
    fi

    aws rds delete-db-instance --db-instance-identifier ${RDS_DB_IDENTIFIER} \
        --skip-final-snapshot --delete-automated-backups
    aws rds wait db-instance-deleted --db-instance-identifier ${RDS_DB_IDENTIFIER}
    aws rds delete-db-subnet-group --db-subnet-group-name ${SUBNET_GROUP_NAME}
    aws ec2 delete-security-group --group-id ${SECURITY_GROUP_ID}
}

clean_up