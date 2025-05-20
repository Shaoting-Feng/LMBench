KubeRay:

helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update
# Install both CRDs and KubeRay operator v1.3.0.
helm install kuberay-operator kuberay/kuberay-operator --version 1.3.0

kubectl apply -f https://raw.githubusercontent.com/ray-project/kuberay/v1.3.0/ray-operator/config/samples/ray-service.sample.yaml


See something like this:
ubuntu@137-131-5-20:~/RayServeExperimentation$ kubectl get raycluster
NAME                                 DESIRED WORKERS   AVAILABLE WORKERS   CPUS    MEMORY   GPUS   STATUS   AGE
rayservice-sample-raycluster-m54x7   1                 1                   2500m   4Gi      0      ready    3m5s
ubuntu@137-131-5-20:~/RayServeExperimentation$ kubectl get rayservice
NAME                SERVICE STATUS   NUM SERVE ENDPOINTS
rayservice-sample   Running          2
ubuntu@137-131-5-20:~/RayServeExperimentation$ kubectl get pods -l=ray.io/is-ray-node=yes
NAME                                                          READY   STATUS    RESTARTS   AGE
rayservice-sample-raycluster-m54x7-head-n6q4m                 1/1     Running   0          3m15s
rayservice-sample-raycluster-m54x7-small-group-worker-jp8hg   1/1     Running   0          3m15s


kubectl get rayservice rayservice-sample -o json | jq -r '.status.conditions[] | select(.type=="Ready") | to_entries[] | "\(.key): \(.value)"'

tatus.conditions[] | select(.type=="Ready") | to_entries[] | "\(.key): \(.value)"'
lastTransitionTime: 2025-05-19T22:39:43Z
message: Number of serve endpoints is greater than 0
observedGeneration: 1
reason: NonZeroServeEndpoints
status: True
type: Ready



kubectl get services -o json | jq -r '.items[].metadata.name'

kubectl run curl --image=curlimages/curl --command -- tail -f /dev/null

# Step 6.3: Send a request to the calculator app.
kubectl exec curl -- curl -sS -X POST -H 'Content-Type: application/json' rayservice-sample-serve-svc:8000/calc/ -d '["MUL", 3]'

15 pizzas please!

# Step 6.2: Send a request to the fruit stand app.
kubectl exec curl -- curl -sS -X POST -H 'Content-Type: application/json' rayservice-sample-serve-svc:8000/fruit/ -d '["MANGO", 2]'

6

ubuntu@137-131-5-20:~/RayServeExperimentation$ kubectl get pods
NAME                                                          READY   STATUS    RESTARTS   AGE
curl                                                          1/1     Running   0          4h41m
kuberay-operator-86787646f6-pwb7j                             1/1     Running   0          4h49m
rayservice-sample-raycluster-m54x7-head-n6q4m                 1/1     Running   0          4h49m
rayservice-sample-raycluster-m54x7-small-group-worker-jp8hg   1/1     Running   0          4h49m