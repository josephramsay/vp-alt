#!/bin/bash

set -e

# Read utility functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
UTIL_SCRIPT=util.sh
. ${SCRIPT_DIR}/${UTIL_SCRIPT}

#Local switches
RDS_DB_HOST=${1:-$PROJECT_NAME.$DEF_HOST_SFX}
RDS_DB_PASS_PATH=${2:-$DEF_RDS_PASS_PATH}
UTIL_SCRIPT=util.sh

PROJECT_DIR=${SCRIPT_DIR}/${PROJECT_NAME}
CLUSTER_CONFIG_FILE=${PROJECT}/cluster-config.yaml


usage () {
    echo "Usage: ./meta.sh <rds-db-host> <pwd-path>"
    echo "   RDS database host name"
    echo "   pwd: <db-user> password or the location of the file where it is stored"
}

if [[ $1 == *"help"* ]]; then
    usage
    exit
fi

trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap finally EXIT


setup_cluster () {  
    # Create clusters and nodegroups if required
    # Its a bit risky to run some of this so commented out for now and will be done manually

    #TODO
    #CLUSTER_EXISTS=$(eksctl get clusters  --output json | jq --arg C "$CLUSTER_NAME" 'any(.[].metadata.name; . == $C)')
    #if [[ ${CLUSTER_EXISTS} != "true" ]]; then
    #    eksctl create cluster --region ${REGION} --name ${CLUSTER_NAME} --version 1.19 --without-nodegroup
    #fi
    aws eks --region ${REGION} update-kubeconfig --name ${CLUSTER_NAME}


    #REQUESTED_NODE_GROUPS=$(yq e -j "[].managedNodeGroups[].name]" ${CLUSTER_CONFIG_FILE})
    #NODE_GROUP_EXISTS=$(eksctl get nodegroups --cluster ${CLUSTER_NAME} --output json | jq --arg R "${REQUESTED_NODE_GROUPS}" '.[].Name | IN($R[]) | any')
    #if [[ ${NODE_GROUP_EXISTS} != "true" ]]; then
        yq e -i ".metadata.name = \"${CLUSTER_NAME}\" | .metadata.region = \"${REGION}\"" ${CLUSTER_CONFIG_FILE}
        eksctl create nodegroup --config-file=${CLUSTER_CONFIG_FILE}
    #fi
}

create_secrets (){
    # Store kubectl secrets
    read_refs
    
    RDS_DB_PASS=$(head -n 1 $RDS_DB_PASS_PATH);
    # Create secrets from RDS variables. 
    # Note: While not particularly secret some values are stored as secrets for 
    # convenience and because the are user configurable 
    kubectl delete secret metatrino-secret --ignore-not-found=true
    kubectl create secret generic metatrino-secret \
    --from-literal=rds-pg-host=${RDS_DB_HOST} \
    --from-literal=rds-pg-name=${RDS_DB_NAME} \
    --from-literal=rds-pg-user=${RDS_DB_USER} \
    --from-literal=rds-pg-pass=${RDS_DB_PASS}
    
    read_creds
    
    # Create secrets from AWS creds sourced from ~/.aws/credentials
    kubectl delete secret s3-vibrant-dragon --ignore-not-found=true
    kubectl create secret generic s3-vibrant-dragon \
    --from-literal=id=${aws_access_key_id} \
    --from-literal=secret=${aws_secret_access_key}
}

install () {
    helm install ${PROJECT_NAME} ${SCRIPT_DIR}/${PROJECT}
}

uninstall () {
    helm uninstall ${PROJECT_NAME}
}

create_secrets
setup_cluster
install

echo 