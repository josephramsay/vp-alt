#!/bin/bash


CLUSTER_NAME=vp-metatrino
REGION=us-west-1

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
RELEASE_NAME=$(basename $SCRIPT_DIR)
TARGET_NAMESPACE=vpjr
ORIG_NAMESPACE=$(kubectl config view --minify --output 'jsonpath={..namespace}')

if [ -z "$ORIG_NAMESPACE" ]; then
    ORIG_NAMESPACE=$TARGET_NAMESPACE
fi

M_OR_T=${1:-"none"}

reset_namespace() {    
    echo "Switching back to namespace: $ORIG_NAMESPACE"
    #kubectl config set-context --current --namespace=$ORIG_NAMESPACE
}

set_namespace (){
    echo "Switching to namespace: $TARGET_NAMESPACE"
    kubectl config set-context --current --namespace=$TARGET_NAMESPACE
}

usage () {
    echo "Usage: ./init.sh <dry-run>"
    echo "   dry-run: nothing or metastore or trino or both 0-3"
}

reset_error () {
    #reset namespace
    reset_namespace
    #check if exit was on error
    if [[ $? > 0 ]]; 
    then
        echo "${last_command} command failed with exit code $?"
    fi
}

trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap reset_error EXIT


if [[ $M_OR_T == *"help"* ]]; then
    usage
    exit
fi

#Setup Clusters
setup_cluster () {    

    
    CONFIG_FILE=vpjr-metatrino-cluster.yaml

    echo eksctl create cluster --region ${REGION} --name ${CLUSTER_NAME} --version 1.19 --without-nodegroup
    echo aws eks --region ${REGION} update-kubeconfig --name ${CLUSTER_NAME}

    yq e -i ".metadata.name = \"${CLUSTER_NAME}\" | .metadata.region = \"${REGION}\"" ${CONFIG_FILE}
    echo eksctl create nodegroup --config-file=${CONFIG_FILE}
}

#Create Secrets

create_secrets () {
    SEC0=vpjr-sshkey
    SEC1=vpjr-ac1key
    SEC2=vpjr-ac2key

    kubectl create secret generic ${SEC0} --from-file=id_rsa=~/.ssh/secret_access_keys

    cat ~/.sec/secret_access_keys1.csv | \
        tail -n+2 | \
        awk -v s1=${SEC1} 'BEGIN { FS = "," } ; {print "kubectl create secret generic "s1" --from-literal=id="$1" --from-literal=secret="$2}' | \
        bash

    cat ~/.sec/secret_access_keys2.csv | \
        tail -n+2 | \
        awk -v s2=${SEC2} 'BEGIN { FS = "," } ; {print "kubectl create secret generic "s2" --from-literal=id="$1" --from-literal=secret="$2}' | \
        bash
}



helm_deploy_applications (){
    # force upgrade to work, otherwise get 'Error: UPGRADE FAILED: "secrets" has no deployed releases'
    # might be fixed with https://github.com/helm/helm/pull/7653/
    kubectl delete secret sh.helm.release.v1.${RELEASE_NAME}.v1 --ignore-not-found
    # test with:
    #   helm template --debug $RELEASE_NAME $SCRIPT_DIR
    helm upgrade --install --debug $RELEASE_NAME $SCRIPT_DIR

    #helm template name charts/chartname/charts/name --values values.yaml | kubectl apply -f - -l key=value

}


kube_deploy_applications (){
    #bitmap select which ops to run
    if [ $(($M_OR_T&1)) -gt 0 ]; then
        #kubectl apply --filename metastore2.yaml
        helm install --debug ${CLUSTER_NAME} ${SCRIPT_DIR}${CLUSTER_NAME}
        #/home/ubuntu/git/vp-alt/helm/vpjr-metatrino
    fi
    if [ $(($M_OR_T&2)) -gt 0 ]; then
        echo kubectl apply --filename trino2.yaml
    fi


}


setup_cluster
#create_secrets
#set_namespace
#helm_deploy_applications

