#!/bin/bash

#Set args from migrate script if provided
RDS_DB_NAME=${1:-RDS_DATA2}
RDS_DB_USER=${2:-vp_user}
RDS_DB_PASSWORD_PATH=${3:-~/.aws/rds_data2_password}


echo "db ${RDS_DB_NAME} usr ${RDS_DB_USER} pth ${RDS_DB_PASSWORD_PATH}"
exit 1

#Local switches
TESTRUN="FALSE"
VPC="NONDEFAULT"
NETWORK="PUBLIC"
BLOCK="TRUE"

'''
Currently we have two VPCs that are most easily distinguished by their default status. Read
the one that matches the VPC we want to use. 
NB. This will probably change in the future'''
fetch_vpc_ids () {
    export CLUSTER_NAME=vp-test
    #export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=eksctl-${CLUSTER_NAME}-cluster/VPC" --query "Vpcs[0].VpcId" --output text)
    #echo "VPC ID: ${VPC_ID}"

    if [[ ${VPC} = 'DEFAULT' ]]; then 
        export VPC_ID=$(aws ec2 describe-vpcs --query "Vpcs[?IsDefault].VpcId" --output text)
    elif [[ ${VPC} = 'NONDEFAULT' ]]; then
        export VPC_ID=$(aws ec2 describe-vpcs --query "Vpcs[?IsDefault == \`false\`].VpcId" --output text)
    else 
        echo "VPC identifier must be either DEFAULT or NONDEFAULT"
        exit 1
    fi
}
echo "VPC-ID: ${VPC_ID}" > ~/.aws/vpjr.refs


create_security_group () {
    #SG is based on VPC so security scope implied
    export SECURITY_GROUP_NAME="vpjr-sg-data2"
    export SECURITY_GROUP_DESC="Security Group for Data2"
    #TODO from cr-sec-grp to cr-db-sec-grp?
    #aws rds create-db-security-group \
    aws ec2 create-security-group \
        --description "${SECURITY_GROUP_DESC}" \
        --group-name ${SECURITY_GROUP_NAME} \
        --vpc-id ${VPC_ID}

    export SG_DATA2=$(aws ec2 describe-security-groups \
        --filters Name=group-name,Values=${SECURITY_GROUP_NAME} Name=vpc-id,Values=${VPC_ID} \
        --query "SecurityGroups[0].GroupId" --output text)

}
echo "EC2-SG-ID: ${SG_DATA2}" >> ~/.aws/vpjr.refs

create_subnet_group () {
        
    SFX=`echo ${NETWORK} | cut -c2- | awk '{print tolower($0)}'`
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name, Values=eksctl-${CLUSTER_NAME}-cluster/SubnetP${SFX}*" \
        --query "Subnets[*].SubnetId" --output json | jq -c .)

    export SUBNET_GROUP_NAME="vpjr-sng-data2"
    export SUBNET_GROUP_DESC="Subnet Group for Data2"

    aws rds create-db-subnet-group \
        --db-subnet-group-name ${SUBNET_GROUP_NAME} \
        --db-subnet-group-description "${SUBNET_GROUP_DESC}" \
        --subnet-ids ${SUBNET_IDS}
        
    SNG_VPC_ID=$(aws rds describe-db-subnet-groups \
    --filters Name=group-name,Values=${SUBNET_GROUP_NAME} \
    --query "DBSubnetGroups[0].VpcId" --output text)

    if [[ ${SNG_VPC_ID} != ${VPC_ID} ]];
    then 
        echo "RDS subnet group VPC ID's don't match ${SNG_VPC_ID} != ${VPC_ID}"
        exit 1;
    fi
}

echo "SNG-Name: ${SUBNET_GROUP_NAME}" >> ~/.aws/vpjr.refs


"""Extract CIDR Blocks from desired subnets and user these blocks to create 
Security Group ingress rules""" 
authorise_subnets (){

    RDS_DB_PORT=$1
    SUBNET_CIDR=$(aws ec2 describe-subnets --subnet-ids ${SUBNET_IDS} \
        --query "Subnets[].CidrBlock[]" --output text )

    for cidr in ${SUBNET_CIDR}; do
        aws ec2 authorize-security-group-ingress --group-id ${SG_DATA2} \
            --protocol tcp \
            --port ${RDS_DB_PORT} \
            --cidr ${cidr};
    done
}
echo "SNG-CIDR: ${SUBNET_CIDR}" >> ~/.aws/vpjr.refs

"""
Create PostgreSQL database in RDS using the Security Group created above
and with access to required subnet groups"""
create_rds_database () {
    # generate a password for RDS or use a stored one if available
    #RDS_DB_USER=vp_user
    #RDS_DB_PASSWORD_PATH=~/.aws/rds_data2_password
    if [[ -f $RDS_DB_PASSWORD_PATH ]]; 
    then
        RDS_DB_PASS=$(head -n 1 $RDS_DB_PASSWORD_PATH);
    else
        RDS_DB_PASS="vp_$(date | md5sum | cut -f1 -d' ')";
        echo ${RDS_DB_PASS}  > ${RDS_DB_PASSWORD_PATH}
        chmod 600 ${RDS_DB_PASSWORD_PATH}
    fi

    if [[ ${TESTRUN} = 'TRUE' ]]; 
    then DELETION_PROTECTION="--no-deletion-protection";
    else DELETION_PROTECTION="--deletion-protection";
    fi

    RDS_DB_IDENTIFIER=vpjr-rds-data2
    #RDS_DB_NAME=RDS_DATA2
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
        --vpc-security-group-ids ${SG_DATA2} \
        --master-username ${RDS_DB_USER} \
        --master-user-password ${RDS_DB_PASS} \
        --backup-retention-period ${RDS_DB_RETENTION} \
        --allocated-storage ${RDS_DB_STORAGE} \
        ${DELETION_PROTECTION}

    #Block until the database has been created
    while [[ ${BLOCK} == True && ${RDS_STATUS} != "available" ]];
    do
        RDS_STATUS=$(aws rds describe-db-instances \
            --db-instance-identifier ${RDS_DB_IDENTIFIER} \
            --query "DBInstances[].DBInstanceStatus" \
            --output text)
        sleep 10
    done
}
echo "RDS-ID: ${RDS_DB_IDENTIFIER}" >> ~/.aws/vpjr.refs

clean_up () {
    aws rds delete-db-instance --db-instance-identifier ${RDS_DB_IDENTIFIER} --skip-final-snapshot
    aws rds delete-db-subnet-group --db-subnet-group-name ${SUBNET_GROUP_NAME}
    aws ec2 delete-security-group --group-name ${SG_DATA2}
}

fetch_vpc_ids
create_security_group
create_subnet_group
create_rds_database

#if [[ ${TESTRUN} = 'TRUE' ]]; 
#then clean_up;
#fi

