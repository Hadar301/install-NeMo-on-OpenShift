#!/bin/bash

# NDS_URL = "http://localhost:8001"  # Data Store
# ENTITY_STORE_URL = "http://localhost:8002"  # Entity Store
# CUSTOMIZER_URL = "http://localhost:8003"  # Customizer
# EVALUATOR_URL = "http://localhost:8004"  # Evaluator
# GUARDRAILS_URL = "http://localhost:8005"  # Guardrails
# NIM_URL = "http://localhost:8006"  # NIM

# Trap SIGINT and SIGTERM to kill all background processes
trap 'echo "Stopping all port-forwards..."; kill $(jobs -p) 2>/dev/null; exit' INT TERM

echo "Starting port-forwards..."

oc port-forward svc/nemodatastore-sample 8001:8000 -n arhkp-nemo-helm &
sleep 0.1s
oc port-forward svc/nemoentitystore-sample 8002:8000 -n arhkp-nemo-helm &
sleep 0.1s
oc port-forward svc/nemocustomizer-sample 8003:8000 -n arhkp-nemo-helm &
sleep 0.1s
oc port-forward svc/nemoevaluator-sample 8004:8000 -n arhkp-nemo-helm &
sleep 0.1s
oc port-forward svc/nemoguardrails-sample 8005:8000 -n arhkp-nemo-helm &
sleep 0.1s
oc port-forward svc/meta-llama3-1b-instruct 8006:8000 -n arhkp-nemo-helm &
sleep 0.1s
oc port-forward svc/nemo-samples-nemo-operator 8007:8443 -n arhkp-nemo-helm &

echo "All port-forwards started. Press Ctrl+C to stop all."

# Wait for all background jobs
wait