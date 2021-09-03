#!/bin/bash

TESTRUN="FALSE"
NETWORK="PRIVATE"

fetch_vpc_ids () {
    export CLUSTER_NAME=vp-test
    #export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=eksctl-${CLUSTER_NAME}-cluster/VPC" --query "Vpcs[0].VpcId" --output text)
    #echo "VPC ID: ${VPC_ID}"

    VPC_DEF=$(aws ec2 describe-vpcs --query "Vpcs[?IsDefault].VpcId" --output text)
    VPC_NDEF=$(aws ec2 describe-vpcs --query "Vpcs[?IsDefault == \`false\`].VpcId" --output text)

    echo "VPC Default ID: ${VPC_DEF}" #public
    echo "VPC NonDefault ID: ${VPC_NDEF}" #private


    if [[ ${NETWORK} = 'PRIVATE' ]]; 
    then export VPC_ID=${VPC_NDEF};
    else export VPC_ID=${VPC_DEF};
    fi
}


create_security_group () {
    #SG is based on VPC so security scope implied
    export EC2_SECURITY_GROUP_NAME="rds-sg-data2"
    export EC2_SECURITY_GROUP_DESC="RDS Security Group for Data2"
    #TODO from cr-sec-grp to cr-db-sec-grp?
    #aws rds create-db-security-group \
    aws ec2 create-security-group \
        --description "${EC2_SECURITY_GROUP_DESC}" \
        --group-name ${EC2_SECURITY_GROUP_NAME} \
        --vpc-id ${VPC_ID}

    export EC2_SG_Data2=$(aws ec2 describe-security-groups \
        --filters Name=group-name,Values=${EC2_SECURITY_GROUP_NAME} Name=vpc-id,Values=${VPC_ID} \
        --query "SecurityGroups[0].GroupId" --output text)

}
echo "EC2 security group ID: ${EC2_SG_Data2}"
#TODO Write SG to file (as ref for later deletion)

create_subnet_group () {
    PUBLIC_SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name, Values=eksctl-${CLUSTER_NAME}-cluster/SubnetPublic*" \
        --query "Subnets[*].SubnetId" --output json | jq -c .)
    PRIVATE_SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name, Values=eksctl-${CLUSTER_NAME}-cluster/SubnetPrivate*" \
        --query "Subnets[*].SubnetId" --output json | jq -c .)

    if [[ $NETWORK = 'PRIVATE' ]]; 
    then export SUBNET_IDS=${PRIVATE_SUBNET_IDS};
    else export SUBNET_IDS=${PUBLIC_SUBNET_IDS};
    fi

    export RDS_SUBNET_GROUP_NAME="rds-sng-data2"
    export RDS_SUBNET_GROUP_DESC="RDS Subnet Group for Data2"

    aws rds create-db-subnet-group \
        --db-subnet-group-name ${RDS_SUBNET_GROUP_NAME} \
        --db-subnet-group-description "${RDS_SUBNET_GROUP_DESC}" \
        --subnet-ids ${SUBNET_IDS}
        
    RDS_VPC_ID=$(aws rds describe-db-subnet-groups \
    --filters Name=group-name,Values=${RDS_SUBNET_GROUP_NAME} \
    --query "DBSubnetGroups[0].VpcId" --output text)

    if [[ ${RDS_VPC_ID} != ${VPC_ID} ]];
    then 
        echo "RDS subnet group VPC ID's don't match ${RDS_VPC_ID} != ${VPC_ID}"
        exit 1;
    fi
}

create_rds_database () {
    # generate a password for RDS
    RDS_USERNAME=vp_user
    RDS_PASSWORD_PATH=~/.aws/rds_data2_password
    if [[ -f $RDS_PASSWORD_PATH ]]; 
    then
        RDS_PASSWORD=$(head -n 1 $RDS_PASSWORD_PATH);
    else
        RDS_PASSWORD="vp_$(date | md5sum | cut -f1 -d' ')";
        echo ${RDS_PASSWORD}  > ${RDS_PASSWORD_PATH}
        chmod 600 ${RDS_PASSWORD_PATH}
    fi

    if [[ ${TESTRUN} = 'TRUE' ]]; 
    then DELETION_PROTECTION="--no-deletion-protection";
    else DELETION_PROTECTION="--deletion-protection";
    fi

    RDS_DB_IDENTIFIER=vp-rds-data2
    RDS_DB_NAME=RDS_DATA2
    RDS_DB_ENGINE=postgres
    RDS_DB_CLASS=db.t3.micro
    RDS_DB_RETENTION=30
    RDS_DB_STORAGE=20

    aws rds create-db-instance \
        --db-instance-identifier ${RDS_DB_IDENTIFIER} \
        --db-name ${RDS_DB_NAME} \
        --db-instance-class ${RDS_DB_CLASS} \
        --engine ${RDS_DB_ENGINE} \
        --db-subnet-group-name ${RDS_SUBNET_GROUP_NAME} \
        --vpc-security-group-ids ${EC2_SG_Data2} \
        --master-username ${RDS_USERNAME} \
        --master-user-password ${RDS_PASSWORD} \
        --backup-retention-period ${RDS_DB_RETENTION} \
        --allocated-storage ${RDS_DB_STORAGE} \
        ${DELETION_PROTECTION}

    aws rds describe-db-instances \
        --db-instance-identifier ${RDS_DB_IDENTIFIER} \
        --query "DBInstances[].DBInstanceStatus" \
        --output text
}


clean_up () {
    aws rds delete-db-instance --db-instance-identifier ${RDS_DB_IDENTIFIER} --skip-final-snapshot
    aws rds delete-db-subnet-group --db-subnet-group-name ${RDS_SUBNET_GROUP_NAME}
    #TODO from cr-sec-grp to cr-db-sec-grp!
    #aws rds delete-db-security-group --db-security-group-name ${EC2_SG_Data2}
    aws ec2 delete-security-group --group-name ${EC2_SG_Data2}
}

fetch_vpc_ids
create_security_group
#create_subnet_group
#create_rds_database

#if [[ ${TESTRUN} = 'TRUE' ]]; 
#then clean_up;
#fi
