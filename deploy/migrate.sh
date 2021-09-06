#!/bin/bash

DUMP_FILE=dump.sql

SRC_POD=superset-postgresql-0
SRC_PG_PASS=********
SRC_PG_USER=superset
SRC_PG_DBNAME=superset


#
DST_RDS=$( build.sh )
#Dump database on pod
kubectl exec -t ${SRC_POD} -- env PGPASSWORD=${SRC_PG_PASS} \
    pg_dump -h localhost -U ${SRC_PG_USER} -t tag ${SRC_PG_DBNAME} > ${DUMP_FILE}

pg_restore ${DUMP_FILE} ${DST_RDS}