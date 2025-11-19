#!/bin/bash
set -e

NAMESPACE="${1:-hacohen-nemo}"
SERVICE_NAME="${2:-llamastack}"
PORT="${3:-8321}"

echo "Testing LlamaStack Server Connectivity"
echo "======================================="
echo "Namespace: $NAMESPACE"
echo "Service: $SERVICE_NAME"
echo "Port: $PORT"
echo ""

# Check if service exists
echo "1. Checking if service exists..."
if oc get svc $SERVICE_NAME -n $NAMESPACE &>/dev/null; then
    echo "   ✅ Service $SERVICE_NAME exists"
    oc get svc $SERVICE_NAME -n $NAMESPACE
else
    echo "   ❌ Service $SERVICE_NAME not found in namespace $NAMESPACE"
    exit 1
fi
echo ""

# Check if deployment is ready
echo "2. Checking if deployment is ready..."
if oc get deployment llamastack -n $NAMESPACE &>/dev/null; then
    READY=$(oc get deployment llamastack -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
    DESIRED=$(oc get deployment llamastack -n $NAMESPACE -o jsonpath='{.spec.replicas}')

    if [ "$READY" == "$DESIRED" ] && [ "$READY" != "" ]; then
        echo "   ✅ Deployment ready ($READY/$DESIRED replicas)"
    else
        echo "   ⚠️ Deployment not ready ($READY/$DESIRED replicas)"
        echo "   Waiting for pods to be ready..."
        oc wait --for=condition=available --timeout=60s deployment/llamastack -n $NAMESPACE
    fi
else
    echo "   ❌ Deployment llamastack not found"
    exit 1
fi
echo ""

# Get pod status
echo "3. Checking pod status..."
oc get pods -n $NAMESPACE -l app=nemo-llamastack
echo ""

# Test connectivity from inside the cluster
echo "4. Testing connectivity from inside the cluster..."
echo "   Creating test pod..."

TEST_RESULT=$(oc run llamastack-test-pod \
    --image=curlimages/curl:latest \
    --restart=Never \
    --rm \
    -n $NAMESPACE \
    -i \
    --quiet \
    --command -- sh -c "
        echo '=== Testing LlamaStack Server (Unified API Gateway) ==='
        echo ''
        echo '1. Models - List available models...'
        curl -s -w '\n   HTTP Status: %{http_code}\n' \
            http://$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$PORT/v1/models
        echo ''
        echo '2. Datasets - List registered datasets...'
        curl -s -w '\n   HTTP Status: %{http_code}\n' \
            http://$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$PORT/v1/datasets
        echo ''
        echo '3. Post-Training - List fine-tuning jobs...'
        curl -s -w '\n   HTTP Status: %{http_code}\n' \
            http://$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$PORT/v1/post-training/jobs
        echo ''
        echo '4. Evaluation - List benchmarks...'
        curl -s -w '\n   HTTP Status: %{http_code}\n' \
            http://$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$PORT/v1/eval/benchmarks
        echo ''
        echo '5. Inference - Test chat completion (OpenAI-compatible)...'
        INFERENCE_RESULT=\$(curl -s -X POST http://$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$PORT/v1/chat/completions \
            -H 'Content-Type: application/json' \
            -d '{\"model\": \"nvidia/meta/llama-3.2-1b-instruct\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hi in 3 words\"}], \"max_tokens\": 10}')
        echo \"\$INFERENCE_RESULT\" | head -c 200
        echo '...'
        if echo \"\$INFERENCE_RESULT\" | grep -q '\"choices\"'; then
            echo '   ✅ Inference successful'
        else
            echo '   ❌ Inference failed'
        fi
    " 2>&1)

echo "$TEST_RESULT"
echo ""

# Check for successful responses
if echo "$TEST_RESULT" | grep -q "HTTP Status: 200"; then
    echo "✅ LlamaStack server is responding correctly!"
    echo ""
    echo "You can now:"
    echo "  1. Port-forward to access locally:"
    echo "     oc port-forward -n $NAMESPACE svc/$SERVICE_NAME $PORT:$PORT"
    echo ""
    echo "  2. Use from notebooks running in the cluster at:"
    echo "     http://$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$PORT"
else
    echo "❌ LlamaStack server is not responding as expected"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check pod logs:"
    echo "     oc logs -n $NAMESPACE -l app=nemo-llamastack --tail=100"
    echo ""
    echo "  2. Check pod events:"
    echo "     oc describe pod -n $NAMESPACE -l app=nemo-llamastack"
    exit 1
fi
