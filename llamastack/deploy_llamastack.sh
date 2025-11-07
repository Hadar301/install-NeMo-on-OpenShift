#!/bin/bash

oc apply -f configmap.yaml
oc apply -f service.yaml
oc apply -f deployment.yaml
oc wait --for=condition=available deployment/llamastack --timeout=300s
sleep 3s
oc apply -f route.yaml

oc get pods | grep llamastack
oc get route | grep llamastack