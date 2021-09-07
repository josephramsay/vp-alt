#!/bin/bash

DUMP_FILE=dump.sql

#Dump from Source Pod (NB superset is just for testing)
'''SRC_POD=superset-postgresql-0
SRC_PG_PASS=********
SRC_PG_USER=superset
SRC_PG_DBNAME=superset
'''

#Passwords can be found on the pod in the env vars
SRC_PASS_PATH=~/.aws/pod_data2_password
SRC_POD=postgres-558b5f557d-bkcwn
SRC_PG_PASS=$(cat ${SRC_PASS_PATH})
SRC_PG_USER=metastore_user
SRC_PG_DBNAME=metastore

#Setup Destination
DST_PASS_PATH=~/.aws/rds_data2_password
DST_RDS=$( build.sh ${SRC_PG_DBNAME} ${SRC_PG_USER} ${DST_PASS_PATH} )

DST_ID=vpjr-rds-data2
#TODO Check into reading full hostname
DST_PG_HOST=${DST_ID}.cl7kxrjemfld.us-west-1.rds.amazonaws.com
DST_PG_USER=vp_user
DST_PG_PASS=$(cat ${DST_PASS_PATH})
DST_PG_DBNAME=${SRC_PG_NAME}

#Dump database on pod
#DUMP
'''
kubectl exec -t ${SRC_POD} -- env PGPASSWORD=${SRC_PG_PASS} \
    pg_dump -C -h localhost -U ${SRC_PG_USER} ${SRC_PG_DBNAME} > ${DUMP_FILE}
'''

#DUMPALL
'''
kubectl exec -t ${SRC_POD} -- env PGPASSWORD=${SRC_PG_PASS} \
    psql -h localhost -U ${SRC_PG_USER} \
    -c "GRANT USAGE ON SCHEMA public TO ${SRC_PG_USER}; \
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${SRC_PG_USER};" \
    metastore
'''

echo Dumping Globals
kubectl exec -t ${SRC_POD} -- env PGPASSWORD=${SRC_PG_PASS} \
    pg_dumpall -h localhost -U ${SRC_PG_USER} -g > globals.${DUMP_FILE}

echo Dumping Tablespaces
kubectl exec -t ${SRC_POD} -- env PGPASSWORD=${SRC_PG_PASS} \
    pg_dumpall -h localhost -U ${SRC_PG_USER} -t > tablespaces.${DUMP_FILE}

echo Dumping Schema
kubectl exec -t ${SRC_POD} -- env PGPASSWORD=${SRC_PG_PASS} \
    pg_dumpall -h localhost -U ${SRC_PG_USER} -s > schema.${DUMP_FILE}

echo Dumping Data
kubectl exec -t ${SRC_POD} -- env PGPASSWORD=${SRC_PG_PASS} \
    pg_dumpall -h localhost -U ${SRC_PG_USER} -a > data.${DUMP_FILE} 

#RESTORE
PGPASSWORD=${DST_PG_PASS} psql -U ${DST_PG_USER} \
    -h ${DST_PG_HOST} -f ${DUMP_FILE} ${DST_PG_DBNAME}