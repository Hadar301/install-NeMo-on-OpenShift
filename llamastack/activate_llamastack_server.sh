#!/bin/bash

export LLAMA_STACK_PORT=8321
export NVIDIA_API_KEY=""
# Use host.containers.internal to access host from container
export NVIDIA_BASE_URL="http://host.containers.internal:8006"
export NVIDIA_DATASETS_URL="http://host.containers.internal:8001"
export NVIDIA_DATASET_NAMESPACE="xlam-tutorial-ns"
export NVIDIA_PROJECT_ID="llamastack-project"
export NVIDIA_CUSTOMIZER_URL="http://host.containers.internal:8003"
export GUARDRAILS_SERVICE_URL="http://host.containers.internal:8005"
export NVIDIA_GUARDRAILS_CONFIG_ID="demo-self-check-input-output"
export NVIDIA_EVALUATOR_URL="http://host.containers.internal:8004"
export NIM_PROXY_URL="http://host.containers.internal:8006"
export INFERENCE_MODEL="meta/llama-3.2-1b-instruct"
export SAFETY_MODEL="meta/llama-3.2-1b-instruct"

podman run \
  --platform linux/amd64 \
  -p 8321:8321 \
  -p 8001:8001 \
  -p 8002:8002 \
  -p 8003:8003 \
  -p 8004:8004 \
  -p 8005:8005 \
  -p 8006:8006 \
  --entrypoint llama \
  -it \
  -e NVIDIA_API_KEY=$NVIDIA_API_KEY \
  -e NVIDIA_BASE_URL=$NVIDIA_BASE_URL \
  -e NVIDIA_DATASETS_URL=$NVIDIA_DATASETS_URL \
  -e NVIDIA_DATASET_NAMESPACE=$NVIDIA_DATASET_NAMESPACE \
  -e NVIDIA_PROJECT_ID=$NVIDIA_PROJECT_ID \
  -e NVIDIA_CUSTOMIZER_URL=$NVIDIA_CUSTOMIZER_URL \
  -e GUARDRAILS_SERVICE_URL=$GUARDRAILS_SERVICE_URL \
  -e NVIDIA_GUARDRAILS_CONFIG_ID=$NVIDIA_GUARDRAILS_CONFIG_ID \
  -e NVIDIA_EVALUATOR_URL=$NVIDIA_EVALUATOR_URL \
  -e NIM_PROXY_URL=$NIM_PROXY_URL \
  -e INFERENCE_MODEL=$INFERENCE_MODEL \
  -e SAFETY_MODEL=$SAFETY_MODEL \
  -v /Users/hacohen/Desktop/repos/install-NeMo-on-OpenShift/llamastack:/app \
  quay.io/hacohen/distribution-nvidia:v0.3.0 \
  stack run /app/run.yaml --port $LLAMA_STACK_PORT
