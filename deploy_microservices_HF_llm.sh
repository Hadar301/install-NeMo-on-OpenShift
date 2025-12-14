#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="hacohen-nemo"

echo "Installing IBM Granite-3.1-1B-Instruct model..."
oc apply -f granite-3.1-1b-hf.yaml
echo "Done Installing Granite model"

cd "$SCRIPT_DIR/k8s-nim-operator/config/samples/nemo/25.06"

for file in apps_v1alpha1_nemodatastore.yaml apps_v1alpha1_nemoentitystore.yaml apps_v1alpha1_nemocustomizer.yaml apps_v1alpha1_nemoevaluator.yaml apps_v1alpha1_nemoguardrails.yaml nemocustomizer_config.yaml; do
  echo "Applying $file..."
  sed "s/namespace: nemo/namespace: $NAMESPACE/g" "$file" | \
  sed "s/\.nemo\.svc\.cluster\.local/.$NAMESPACE.svc.cluster.local/g" | \
  sed 's/storageClass: ""/storageClass: "gp3-csi"/g' | \
  oc apply -f -
done

echo "Waiting for NemoCustomizer to be ready..."
oc wait --for=condition=ready pod -l app.kubernetes.io/name=nemocustomizer -n $NAMESPACE --timeout=300s || true

echo "Patching NeMo Data Store for HuggingFace proxy..."
oc patch nemodatastore nemodatastore-sample -n $NAMESPACE --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/env",
    "value": [
      {
        "name": "HF_TOKEN",
        "valueFrom": {
          "secretKeyRef": {
            "name": "hf-token",
            "key": "HF_TOKEN"
          }
        }
      },
      {
        "name": "HF_ENDPOINT",
        "value": "https://huggingface.co"
      }
    ]
  }
]'
echo "  Waiting for Data Store to restart..."
sleep 30

echo "Patching NemoCustomizer for IBM Granite HuggingFace model support..."

# Patch 0: Disable meta models and add IBM Granite-3.1-1B model
echo "  - Disabling meta models and adding Granite-3.1-1B model config..."
oc patch configmap nemo-model-config -n $NAMESPACE --type='json' -p='[
  {
    "op": "replace",
    "path": "/data/customizationTargets",
    "value": "overrideExistingTargets: true\ntargets:\n  meta/llama-3.1-8b-instruct@2.0:\n    base_model: meta/llama-3.1-8b-instruct\n    enabled: false\n    model_path: llama-3_1-8b-instruct_2_0\n    model_uri: ngc://nvidia/nemo/llama-3_1-8b-instruct-nemo:2.0\n    name: llama-3.1-8b-instruct@2.0\n    namespace: meta\n    num_parameters: 8000000000\n    precision: bf16-mixed\n  meta/llama-3.2-1b-instruct@2.0:\n    base_model: meta/llama-3.2-1b-instruct\n    enabled: false\n    model_path: llama32_1b-instruct_2_0\n    model_uri: ngc://nvidia/nemo/llama-3_2-1b-instruct:2.0\n    name: llama-3.2-1b-instruct@2.0\n    namespace: meta\n    num_parameters: 1000000000\n    precision: bf16-mixed\n  ibm-granite/granite-3.1-1b-instruct@1.0:\n    base_model: ibm-granite/granite-3.1-1b-instruct\n    enabled: true\n    model_path: granite-3.1-1b-instruct\n    model_uri: hf://ibm-granite/granite-3.1-1b-a400m-instruct\n    name: granite-3.1-1b-instruct@1.0\n    namespace: ibm-granite\n    num_parameters: 1300000000\n    precision: bf16-mixed\n"
  },
  {
    "op": "add",
    "path": "/data/customizationConfigTemplates",
    "value": "overrideExistingTemplates: false\ntemplates:\n  ibm-granite/granite-3.1-1b-instruct@v1.0.0+A100:\n    max_seq_length: 4096\n    name: granite-3.1-1b-instruct@v1.0.0+A100\n    namespace: ibm-granite\n    prompt_template: \"{prompt} {completion}\"\n    target: ibm-granite/granite-3.1-1b-instruct@1.0\n    training_options:\n    - finetuning_type: lora\n      micro_batch_size: 1\n      num_gpus: 1\n      num_nodes: 1\n      tensor_parallel_size: 1\n      training_type: sft\n"
  }
]'

# Restart NemoCustomizer to pick up new config
echo "  - Restarting NemoCustomizer to apply new model config..."
oc rollout restart deployment -l app.kubernetes.io/name=nemocustomizer -n $NAMESPACE
oc rollout status deployment -l app.kubernetes.io/name=nemocustomizer -n $NAMESPACE --timeout=300s

# Patch 1: Temporarily configure datastore endpoint to HuggingFace for model download
echo "  - Configuring datastore endpoint to HuggingFace for model download..."
oc patch nemocustomizer nemocustomizer-sample -n $NAMESPACE --type='merge' -p='
{
  "spec": {
    "datastore": {
      "endpoint": "https://huggingface.co"
    },
    "modelDownloadJobs": {
      "hfSecret": {
        "name": "hf-token",
        "key": "HF_TOKEN"
      }
    }
  }
}'

echo "  - Waiting for Granite-3.1-1B model to download..."
echo "    Monitoring model downloader job..."

# Wait for model downloader job to complete
for i in {1..60}; do
  # Find the model downloader pod for Granite
  POD_NAME=$(oc get pods -n $NAMESPACE -l job-name=model-downloader-ibm-granite-granite-3-1-1b-instruct-1-0 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [ -n "$POD_NAME" ]; then
    POD_STATUS=$(oc get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.status.phase}' 2>/dev/null)

    if [ "$POD_STATUS" = "Succeeded" ]; then
      echo "    ✅ Model download complete!"
      break
    elif [ "$POD_STATUS" = "Failed" ]; then
      echo "    ❌ Model download failed! Check logs:"
      oc logs -n $NAMESPACE $POD_NAME --tail=20
      break
    else
      echo "    Job status: $POD_STATUS (attempt $i/60)"
      sleep 10
    fi
  else
    echo "    Waiting for model downloader job to start... (attempt $i/60)"
    sleep 10
  fi
done

if [ "$POD_STATUS" != "Succeeded" ]; then
  echo ""
  echo "⚠️  Model download did not complete successfully."
  echo ""
fi

# Patch 2: Switch datastore endpoint back to NeMo Data Store for dataset access
echo "  - Switching datastore endpoint back to NeMo Data Store for dataset access..."
oc patch nemocustomizer nemocustomizer-sample -n $NAMESPACE --type='merge' -p='
{
  "spec": {
    "datastore": {
      "endpoint": "http://nemodatastore-sample.'$NAMESPACE'.svc.cluster.local:8000"
    }
  }
}'
echo "    ✅ Datastore endpoint now points to NeMo Data Store"
echo ""
echo "    Model is cached in PVC, datasets will be fetched from Data Store during fine-tuning"
echo ""

# Patch 2: Update security context for GPU compatibility
echo "  - Updating security context for GPU access..."
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

# Patch 3: Add HF_TOKEN and NGC_API_KEY to customizer API env
echo "  - Adding tokens to Customizer API..."
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

# Patch 4: Update storage classes
echo "  - Updating storage classes to gp3-csi..."
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

# Patch 5: Fix Hugging Face cache permissions
echo "  - Fixing HuggingFace cache permissions..."
oc patch nemoentityhandler dataset-downloader -n $NAMESPACE --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/image/arguments/1",
    "value": "huggingface-cli download --repo-type dataset $ENTITY_NAME --local-dir /tmp/dataset && mkdir -p $ENTITY_PATH && mv /tmp/dataset/* $ENTITY_PATH"
  }
]'

# Patch 6: Allocate GPU for training
echo "  - Configuring GPU tolerations..."
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

cd "$SCRIPT_DIR"

echo "Applying security-specific training config..."
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

echo "Waiting for NemoCustomizer to be ready..."
oc wait --for=condition=ready nemocustomizer/nemocustomizer-sample -n $NAMESPACE --timeout=600s
echo "✅ NemoCustomizer is ready"

# Patch 7: Update evaluator to use IBM Granite model instead of meta
echo "Patching NemoEvaluator to use Granite model..."
oc patch nemoevaluator nemoevaluator-sample -n $NAMESPACE --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/env",
    "value": [
      {
        "name": "NIM_PROXY_URL",
        "value": "http://granite-3-1-1b-instruct.hacohen-nemo.svc.cluster.local:8000/v1"
      }
    ]
  }
]'
oc wait --for=condition=ready pod -l app=nemoevaluator-sample -n $NAMESPACE --timeout=300s

cd "$SCRIPT_DIR"

# Apply Security Context Constraints
echo "Applying Security Context Constraints..."
oc apply -f nemo-customizer-scc.yaml

# Bind the SCC to service accounts
oc adm policy add-scc-to-user nemo-customizer-scc -z default -n $NAMESPACE
oc adm policy add-scc-to-user nemo-customizer-scc -z nemocustomizer-sample -n $NAMESPACE

echo "Current pods in $NAMESPACE:"
oc get pods -n $NAMESPACE

echo ""
echo "Waiting for Granite NIM to be ready before deploying LlamaStack..."
echo "  - Checking if granite-3-1-1b-instruct pod is running and ready..."

# Wait for Granite NIM pod to be ready (max 20 minutes - 1B model should load faster)
for i in {1..120}; do
  POD_READY=$(oc get pods -n $NAMESPACE -l app=granite-3-1-1b-instruct -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  POD_NAME=$(oc get pods -n $NAMESPACE -l app=granite-3-1-1b-instruct -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [ "$POD_READY" = "True" ]; then
    echo "  ✅ Granite NIM pod is ready!"
    break
  elif [ -n "$POD_NAME" ]; then
    POD_STATUS=$(oc get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
    RESTARTS=$(oc get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
    echo "  Granite NIM status: $POD_STATUS (restarts: $RESTARTS) - attempt $i/120 ($(($i * 10 / 60)) min)"
    sleep 10
  else
    echo "  Waiting for Granite NIM pod to start... (attempt $i/120)"
    sleep 10
  fi
done

if [ "$POD_READY" != "True" ]; then
  echo ""
  echo "⚠️  WARNING: Granite NIM did not become ready within 20 minutes."
  echo "   LlamaStack deployment may fail if the model is not available."
  echo "   Check pod logs: oc logs -n $NAMESPACE $POD_NAME"
  echo ""
  read -p "Continue with LlamaStack deployment anyway? (y/N): " CONTINUE
  if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
    echo "Deployment halted. Fix the Granite NIM issue and run the script again."
    exit 1
  fi
else
  echo "  ✅ Granite NIM is ready, proceeding with LlamaStack deployment"
fi

echo ""
echo "Deploying LlamaStack..."
cd llamastack
bash deploy_llamastack.sh

echo ""
echo "=========================================="
echo "✅ IBM Granite Model Deployment Complete!"
echo "=========================================="
echo ""
echo "Deployed:"
echo "  - IBM Granite 3.1 1B Instruct (NIM)"
echo "  - NeMo Microservices (Data Store, Entity Store, Customizer, Evaluator, Guardrails)"
echo "  - LlamaStack Server"
echo ""
echo "Model Service:"
echo "  - http://granite-3-1-1b-instruct.$NAMESPACE.svc.cluster.local:8000"
echo ""
echo "Next steps:"
echo "  1. Update notebook cells for Granite model (see MISTRAL_NOTEBOOK_CHANGES.md)"
echo "  2. Run fine-tuning using the Granite model config"
echo "  3. Test LoRA adapter loading"
echo ""
echo "DONE!"
