#!/bin/bash

set -e

# Read utility functions
UTIL_SCRIPT=util.sh
. ${SCRIPT_DIR}/${UTIL_SCRIPT}

PROTECT="FALSE"
#choose the nodefault vpcs
VPC="NONDEFAULT"
#choose the first vpc returned...
VPCI=0
NETWORK="PUBLIC"
BLOCK="TRUE"

#Set args from migrate script if provided
RDS_DB_NAME=${1:-metastore_db}
RDS_DB_USER=${2:-metastore_user}
RDS_DB_PASS_PATH=${3:-$DEF_RDS_PASS_PATH}

usage () {
    echo "Usage: ./build.sh <db-name> <db-user> <pwd-path>"
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

# Currently we have three (no longer 2) VPCs that are most easily distinguished by their default status. Read
# the one that matches the VPC we want to use. 
# NB. This will probably change in the future
fetch_vpc_ids () {
    export CLUSTER_NAME=vp-test

    if [[ ${VPC} = 'DEFAULT' ]]; then 
        VPC_ID=$(aws ec2 describe-vpcs --query "Vpcs[?IsDefault].VpcId" --output text)
    elif [[ ${VPC} = 'NONDEFAULT' ]]; then
        VPC_ID=$(aws ec2 describe-vpcs --query "Vpcs[?IsDefault == \`false\`].VpcId" --output text)
    else 
        echo "VPC identifier must be either DEFAULT or NONDEFAULT"
        exit 1
    fi
    #comma sep the vpc list and write it to refs
    VPC_ID_CS=$(awk '{gsub(/[ ]+/,",")}1' <<<${VPC_ID})
    write_refs NEW VPC_ID_CS
    #copy the vpcs to an array
    VPC_ID_A=( $VPC_ID )
}

create_security_group () {
    #SG is based on VPC so security scope implied
    SECURITY_GROUP_NAME="${PREFIX}-sg-${PROJECT}"
    SECURITY_GROUP_DESC="Security Group for ${PROJECT}"
    #TODO from cr-sec-grp to cr-db-sec-grp?
    #aws rds create-db-security-group \
    aws ec2 create-security-group \
        --description "${SECURITY_GROUP_DESC}" \
        --group-name ${SECURITY_GROUP_NAME} \
        --vpc-id ${VPC_ID_A[$VPCI]}

    SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
        --filters Name=group-name,Values=${SECURITY_GROUP_NAME} Name=vpc-id,Values=${VPC_ID_A[$VPCI]} \
        --query "SecurityGroups[0].GroupId" --output text)

    write_refs SECURITY_GROUP_ID
    write_refs SECURITY_GROUP_NAME
}

create_subnet_group () {
        
    SFX=`echo ${NETWORK} | cut -c2- | awk '{print tolower($0)}'`
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name, Values=eksctl-${CLUSTER_NAME}-cluster/SubnetP${SFX}*" \
        --query "Subnets[*].SubnetId" --output json | jq -c .)

    SUBNET_GROUP_NAME="${PREFIX}-sng-${PROJECT}"
    SUBNET_GROUP_DESC="Subnet Group for ${PROJECT}"

    aws rds create-db-subnet-group \
        --db-subnet-group-name ${SUBNET_GROUP_NAME} \
        --db-subnet-group-description "${SUBNET_GROUP_DESC}" \
        --subnet-ids ${SUBNET_IDS}
        
    SNG_VPC_ID=$(aws rds describe-db-subnet-groups \
    --filters Name=group-name,Values=${SUBNET_GROUP_NAME} \
    --query "DBSubnetGroups[0].VpcId" --output text)

    if [[ ${SNG_VPC_ID} != ${VPC_ID_A[$VPCI]} ]];
    then 
        echo "RDS subnet group VPC ID's don't match ${SNG_VPC_ID} != ${VPC_ID_A[$VPCI]}"
        exit 1;
    fi

    write_refs SUBNET_GROUP_NAME
}

# Extract CIDR Blocks from desired subnets and user these blocks to create 
# Security Group ingress rules
authorise_subnets (){

    RDS_DB_PORT=$1
    SUBNET_CIDR=$(aws ec2 describe-subnets --subnet-ids ${SUBNET_IDS} \
        --query "Subnets[].CidrBlock[]" --output text )

    for cidr in ${SUBNET_CIDR}; do
        aws ec2 authorize-security-group-ingress --group-id ${SECURITY_GROUP_ID} \
            --protocol tcp \
            --port ${RDS_DB_PORT} \
            --cidr ${cidr};
    done
    SUBNET_CIDR=$(awk '{gsub(/[ ]+/,",")}1' <<<${SUBNET_CIDR})

    #TODO Can't read this back as is, trim and comma sep
    write_refs SUBNET_CIDR
}

# Create PostgreSQL database in RDS using the Security Group created above
# and with access to required subnet groups
create_rds_database () {
    # generate a password for RDS or use a stored one if available
    #RDS_DB_USER=vp_user
    #RDS_DB_PASS_PATH=~/.aws/rds_data2_password
    if [[ -f $RDS_DB_PASS_PATH ]]; 
    then
        RDS_DB_PASS=$(head -n 1 $RDS_DB_PASS_PATH);
    else
        RDS_DB_PASS="${PREFIX}_$(date | md5sum | cut -f1 -d' ')";
        echo ${RDS_DB_PASS}  > ${RDS_DB_PASS_PATH}
        chmod 600 ${RDS_DB_PASS_PATH}
    fi

    if [[ ${PROTECT} = 'TRUE' ]]; 
    then DELETION_PROTECTION="--deletion-protection";
    else DELETION_PROTECTION="--no-deletion-protection";
    fi

    RDS_DB_IDENTIFIER=${PREFIX}-rds-${PROJECT}
    RDS_DB_ENGINE=postgres
    RDS_DB_PORT=5432
    RDS_DB_CLASS=db.t3.micro
    RDS_DB_RETENTION=30
    RDS_DB_STORAGE=20

    authorise_subnets ${RDS_DB_PORT}

    #Create the RDS instance
    aws rds create-db-instance \
        --db-instance-identifier ${RDS_DB_IDENTIFIER} \
        --db-name ${RDS_DB_NAME} \
        --db-instance-class ${RDS_DB_CLASS} \
        --engine ${RDS_DB_ENGINE} \
        --db-subnet-group-name ${SUBNET_GROUP_NAME} \
        --vpc-security-group-ids ${SECURITY_GROUP_ID} \
        --master-username ${RDS_DB_USER} \
        --master-user-password ${RDS_DB_PASS} \
        --backup-retention-period ${RDS_DB_RETENTION} \
        --allocated-storage ${RDS_DB_STORAGE} \
        ${DELETION_PROTECTION}

    aws rds wait db-instance-available --db-instance-identifier ${RDS_DB_IDENTIFIER}

    export RDS_DB_HOST=$(aws rds describe-db-instances \
            --db-instance-identifier ${RDS_DB_IDENTIFIER} \
            --query "DBInstances[].Endpoint.Address" \
            --output text)

    write_refs RDS_DB_IDENTIFIER
    write_refs RDS_DB_HOST
    write_refs RDS_DB_NAME
    write_refs RDS_DB_USER
}

fetch_vpc_ids
create_security_group
create_subnet_group
create_rds_database

# Return the hostname and the user params which might be different is no src was provided
echo ${RDS_DB_HOST},${RDS_DB_NAME},${RDS_DB_USER},${RDS_DB_PASS_PATH}


