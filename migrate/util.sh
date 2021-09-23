#Source this file for common constants and functions


REFS=~/.aws/vpjr.refs
CREDS=~/.aws/credentials
DEF_POD_PASS_PATH=~/.aws/pod_db_password
DEF_RDS_PASS_PATH=~/.aws/rds_db_password

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

PREFIX=vp-di
PROJECT=metastore
PROJECT_NAME=${PREFIX}-${PROJECT}
DEF_HOST_SFX=cl7kxrjemfld.us-west-1.rds.amazonaws.com

TARGET_NAMESPACE=default

write_refs () {
    if [[ ${1} == "NEW" && -n ${2} ]]; 
    then eval 'echo $2=$'$2 > ${REFS};
    else eval 'echo $1=$'$1 >> ${REFS};
    fi
}

read_refs () {
    . ${1:-$REFS}
}

read_creds () {
    aws_access_key_id=`cat ${1:-$CREDS} | grep _id | cut -f2 -d"="`
    aws_secret_access_key=`cat ${1:-$CREDS} | grep _sec | cut -f2 -d"="`
}



capture_namespace () {
    ORIG_NAMESPACE=$(kubectl config view --minify --output 'jsonpath={..namespace}')
    if [ -z "$ORIG_NAMESPACE" ]; then
        ORIG_NAMESPACE=$TARGET_NAMESPACE
    fi
}

reset_namespace() {
    echo "Switching back to namespace: $ORIG_NAMESPACE"
    echo kubectl config set-context --current --namespace=$ORIG_NAMESPACE
}

finally () {
    #trap error
    if [[ $? > 0 ]]; 
    then
        echo "${last_command} command failed with exit code $?"
    fi    
    reset_namespace
}
