#!/bin/bash


git clone git clone https://github.com/meta-llama/llama-stack.git

cd llama-stack

podman build --platform=linux/amd64 \
  -f containers/Containerfile \
  --build-arg DISTRO_NAME=nvidia \
  --build-arg INSTALL_MODE=editable \
  --tag quay.io/hacohen/distribution-nvidia:v0.3.0 .

podman push quay.io/hacohen/distribution-nvidia:v0.3.0