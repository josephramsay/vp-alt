#!/bin/bash

TESTRUN="TRUE"

if [ $TESTRUN = 'TRUE' ]; 
then DELETION_PROTECTION="--no-deletion-protection";
else DELETION_PROTECTION="--deletion-protection";
fi

export CLUSTER_NAME=vp-test
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=eksctl-${CLUSTER_NAME}-cluster/VPC" --query "Vpcs[0].VpcId" --output text)
echo "VPC ID: ${VPC_ID}"

create_security_group () {
    
    export EC2_SECURITY_GROUP_NAME="rds-sg-data2"
    export EC2_SECURITY_GROUP_DESC="RDS Security Group for Data2"
    
    aws ec2 create-security-group \
        --description "${EC2_SECURITY_GROUP_DESC}" \
        --group-name ${EC2_SECURITY_GROUP_NAME} \
        --vpc-id ${VPC_ID}

    export EC2_SecGrp_Data2_ID=$(aws ec2 describe-security-groups \
        --filters Name=group-name,Values=${EC2_SECURITY_GROUP_NAME} Name=vpc-id,Values=${VPC_ID} \
        --query "SecurityGroups[0].GroupId" --output text)

}
echo "EC2 security group ID: ${EC2_SecGrp_Data2_ID}"

create_subnet_group () {
    export PUBLIC_SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name, Values=eksctl-${CLUSTER_NAME}-cluster/SubnetPublic*" \
        --query "Subnets[*].SubnetId" --output json | jq -c .)

    export RDS_SUBNET_GROUP_NAME="rds-sng-data2"
    export RDS_SUBNET_GROUP_DESC="RDS Subnet Group for Data2"

    aws rds create-db-subnet-group \
        --db-subnet-group-name ${RDS_SUBNET_GROUP_NAME} \
        --db-subnet-group-description "${RDS_SUBNET_GROUP_DESC}" \
        --subnet-ids ${PUBLIC_SUBNET_IDS}
        
    export RDS_SubnetGrp_Data2_VPC_ID=$(aws rds describe-db-subnet-groups \
    --filters Name=group-name,Values=${RDS_SUBNET_GROUP_NAME} \
    --query "DBSubnetGroups[0].VpcId" --output text)
}
echo "RDS subnet group VPC ID: ${RDS_SubnetGrp_Data2_VPC_ID}"

create_rds_database () {
    # generate a password for RDS
    export RDS_USERNAME=vp.user
    export RDS_PASSWORD="vp.$(date | md5sum  |cut -f1 -d' ')"
    export RDS_PASSWORD_PATH=~/.aws/rds_data2_password
    echo ${RDS_PASSWORD}  > ${RDS_PASSWORD_PATH}
    chmod 600 ${RDS_PASSWORD_PATH}


    RDS_DB_IDENTIFIER=vp-rds-data2-id
    RDS_DB_NAME=RDS_DATA2
    RDS_DB_ENGINE=postgres
    RDS_DB_CLASS=db.t3.micro
    RDS_DB_RETENTION=30
    RDS_DB_STORAGE=20

    aws rds create-db-instance \
        --db-instance-identifier ${RDS_DB_IDENTIFIER} \
        --db-name ${RDS_DB_NAME} \
        --db-instance-class ${RDS_DB_CLASS} \
        --engine ${RDS_ENGINE} \
        --db-subnet-group-name ${RDS_SUBNET_GROUP_NAME} \
        --vpc-security-group-ids ${RDS_SG} \
        --master-username ${RDS_USERNAME} \
        --master-user-password ${RDS_PASSWORD} \
        --backup-retention-period ${RDS_DB_RETENTION} \
        --allocated-storage ${RDS_DB_STORAGE} \
        ${DELETION_PROTECTION}

    aws rds describe-db-instances \
        --db-instance-identifier rds-eks-airflow \
        --query "DBInstances[].DBInstanceStatus" \
        --output text
}


clean_up () {
    aws rds delete-db-instance --db-instance-identifier ${RDS_DB_IDENTIFIER}
    aws rds delete-db-subnet-group --db-subnet-group-name ${RDS_SUBNET_GROUP_NAME}
    aws ec2 delete-security-group --group-id ${EC2_SecGrp_Data2_ID}
}

create_security_group
create_subnet_group
create_rds_database

if [ $TESTRUN = 'TRUE' ]; 
then clean_up;
fi
