#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

echo $SCRIPT_DIR
echo $ENV_FILE

if [ -f "$ENV_FILE" ]; then
set -a
. "$ENV_FILE"
set +a
fi

: "${NGC_API_KEY:?Set NGC_API_KEY in $ENV_FILE}"
: "${HF_Token:?Set HF_Token in $ENV_FILE}"

echo "Retrived API key for NGC"
# echo "$NGC_API_KEY"

echo "Retrived toekn for HF"
# echo "$HF_Token"
oc new-project $NAMESPACE

echo "created new project"

oc create secret -n $NAMESPACE docker-registry ngc-secret \
    --docker-server=nvcr.io \
    --docker-username='$oauthtoken' \
    --docker-password="${NGC_API_KEY}"

echo "Added a Docker registry secret for downloading container images from NVIDIA NGC"

oc create secret -n $NAMESPACE generic ngc-api-secret \
    --from-literal=NGC_API_KEY="${NGC_API_KEY}"

echo "Added a generic secret that the model puller containers use to download models from NVIDIA NGC"


oc create secret generic hf-token \
  --from-literal=HF_TOKEN=${HF_Token} \
  -n $NAMESPACE

echo "Added HF token"


echo "Installing NeMo Microservices Prerequisites..."
cd k8s-nim-operator/test/e2e/nemo-dependencies
ansible-playbook -c local -i localhost install.yaml
cd $SCRIPT_DIR
echo "DONE! Installing NeMo Microservices Prerequisites"


echo "Install NeMo Training Operator..."
export VERSION=25.6.0

helm fetch https://helm.ngc.nvidia.com/nvidia/nemo-microservices/charts/nemo-operator-${VERSION}.tgz\
  --username='$oauthtoken' \
  --password="${NGC_API_KEY}"

helm template --include-crds ./nemo-operator-${VERSION}.tgz \
  | yq 'select(.kind == "CustomResourceDefinition")' | oc apply -f -

helm upgrade --install nemo-operator nemo-operator-${VERSION}.tgz \
  -n $NAMESPACE \
  --set 'imagePullSecrets[0].name=ngc-secret' \
  --set controllerManager.manager.scheduler=volcano \
  --set controllerManager.manager.image.tag=25.06
echo "Done Installing NeMo Training Operator"


# echo "Install k8s-nim-operator (for NIM and NeMo Microservices)..."
# cd k8s-nim-operator

# Install CRDs
# make install

# Deploy the operator using Helm
# helm upgrade --install k8s-nim-operator deployments/helm/k8s-nim-operator/ \
#   -n $NAMESPACE \
#   --set 'imagePullSecrets[0].name=ngc-secret' \
#   --set nfd.nodeFeatureRules.deviceID=false

# oc patch deployment k8s-nim-operator -n $NAMESPACE -p '{"spec":{"template":{"spec":{"containers":[{"name":"manager","resources":{"limits":{"memory":"512Mi"},"requests":{"memory":"256Mi"}}}]}}}}'

# cd $SCRIPT_DIR
# echo "Done Installing k8s-nim-operator"


echo "Verify installation..."
oc get pods -n $NAMESPACE
oc get secrets -n $NAMESPACE

echo "Waiting for operators to be ready..."
oc wait --for=condition=available --timeout=300s deployment/nemo-operator-controller-manager -n $NAMESPACE
oc wait --for=condition=available --timeout=300s deployment/k8s-nim-operator-controller-manager -n $NAMESPACE
# oc wait --for=condition=available --timeout=300s deployment/k8s-nim-operator -n $NAMESPACE

echo "All prerequisites installed successfully!"

# #!/bin/bash

# NAMESPACE="hacohen-nemo"


# set -euo pipefail
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ENV_FILE="$SCRIPT_DIR/.env"

# echo $SCRIPT_DIR
# echo $ENV_FILE

# if [ -f "$ENV_FILE" ]; then
# set -a
# . "$ENV_FILE"
# set +a
# fi

# : "${NGC_API_KEY:?Set NGC_API_KEY in $ENV_FILE}"
# : "${HF_Token:?Set HF_Token in $ENV_FILE}"

# echo "Retrived API key for NGC"
# # echo "$NGC_API_KEY"

# echo "Retrived toekn for HF"
# # echo "$HF_Token"
# oc new-project $NAMESPACE

# echo "created new project"

# oc create secret -n $NAMESPACE docker-registry ngc-secret \
#     --docker-server=nvcr.io \
#     --docker-username='$oauthtoken' \
#     --docker-password="${NGC_API_KEY}"

# echo "Added a Docker registry secret for downloading container images from NVIDIA NGC"

# oc create secret -n $NAMESPACE generic ngc-api-secret \
#     --from-literal=NGC_API_KEY="${NGC_API_KEY}"

# echo "Added a generic secret that the model puller containers use to download models from NVIDIA NGC"


# oc create secret generic hf-token \
#   --from-literal=HF_TOKEN=${HF_Token} \
#   -n $NAMESPACE

# echo "Added HF token"


# echo "Installing NeMo Microservices Prerequisites..."
# cd k8s-nim-operator/test/e2e/nemo-dependencies
# ansible-playbook -c local -i localhost install.yaml
# echo "DONE! Installing NeMo Microservices Prerequisites"


# echo "Install NeMo Operator..."
# export VERSION=25.4.0

# helm fetch https://helm.ngc.nvidia.com/nvidia/nemo-microservices/charts/nemo-operator-${VERSION}.tgz\
#   --username='$oauthtoken' \
#   --password="${NGC_API_KEY}"

# helm template --include-crds ./nemo-operator-${VERSION}.tgz \
#   | yq 'select(.kind == "CustomResourceDefinition")' | oc apply -f -

# helm upgrade --install nemo-operator nemo-operator-${VERSION}.tgz \
#   -n $NAMESPACE \
#   --set 'imagePullSecrets[0].name=ngc-secret' \
#   --set controllerManager.manager.scheduler=volcano
# echo "Done Installing NeMo operator"

# echo "Verity installation..."
# oc get pods -n $NAMESPACE
# oc get secrets -n $NAMESPACE

# # echo "Installing LLAMA..."
# # oc apply -f llama-nim.yaml
# # echo "Done Installing LLAMA"
