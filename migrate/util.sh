#Source this file for common constants and functions


PREFIX=vp-di
REGION=us-west-1
CLUSTER_NAME=vp-test
PROJECT=metastore

REFS=~/.aws/${PREFIX}.refs
CREDS=~/.aws/credentials
DEF_POD_PASS_PATH=~/.aws/pod_db_password
DEF_RDS_PASS_PATH=~/.aws/rds_db_password

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
RELEASE_NAME=$(basename $SCRIPT_DIR)

PROJECT_NAME=${PREFIX}-${PROJECT}
DEF_HOST_SFX=cl7kxrjemfld.us-west-1.rds.amazonaws.com

TARGET_NAMESPACE=default

write_refs () {
    # Write K=V to refs file
    if [[ ${1} == "NEW" && -n ${2} ]]; 
    then eval 'echo $2=$'$2 > ${REFS};
    else eval 'echo $1=$'$1 >> ${REFS};
    fi
}

read_refs () {
    # Source the refs file
    . ${1:-$REFS}
}

read_creds () {
    # Read AWS access keys
    aws_access_key_id=`cat ${1:-$CREDS} | grep _id | cut -f2 -d"="`
    aws_secret_access_key=`cat ${1:-$CREDS} | grep _sec | cut -f2 -d"="`
}

capture_namespace () {
    # Read namespace and save so we can switch back to it when done
    ORIG_NAMESPACE=$(kubectl config view --minify --output 'jsonpath={..namespace}')
    if [ -z "$ORIG_NAMESPACE" ]; then
        ORIG_NAMESPACE=$TARGET_NAMESPACE
    fi
    write_refs ORIG_NAMESPACE
    write_refs TARGET_NAMESPACE
}

switch_namespace () {
    # Switch to the target namespace
    echo "Switching to namespace: ${TARGET_NAMESPACE}"
    kubectl config set-context --current --namespace=${TARGET_NAMESPACE}
}

reset_namespace() {
    # Switch back to the previous namespace
    echo "Switching back to namespace: $ORIG_NAMESPACE"
    echo kubectl config set-context --current --namespace=$ORIG_NAMESPACE
}

error_report() {
    echo "Error on line $1"
}

finally () {
    # On exit trap any errors and report the reset back to original namespace
    if [[ $? > 0 ]]; 
    then
        echo "${last_command} command failed with exit code $?"
    fi    
    reset_namespace
}
