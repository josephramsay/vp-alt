
REFS=~/.aws/vpjr.refs
CREDS=~/.aws/credentials
DEF_POD_PASS_PATH=~/.aws/pod_db_password
DEF_RDS_PASS_PATH=~/.aws/rds_db_password

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

DEF_HOST_SFX=cl7kxrjemfld.us-west-1.rds.amazonaws.com

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