#!/bin/bash

export NAMESPACE="hacohen-nemo"

bash clear_namespace.sh
sleep 15s
bash nemo_prerequisites.sh
sleep 10s
bash deploy_microservices.sh