#!/bin/bash

NAMESPACE="hacohen-nemo"

oc apply -f configmap.yaml -n $NAMESPACE
oc apply -f service.yaml -n $NAMESPACE
oc apply -f deployment.yaml -n $NAMESPACE
oc wait --for=condition=available deployment/llamastack --timeout=300s
sleep 3s
# oc apply -f route.yaml

oc get pods -n $NAMESPACE | grep llamastack
# oc get route | grep llamastack