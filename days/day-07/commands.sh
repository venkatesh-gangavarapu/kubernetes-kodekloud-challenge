#!/usr/bin/env bash
# =============================================================================
# Day 07 — Kubernetes Challenge: Create a ReplicaSet
# Task: httpd-replicaset, httpd:latest, httpd-container, replicas=4
#       Labels: app=httpd_app, type=front-end
# Platform: KodeKloud lab | kubectl on jump-host
#
# KEY INSIGHT FOR THIS TASK:
#   There is NO 'kubectl create replicaset' command.
#   Unlike Pods (kubectl run), Deployments (kubectl create deployment), and
#   Namespaces (kubectl create namespace) — ReplicaSet has no imperative
#   shortcut. The ONLY approach is writing the YAML manifest directly.
#   This task tests manifest fluency, not flag knowledge.
#
# MANIFEST STRUCTURE RULE:
#   Both labels (app=httpd_app, type=front-end) must appear in THREE places:
#     1. metadata.labels         (on the ReplicaSet object itself)
#     2. spec.selector.matchLabels  (how RS finds/claims its Pods)
#     3. spec.template.metadata.labels  (applied to each Pod created)
#   A mismatch between matchLabels and template labels = infinite Pod loop.
# =============================================================================
set -e

# ─── STEP 1: Verify cluster access ───────────────────────────────────────────
echo "=== Step 1: Cluster connectivity check ==="
kubectl get nodes
echo ""

# ─── STEP 2: Clean up any previous attempt ───────────────────────────────────
# A failed attempt may have left a ReplicaSet or loose Pods behind.
# Deleting the RS cascades: Pods it owns are garbage-collected.
echo "=== Step 2: Clean up any previous attempt ==="
if kubectl get replicaset httpd-replicaset -n default &>/dev/null; then
  echo "Found existing httpd-replicaset — deleting before recreating"
  kubectl delete replicaset httpd-replicaset -n default
  echo "Waiting for RS Pods to terminate..."
  sleep 5
else
  echo "No pre-existing httpd-replicaset found — proceeding"
fi
echo ""

# ─── STEP 3: Write the ReplicaSet manifest ───────────────────────────────────
# There is no kubectl create replicaset command — write the YAML directly.
# apiVersion must be apps/v1, NOT v1 (v1 = core group: Pods/Namespaces/Services).
# Both labels appear in all three required locations.
echo "=== Step 3: Write httpd-replicaset.yaml ==="
cat > httpd-replicaset.yaml << 'EOF'
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: httpd-replicaset
  namespace: default
  labels:
    app: httpd_app        # label on the ReplicaSet object itself
    type: front-end
spec:
  replicas: 4             # desired pod count
  selector:
    matchLabels:          # RS claims pods matching these labels
      app: httpd_app      # must exactly match template.metadata.labels
      type: front-end
  template:               # pod template used when RS creates new pods
    metadata:
      labels:
        app: httpd_app    # must exactly match selector.matchLabels
        type: front-end
    spec:
      containers:
        - name: httpd-container   # explicit container name required by task
          image: httpd:latest
          ports:
            - containerPort: 80
EOF

echo "Manifest written:"
cat httpd-replicaset.yaml
echo ""

# ─── STEP 4: Apply the manifest ──────────────────────────────────────────────
echo "=== Step 4: Apply httpd-replicaset.yaml ==="
kubectl apply -f httpd-replicaset.yaml
echo ""

# ─── STEP 5: Wait for all 4 replicas to be Ready ─────────────────────────────
# httpd:latest needs to be pulled on each node — allow 90 seconds.
# jsonpath wait for readyReplicas to reach 4 is more precise than a sleep.
echo "=== Step 5: Wait for 4 ready replicas ==="
echo "Waiting for readyReplicas=4 (timeout 90s)..."
SECONDS_WAITED=0
until [ "$(kubectl get replicaset httpd-replicaset -n default \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "4" ]; do
  sleep 3
  SECONDS_WAITED=$((SECONDS_WAITED + 3))
  if [ $SECONDS_WAITED -ge 90 ]; then
    echo "Timeout: ReplicaSet did not reach 4 ready replicas in 90s"
    kubectl describe replicaset httpd-replicaset -n default
    exit 1
  fi
  echo "  Waiting... (${SECONDS_WAITED}s elapsed)"
done
echo "✅ All 4 replicas are ready"
echo ""

# ─── STEP 6: Verify ReplicaSet status ────────────────────────────────────────
# DESIRED, CURRENT, and READY must all equal 4.
echo "=== Step 6: ReplicaSet status ==="
kubectl get replicaset httpd-replicaset -n default
echo ""

# ─── STEP 7: Verify labels on the ReplicaSet ─────────────────────────────────
# Both app=httpd_app and type=front-end must be present.
echo "=== Step 7: Verify ReplicaSet labels ==="
kubectl get replicaset httpd-replicaset -n default --show-labels
echo ""

# ─── STEP 8: Verify all 4 pods are Running ───────────────────────────────────
# -l app=httpd_app filters to only RS-owned pods.
echo "=== Step 8: Verify all 4 pods are Running ==="
kubectl get pods -n default -l app=httpd_app
echo ""

# ─── STEP 9: Verify pod labels ───────────────────────────────────────────────
# Both labels must be on every pod created by the RS.
echo "=== Step 9: Verify pod labels ==="
kubectl get pods -n default -l "app=httpd_app,type=front-end" --show-labels
echo ""

# ─── STEP 10: Verify container name ──────────────────────────────────────────
echo "=== Step 10: Verify container name ==="
CONTAINER_NAME=$(kubectl get replicaset httpd-replicaset -n default \
  -o jsonpath='{.spec.template.spec.containers[0].name}')
echo "Container name: ${CONTAINER_NAME}"

if [ "${CONTAINER_NAME}" == "httpd-container" ]; then
  echo "✅ Container name correct: httpd-container"
else
  echo "❌ Container name mismatch: expected httpd-container, got ${CONTAINER_NAME}"
  exit 1
fi
echo ""

# ─── STEP 11: Verify image tag ────────────────────────────────────────────────
echo "=== Step 11: Verify image tag ==="
IMAGE=$(kubectl get replicaset httpd-replicaset -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "Image: ${IMAGE}"

if [ "${IMAGE}" == "httpd:latest" ]; then
  echo "✅ Image correct: httpd:latest"
else
  echo "❌ Image mismatch: expected httpd:latest, got ${IMAGE}"
  exit 1
fi
echo ""

# ─── STEP 12: Verify replica count in spec ────────────────────────────────────
echo "=== Step 12: Verify replica count ==="
REPLICAS=$(kubectl get replicaset httpd-replicaset -n default \
  -o jsonpath='{.spec.replicas}')
echo "Desired replicas: ${REPLICAS}"

if [ "${REPLICAS}" == "4" ]; then
  echo "✅ Replica count correct: 4"
else
  echo "❌ Replica count mismatch: expected 4, got ${REPLICAS}"
  exit 1
fi
echo ""

# ─── STEP 13: Full describe ───────────────────────────────────────────────────
# Look for: Replicas, Labels, Selector, Pod Template image and container name.
echo "=== Step 13: Full describe ==="
kubectl describe replicaset httpd-replicaset -n default
echo ""

echo "============================================"
echo "All verification steps passed."
echo "ReplicaSet httpd-replicaset:"
echo "  replicas:       4/4 ready"
echo "  image:          httpd:latest"
echo "  container name: httpd-container"
echo "  labels:         app=httpd_app, type=front-end"
echo "============================================"

# ─── CLEANUP (commented — run manually when done) ────────────────────────────
# Deleting RS cascades — all 4 pods are garbage-collected.
# kubectl delete replicaset httpd-replicaset -n default
# kubectl delete -f httpd-replicaset.yaml
# rm -f httpd-replicaset.yaml
