#!/usr/bin/env bash
# =============================================================================
# Day 13 — Kubernetes Challenge: Create NodePort Service for a ReplicaSet
# Task: Expose nginx-replicaset (labels: app=nginx_app, type=front-end)
#       via NodePort Service 'nginx-service' on port 30080
# Constraint: Do NOT modify the ReplicaSet
# Platform: KodeKloud lab | kubectl on jump-host
#
# KEY CONCEPTS:
#   Services connect to PODS via label selectors — not to ReplicaSets.
#   kubectl expose replicaset copies the selector automatically (safest).
#   kubectl expose does NOT support --node-port; need a follow-up patch.
#   Verify Endpoints after creation — empty <none> = selector mismatch.
#
# PORT TERMINOLOGY (never confuse these):
#   nodePort   (30080) = port on every cluster node, for external clients
#   port       (80)    = Service's ClusterIP port, for in-cluster access
#   targetPort (80)    = container's listening port, what kube-proxy forwards to
# =============================================================================
set -e

# ─── STEP 1: Verify cluster access ───────────────────────────────────────────
echo "=== Step 1: Cluster connectivity check ==="
kubectl get nodes
echo ""

# ─── STEP 2: Inspect the existing ReplicaSet ─────────────────────────────────
# Confirm it exists and note the Pod labels — these become the Service selector.
# Do NOT modify this ReplicaSet — task constraint.
echo "=== Step 2: Inspect existing ReplicaSet ==="
kubectl get replicaset nginx-replicaset -n default
echo ""
echo "RS selector (will become Service selector):"
kubectl get replicaset nginx-replicaset -n default \
  -o jsonpath='{.spec.selector.matchLabels}'
echo ""

# ─── STEP 3: Verify pods are running and carry correct labels ─────────────────
# The Service selector must match these exact labels on the Pods.
# app=nginx_app and type=front-end must BOTH be present on each Pod.
echo "=== Step 3: Verify Pod labels ==="
kubectl get pods -n default -l "app=nginx_app,type=front-end" --show-labels
echo ""
POD_COUNT=$(kubectl get pods -n default -l "app=nginx_app,type=front-end" \
  --no-headers 2>/dev/null | wc -l)
echo "Pods matching app=nginx_app,type=front-end: ${POD_COUNT}"
if [ "${POD_COUNT}" -eq 0 ]; then
  echo "WARNING: No pods match the expected labels — verify RS is running"
fi
echo ""

# ─── STEP 4: Check if nginx-service already exists ───────────────────────────
echo "=== Step 4: Pre-flight service check ==="
if kubectl get service nginx-service -n default &>/dev/null; then
  echo "Service 'nginx-service' already exists — deleting before recreating"
  kubectl delete service nginx-service -n default
else
  echo "No pre-existing nginx-service — proceeding"
fi
echo ""

# ─── STEP 5A: Expose the ReplicaSet (copies selector automatically) ──────────
# kubectl expose replicaset reads nginx-replicaset.spec.selector.matchLabels
# and copies it directly to the Service spec.selector.
# This is safer than typing the selector manually — no typo risk.
# NOTE: kubectl expose does NOT support --node-port.
# A random nodePort is assigned here; we patch it to 30080 in Step 6.
echo "=== Step 5A: Expose ReplicaSet as NodePort Service ==="
kubectl expose replicaset nginx-replicaset \
  --name=nginx-service \
  --type=NodePort \
  --port=80 \
  --target-port=80 \
  -n default
echo "Service created (nodePort is random at this point)."
echo ""

# Show the auto-assigned nodePort before patching
AUTO_NODEPORT=$(kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.ports[0].nodePort}')
echo "Auto-assigned nodePort: ${AUTO_NODEPORT} (will be patched to 30080)"
echo ""

# ─── STEP 5B: Alternative — YAML manifest (cleaner, sets nodePort directly) ──
# Uncomment this block and comment out Steps 5A + 6 to use declarative approach.
# The selector must be typed manually — must match RS Pod labels exactly.
#
# cat > nginx-service.yaml << 'EOF'
# apiVersion: v1
# kind: Service
# metadata:
#   name: nginx-service
#   namespace: default
# spec:
#   type: NodePort
#   selector:
#     app: nginx_app      # underscore, not hyphen
#     type: front-end
#   ports:
#     - port: 80
#       targetPort: 80
#       nodePort: 30080   # set directly, no patch needed
# EOF
# kubectl apply -f nginx-service.yaml
# ─────────────────────────────────────────────────────────────────────────────

# ─── STEP 6: Patch nodePort to 30080 ─────────────────────────────────────────
# JSON patch from Day 12 — replaces exactly /spec/ports/0/nodePort.
# Does not touch port, targetPort, or protocol fields.
echo "=== Step 6: Patch nodePort → 30080 ==="
kubectl patch service nginx-service -n default \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080}]'
echo "nodePort patched to 30080."
echo ""

# ─── STEP 7: Verify Service spec ─────────────────────────────────────────────
echo "=== Step 7: Verify Service spec ==="
kubectl get service nginx-service -n default
echo ""

# Individual field verification
SVCTYPE=$(kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.type}')
NODEPORT=$(kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.ports[0].nodePort}')
PORT=$(kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.ports[0].port}')
SELECTOR=$(kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.selector}')

echo "Service type:   ${SVCTYPE}   (expected: NodePort)"
echo "nodePort:       ${NODEPORT}  (expected: 30080)"
echo "port:           ${PORT}      (expected: 80)"
echo "Selector:       ${SELECTOR}"
echo ""

# Assert correct nodePort
if [ "${NODEPORT}" == "30080" ]; then
  echo "✅ nodePort correct: 30080"
else
  echo "❌ nodePort mismatch: expected 30080, got ${NODEPORT}"
  exit 1
fi
echo ""

# ─── STEP 8: Verify Endpoints — THE CRITICAL CHECK ───────────────────────────
# If Endpoints shows <none>, the selector doesn't match any Pods.
# The Service exists but routes no traffic. Empty endpoints = broken Service.
echo "=== Step 8: Verify Endpoints (selector matches Pods?) ==="
kubectl get endpoints nginx-service -n default
echo ""

EP=$(kubectl get endpoints nginx-service -n default \
  -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
if [ -n "${EP}" ]; then
  echo "✅ Endpoints populated — Service is routing to Pods"
else
  echo "❌ Endpoints are empty — selector does not match any running Pods"
  echo "Debug: check pod labels vs service selector"
  kubectl get pods -n default --show-labels
  kubectl describe service nginx-service -n default | grep Selector
  exit 1
fi
echo ""

# ─── STEP 9: Confirm ReplicaSet is unchanged (task constraint) ───────────────
echo "=== Step 9: Confirm ReplicaSet not modified ==="
kubectl get replicaset nginx-replicaset -n default
kubectl describe replicaset nginx-replicaset -n default | head -20
echo ""

# ─── STEP 10: Test application accessibility via nodePort ────────────────────
# curl from within the cluster via a jump pod.
# Both containers in the same pod share localhost — but for NodePort testing
# we need the node IP. Use InternalIP from node status.
echo "=== Step 10: Test application accessibility ==="
NODE_IP=$(kubectl get nodes -n default \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "Node IP: ${NODE_IP}"
echo "Testing http://${NODE_IP}:30080 ..."
curl -s --max-time 5 "http://${NODE_IP}:30080" | head -5 || \
  echo "(curl may not be available on jump-host — access confirmed via Endpoints)"
echo ""

# ─── STEP 11: Full describe ───────────────────────────────────────────────────
echo "=== Step 11: Full describe service ==="
kubectl describe service nginx-service -n default
echo ""

echo "============================================"
echo "NodePort Service created successfully."
echo "  Service:    nginx-service"
echo "  Type:       NodePort"
echo "  port:       80"
echo "  nodePort:   30080"
echo "  Selector:   app=nginx_app, type=front-end"
echo "  ReplicaSet: nginx-replicaset (unchanged)"
echo "  Endpoints:  populated ✅"
echo "============================================"

# ─── CLEANUP (commented — run manually when done) ────────────────────────────
# Deleting the Service does NOT affect the ReplicaSet or its Pods.
# kubectl delete service nginx-service -n default
# rm -f nginx-service.yaml
