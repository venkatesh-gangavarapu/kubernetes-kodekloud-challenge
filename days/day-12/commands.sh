#!/bin/bash
# ============================================================
# 100 Days of Cloud — Azure/K8s Challenge
# Day 14: Update nginx-deployment and nginx-service
# Three changes — no deletion:
#   1. NodePort:  30008 → 32165
#   2. Replicas:  1 → 5
#   3. Image:     nginx:1.17 → nginx:latest
# Run on: jump-host
# ============================================================

set -e

# ============================================================
# STEP 1: DOCUMENT PRE-CHANGE STATE
# Always snapshot state before mutating live resources
# ============================================================

echo "=== Step 1: Pre-change state ==="

echo "--- Deployment ---"
kubectl get deployment nginx-deployment -o wide
echo ""

echo "--- Replicas ---"
kubectl get deployment nginx-deployment \
    -o jsonpath='Replicas: {.spec.replicas}{"\n"}'

echo "--- Image ---"
kubectl get deployment nginx-deployment \
    -o jsonpath='Image: {.spec.template.spec.containers[0].image}{"\n"}'

echo "--- Service ---"
kubectl get service nginx-service -o wide
echo ""

echo "--- NodePort ---"
kubectl get service nginx-service \
    -o jsonpath='NodePort: {.spec.ports[0].nodePort}{"\n"}'

# ============================================================
# STEP 2: CHANGE 1 — NodePort 30008 → 32165
# Using kubectl patch with JSON Patch (RFC 6902)
# This is the safest way — targets exact path, no YAML download needed
# ============================================================

echo ""
echo "=== Step 2: NodePort 30008 → 32165 ==="

kubectl patch service nginx-service \
    --type='json' \
    -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":32165}]'

# Verify immediately
NODEPORT=$(kubectl get service nginx-service \
    -o jsonpath='{.spec.ports[0].nodePort}')
echo "NodePort is now: $NODEPORT"
[ "$NODEPORT" = "32165" ] && echo "✅ NodePort updated" || echo "⚠️  Unexpected: $NODEPORT"

# ============================================================
# STEP 3: CHANGE 2 — Replicas 1 → 5
# kubectl scale is the imperative shortcut
# ============================================================

echo ""
echo "=== Step 3: Replicas 1 → 5 ==="

kubectl scale deployment nginx-deployment --replicas=5

echo "Waiting for rollout..."
kubectl rollout status deployment/nginx-deployment

kubectl get deployment nginx-deployment \
    -o jsonpath='Ready replicas: {.status.readyReplicas}/5{"\n"}'

# ============================================================
# STEP 4: CHANGE 3 — Image nginx:1.17 → nginx:latest
# Must know the container name to use kubectl set image
# ============================================================

echo ""
echo "=== Step 4: Image nginx:1.17 → nginx:latest ==="

CONTAINER=$(kubectl get deployment nginx-deployment \
    -o jsonpath='{.spec.template.spec.containers[0].name}')
echo "Container name: $CONTAINER"

kubectl set image deployment/nginx-deployment \
    ${CONTAINER}=nginx:latest

echo "Waiting for rollout..."
kubectl rollout status deployment/nginx-deployment

# ============================================================
# STEP 5: FINAL VERIFICATION — all three changes confirmed
# ============================================================

echo ""
echo "=== Step 5: Final verification ==="

echo "--- Deployment ---"
kubectl get deployment nginx-deployment -o wide

echo ""
echo "--- Pods ---"
kubectl get pods -l app=nginx -o wide

echo ""
echo "--- Service ---"
kubectl get service nginx-service -o wide

REPLICAS=$(kubectl get deployment nginx-deployment \
    -o jsonpath='{.status.readyReplicas}')
IMAGE=$(kubectl get deployment nginx-deployment \
    -o jsonpath='{.spec.template.spec.containers[0].image}')
NODEPORT=$(kubectl get service nginx-service \
    -o jsonpath='{.spec.ports[0].nodePort}')

echo ""
echo "============================================"
[ "$NODEPORT" = "32165" ] \
    && echo "  NodePort:  ✅ $NODEPORT" \
    || echo "  NodePort:  ⚠️  $NODEPORT (expected 32165)"
[ "$REPLICAS" = "5" ] \
    && echo "  Replicas:  ✅ $REPLICAS/5 ready" \
    || echo "  Replicas:  ⚠️  $REPLICAS/5 ready"
[ "$IMAGE" = "nginx:latest" ] \
    && echo "  Image:     ✅ $IMAGE" \
    || echo "  Image:     ⚠️  $IMAGE (expected nginx:latest)"
echo "============================================"

# ============================================================
# ALTERNATIVE DECLARATIVE APPROACH (reference)
# Download YAML, edit, and apply — useful when changes are complex
# ============================================================

# kubectl get deployment nginx-deployment -o yaml > nginx-deployment.yaml
# kubectl get service nginx-service -o yaml > nginx-service.yaml
# # Edit: spec.replicas, spec.template.spec.containers[0].image, service nodePort
# kubectl apply -f nginx-deployment.yaml
# kubectl apply -f nginx-service.yaml
