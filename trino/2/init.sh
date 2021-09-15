#!/bin/bash

export CLUSTER_NAME=vp-test
export REGION=us-west-1


#eksctl create cluster --region ${REGION} --name ${CLUSTER_NAME} --version 1.19 --without-nodegroup
#aws eks --region ${REGION} update-kubeconfig --name ${CLUSTER_NAME}
j2 dev-cluster.j2
#eksctl create nodegroup --config-file=dev-cluster.yaml