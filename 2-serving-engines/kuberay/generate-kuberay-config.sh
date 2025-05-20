#!/bin/bash

# This script generates the kuberay configuration based on the benchmark spec

# 1. go to the current directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 2. Set default values for required parameters
MODEL_URL="meta-llama/Llama-3.1-8B-Instruct"
HF_TOKEN=""
HEAD_GPUS=1
WORKER_GPUS=1
NUM_WORKERS=1
HEAD_CPUS=2
WORKER_CPUS=2
HEAD_MEMORY="4G"
WORKER_MEMORY="4G"
MODEL_CACHE_SIZE="20Gi"

# 3. Parse the parameters from the benchmark spec file
BENCHMARK_SPEC="../../bench-spec.yaml"
if [ -f "$BENCHMARK_SPEC" ]; then
  # Check if KubeRay is the selected baseline
  BASELINE=$(grep -A1 "Baseline:" "$BENCHMARK_SPEC" | tail -1 | awk '{print $2}')
  if [ "$BASELINE" == "KubeRay" ]; then
    echo "KubeRay is selected as the baseline."

    # Extract the configuration parameters
    MODEL_URL=$(grep -A10 "KubeRay:" "$BENCHMARK_SPEC" | grep "modelURL:" | awk '{print $2}')
    HF_TOKEN=$(grep -A10 "KubeRay:" "$BENCHMARK_SPEC" | grep "hf_token:" | awk '{print $2}')
    HEAD_GPUS=$(grep -A10 "KubeRay:" "$BENCHMARK_SPEC" | grep "headGPUs:" | awk '{print $2}')
    WORKER_GPUS=$(grep -A10 "KubeRay:" "$BENCHMARK_SPEC" | grep "workerGPUs:" | awk '{print $2}')
    NUM_WORKERS=$(grep -A10 "KubeRay:" "$BENCHMARK_SPEC" | grep "numWorkers:" | awk '{print $2}')
    HEAD_CPUS=$(grep -A10 "KubeRay:" "$BENCHMARK_SPEC" | grep "headCPUs:" | awk '{print $2}')
    WORKER_CPUS=$(grep -A10 "KubeRay:" "$BENCHMARK_SPEC" | grep "workerCPUs:" | awk '{print $2}')
    HEAD_MEMORY=$(grep -A10 "KubeRay:" "$BENCHMARK_SPEC" | grep "headMemory:" | awk '{print $2}')
    WORKER_MEMORY=$(grep -A10 "KubeRay:" "$BENCHMARK_SPEC" | grep "workerMemory:" | awk '{print $2}')
    MODEL_CACHE_SIZE=$(grep -A10 "KubeRay:" "$BENCHMARK_SPEC" | grep "modelCacheSize:" | awk '{print $2}')
  else
    echo "KubeRay is not the selected baseline (found $BASELINE). Using default values."
  fi
else
  echo "Benchmark spec file not found. Using default values."
fi

# 4. Generate the config file
OUTPUT_DIR="../../4-latest-results"
mkdir -p "$OUTPUT_DIR"

# Create the kuberay configuration yaml
cat > "$OUTPUT_DIR/generated-kuberay-config.yaml" << EOL
modelURL: $MODEL_URL
hf_token: $HF_TOKEN
headGPUs: $HEAD_GPUS
workerGPUs: $WORKER_GPUS
numWorkers: $NUM_WORKERS
headCPUs: $HEAD_CPUS
workerCPUs: $WORKER_CPUS
headMemory: $HEAD_MEMORY
workerMemory: $WORKER_MEMORY
modelCacheSize: $MODEL_CACHE_SIZE
EOL

echo "Generated KubeRay configuration at $OUTPUT_DIR/generated-kuberay-config.yaml"

# 5. Generate the Ray service YAML with the specified resources
cat > "ray-service.yaml" << EOL
apiVersion: ray.io/v1
kind: RayService
metadata:
  name: rayservice-sample
spec:
  serveConfigV2: |
    applications:
      - name: fruit
        route_prefix: /fruit
        import_path: fruit:deployment
        deployments:
          - name: FruitStand
            num_replicas: 1
            ray_actor_options:
              num_cpus: $WORKER_CPUS
              num_gpus: $WORKER_GPUS
      - name: calc
        route_prefix: /calc
        import_path: calculator:deployment
        deployments:
          - name: Calculator
            num_replicas: 1
            ray_actor_options:
              num_cpus: $WORKER_CPUS
              num_gpus: $WORKER_GPUS

  rayClusterConfig:
    headGroupSpec:
      rayStartParams:
        dashboard-host: "0.0.0.0"
      template:
        spec:
          containers:
          - name: ray-head
            image: rayproject/ray-ml:2.9.0-py310-gpu
            env:
            - name: MODEL_URL
              value: "$MODEL_URL"
            - name: HF_TOKEN
              value: "$HF_TOKEN"
            ports:
            - containerPort: 6379
              name: gcs
            - containerPort: 8265
              name: dashboard
            - containerPort: 10001
              name: client
            - containerPort: 8000
              name: serve
            resources:
              limits:
                cpu: "$HEAD_CPUS"
                memory: "$HEAD_MEMORY"
                nvidia.com/gpu: "$HEAD_GPUS"
              requests:
                cpu: "$HEAD_CPUS"
                memory: "$HEAD_MEMORY"
                nvidia.com/gpu: "$HEAD_GPUS"
            volumeMounts:
            - mountPath: /tmp/ray
              name: ray-logs
            - mountPath: /tmp/model_cache
              name: model-cache
          volumes:
          - name: ray-logs
            emptyDir: {}
          - name: model-cache
            emptyDir:
              medium: Memory
              sizeLimit: "$MODEL_CACHE_SIZE"

    workerGroupSpecs:
      - groupName: small-group
        replicas: $NUM_WORKERS
        minReplicas: 1
        maxReplicas: 10
        rayStartParams: {}
        template:
          spec:
            containers:
            - name: ray-worker
              image: rayproject/ray-ml:2.9.0-py310-gpu
              env:
              - name: MODEL_URL
                value: "$MODEL_URL"
              - name: HF_TOKEN
                value: "$HF_TOKEN"
              resources:
                limits:
                  cpu: "$WORKER_CPUS"
                  memory: "$WORKER_MEMORY"
                  nvidia.com/gpu: "$WORKER_GPUS"
                requests:
                  cpu: "$WORKER_CPUS"
                  memory: "$WORKER_MEMORY"
                  nvidia.com/gpu: "$WORKER_GPUS"
              volumeMounts:
              - mountPath: /tmp/ray
                name: ray-logs
              - mountPath: /tmp/model_cache
                name: model-cache
            volumes:
            - name: ray-logs
              emptyDir: {}
            - name: model-cache
              emptyDir:
                medium: Memory
                sizeLimit: "$MODEL_CACHE_SIZE"
EOL

echo "Generated Ray service configuration at ray-service.yaml"