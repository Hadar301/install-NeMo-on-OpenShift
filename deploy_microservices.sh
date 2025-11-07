#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing LLAMA..."
oc apply -f llama-nim.yaml
echo "Done Installing LLAMA"

cd "$SCRIPT_DIR/k8s-nim-operator/config/samples/nemo/25.06" 

for file in apps_v1alpha1_nemodatastore.yaml apps_v1alpha1_nemoentitystore.yaml apps_v1alpha1_nemocustomizer.yaml apps_v1alpha1_nemoevaluator.yaml apps_v1alpha1_nemoguardrails.yaml nemocustomizer_config.yaml; do
  echo "Applying $file..."
  sed "s/namespace: nemo/namespace: $NAMESPACE/g" "$file" | \
  sed "s/\\.nemo\\.svc\\.cluster\\.local/.$NAMESPACE.svc.cluster.local/g" | \
  sed 's/storageClass: ""/storageClass: "gp3-csi"/g' | \
  oc apply -f -
done

echo "Patching NemoCustomizer modelDownloadJobs security context for GPU compatibility..."
oc patch nemocustomizer nemocustomizer-sample -n $NAMESPACE --type='merge' -p='
{
  "spec": {
    "modelDownloadJobs": {
      "securityContext": {
        "fsGroup": 0,
        "runAsNonRoot": false,
        "runAsUser": 0,
        "runAsGroup": 0
      }
    },
    "trainingConfig": {
      "image": {
        "repository": "nvcr.io/nvidia/nemo-microservices/customizer",
        "tag": "25.08"
      },
      "env": [
        {
          "name": "NVIDIA_DRIVER_CAPABILITIES",
          "value": "all"
        },
        {
          "name": "NVIDIA_VISIBLE_DEVICES",
          "value": "all"
        },
        {
          "name": "NVIDIA_REQUIRE_CUDA",
          "value": ""
        }
      ]
    }
  }
}'

oc patch nemocustomizer nemocustomizer-sample -n $NAMESPACE --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/env",
    "value": [
      {
        "name": "NGC_API_KEY",
        "valueFrom": {
          "secretKeyRef": {
            "name": "ngc-api-secret",
            "key": "NGC_API_KEY"
          }
        }
      },
      {
        "name": "HF_TOKEN",
        "valueFrom": {
          "secretKeyRef": {
            "name": "hf-token",
            "key": "HF_TOKEN"
          }
        }
      }
    ]
  }
]'

echo "Patching NemoCustomizer storage classes to use gp3-csi..."
oc patch nemocustomizer nemocustomizer-sample -n $NAMESPACE --type='merge' -p='
{
  "spec": {
    "trainingConfig": {
      "modelPVC": {
        "storageClass": "gp3-csi"
      },
      "workspacePVC": {
        "storageClass": "gp3-csi"
      }
    }
  }
}'

echo "Patching NemoCustomizer to fix Hugging Face cache permissions..."
oc patch nemoentityhandler dataset-downloader -n $NAMESPACE --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/image/arguments/1",
    "value": "huggingface-cli download --repo-type dataset $ENTITY_NAME --local-dir /tmp/dataset && mkdir -p $ENTITY_PATH && mv /tmp/dataset/* $ENTITY_PATH"
  }
]'

echo "Patching NemoCustomizer to allocate GPU for training..."
oc patch nemocustomizer nemocustomizer-sample -n $NAMESPACE --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/trainingConfig/tolerations",
    "value": [
      {
        "effect": "NoSchedule",
        "key": "g6e-gpu", 
        "operator": "Equal",
        "value": "true"
      }
    ]
  }
]'
# g6e-gpu
cd "$SCRIPT_DIR"

echo "Applying security-specific training config (merges with base nemo-training-config)..."
oc apply -f nemo-training-security.yaml -n $NAMESPACE
oc patch nemocustomizer nemocustomizer-sample -n $NAMESPACE --type='merge' -p='
{
  "spec": {
    "modelConfigMap": {
      "name": "nemo-model-config"
    },
    "trainingConfig": {
      "configMap": {
        "name": "nemo-training-security-config"
      }
    }
  }
}'

echo "Waiting for NemoCustomizer ready..."
oc wait --for=condition=ready nemocustomizer/nemocustomizer-sample -n $NAMESPACE --timeout=600s
echo "NemoCustomizer is ready..."

oc patch nemoevaluator nemoevaluator-sample -n hacohen-nemo --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/env",
    "value": [
      {
        "name": "NIM_PROXY_URL",
        "value": "http://meta-llama3-1b-instruct.hacohen-nemo.svc.cluster.local:8000"
      }
    ]
  }
]'
oc wait --for=condition=ready pod -l app=nemoevaluator-sample -n hacohen-nemo --timeout=300s

cd "$SCRIPT_DIR"
# Apply the SCC
oc apply -f nemo-customizer-scc.yaml

# Bind the SCC to your service account
oc adm policy add-scc-to-user nemo-customizer-scc -z default -n $NAMESPACE
oc adm policy add-scc-to-user nemo-customizer-scc -z nemocustomizer-sample -n $NAMESPACE

oc get pods -n $NAMESPACE
# oc expose svc jupyter-service
oc get route
echo "DONE!"


