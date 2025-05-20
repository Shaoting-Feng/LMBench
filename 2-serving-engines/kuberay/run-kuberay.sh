#!/bin/bash
set -e

# 1. Go to the current directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Create .zshrc to prevent interruptions from the zsh-newuser-install prompt
touch ~/.zshrc

# Clean up existing Ray service resources
echo "Cleaning up existing Ray service resources..."
kubectl delete rayservice rayservice-sample --ignore-not-found=true
kubectl delete service rayservice-service --ignore-not-found=true
kubectl delete service rayservice-sample-head-svc --ignore-not-found=true
kubectl delete service rayservice-sample-serve-svc --ignore-not-found=true
kubectl delete raycluster --all --ignore-not-found=true
kubectl delete configmap llm-api-script --ignore-not-found=true
kubectl delete pod curl --ignore-not-found=true

# Terminate any existing port-forward processes
echo "Cleaning up any existing port-forward processes..."
pkill -f "kubectl port-forward svc/rayservice" || true

# Check if KubeRay operator is already installed and in a failed state
if helm list | grep kuberay-operator | grep -q "failed"; then
  echo "Found KubeRay operator in failed state, uninstalling..."
  helm delete kuberay-operator
fi

# 2. Install KubeRay operator if not already installed
if ! kubectl get deployment kuberay-operator &>/dev/null; then
  echo "Installing KubeRay operator..."
  helm repo add kuberay https://ray-project.github.io/kuberay-helm/
  helm repo update
  helm install kuberay-operator kuberay/kuberay-operator --version 1.3.0

  # Wait for the operator to be ready
  echo "Waiting for KubeRay operator to be ready..."
  while [[ $(kubectl get pods -l=app.kubernetes.io/name=kuberay-operator -o jsonpath='{.items[0].status.phase}') != "Running" ]]; do
    echo "Waiting for KubeRay operator pod to be in Running state..."
    sleep 5
  done
  echo "KubeRay operator is ready."
fi

# 3. Set environment variables from the benchmark spec
echo "Setting environment variables..."
# Extract model URL and HF token from generated config file
if [ -f "../../4-latest-results/generated-kuberay-config.yaml" ]; then
  MODEL_URL=$(grep "modelURL:" "../../4-latest-results/generated-kuberay-config.yaml" | awk '{print $2}')
  HF_TOKEN=$(grep "hf_token:" "../../4-latest-results/generated-kuberay-config.yaml" | awk '{print $2}')

  # Export as environment variables
  export MODEL_URL=$MODEL_URL
  export HF_TOKEN=$HF_TOKEN

  # Create a Kubernetes secret for the HF token
  kubectl create secret generic hf-token --from-literal=token=$HF_TOKEN --dry-run=client -o yaml | kubectl apply -f -
else
  echo "Warning: Generated config not found. Using default model and no token."
  export MODEL_URL="meta-llama/Llama-3.1-8B-Instruct"
  export HF_TOKEN="<YOUR_HF_TOKEN>"
fi

# Setting environment variables
echo "Setting environment variables..."
export RAY_HEAD_POD_NAME=rayservice-sample-raycluster
export API_PORT=8000
export LLM_SERVICE_NAMESPACE=default
export SERVICE_CREATION_TIMEOUT=600  # Increase timeout to 10 minutes

# Set HF_TOKEN environment variable if available
# Note: If not provided, the script will proceed without a token
if [ -z "$HF_TOKEN" ]; then
  echo "Warning: No HF_TOKEN environment variable set. Defaulting to model without token."
fi

# Create ConfigMap for the LLM API script
echo "Creating ConfigMap for LLM API script..."
kubectl create configmap llm-api-script --from-file=llm_api.py=./llm_api.py

# Apply the Ray service configuration
echo "Applying Ray service configuration..."
kubectl apply -f ray-service.yaml

# Wait for the service to be created
echo "Waiting for Ray service to be created (this may take a few minutes)..."
sleep 20  # Initial wait before checking status

# Print Ray service details
echo "Checking the status of Ray service..."
kubectl get rayservice
kubectl get pods

# Show logs from the head pod for debugging
echo "Checking logs from the head pod (may be incomplete if still starting)..."
HEAD_POD=$(kubectl get pods | grep "${RAY_HEAD_POD_NAME}" | grep head | awk '{print $1}' | head -n 1)
if [ -n "$HEAD_POD" ]; then
  kubectl logs $HEAD_POD || echo "No logs available yet from head pod"
else
  echo "Head pod not found yet, skipping logs"
fi

echo "Waiting for pods to become ready..."
TIMEOUT=$SERVICE_CREATION_TIMEOUT
INTERVAL=15
elapsed=0

while [ $elapsed -lt $TIMEOUT ]; do
  if kubectl get pods | grep "${RAY_HEAD_POD_NAME}" | grep " 1/1 " > /dev/null; then
    echo "Ray service is ready!"
    break
  else
    echo "Ray service is not ready yet. Waiting $INTERVAL seconds..."
    sleep $INTERVAL
    elapsed=$((elapsed + INTERVAL))

    # Print pod status every check
    echo "Current pod status:"
    kubectl get pods | grep "${RAY_HEAD_POD_NAME}"
  fi
done

if [ $elapsed -ge $TIMEOUT ]; then
  echo "Timeout waiting for Ray service to be ready."
  echo "Detailed pod status:"
  kubectl get pods -o wide
  echo "Logs from available pods:"
  for pod in $(kubectl get pods | grep "${RAY_HEAD_POD_NAME}" | awk '{print $1}'); do
    echo "=== Logs from $pod ==="
    kubectl logs $pod || echo "Failed to get logs from $pod"
  done
  exit 1
fi

# Display service information
echo "Ray Service Information:"
kubectl get rayservice
kubectl get service

# Set up port forwarding in the background
echo "Setting up port forwarding to access the Ray dashboard and HTTP API..."
kubectl port-forward service/rayservice-service 8265:8265 &
DASHBOARD_PID=$!
kubectl port-forward service/rayservice-service $API_PORT:$API_PORT &
API_PID=$!

# Wait for port-forwarding to be established
echo "Waiting for port-forwarding to be established..."
sleep 5

echo "======================================"
echo "Ray dashboard available at: http://localhost:8265"
echo "Ray HTTP service available at: http://localhost:$API_PORT"
echo "======================================"

# Test the API
echo "Testing the API..."
echo "GET request to /v1/models:"
curl -s http://localhost:$API_PORT/v1/models | jq || echo "Failed to get response from models endpoint"

echo "POST request to /v1/chat/completions:"
curl -s -X POST http://localhost:$API_PORT/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama/Llama-3.1-8B-Instruct",
    "messages": [{"role": "user", "content": "What is Ray?"}]
  }' | jq || echo "Failed to get response from chat completions endpoint"

echo "======================================"
echo "Press Ctrl+C to stop the port forwarding when done"
echo "======================================"

# Keep the script running to maintain port-forwarding
trap "kill $DASHBOARD_PID $API_PID 2>/dev/null" EXIT
wait $DASHBOARD_PID $API_PID