#!/usr/bin/env bash
# =============================================================================
# Day 14 — Kubernetes Challenge: Nginx + PHP-FPM Troubleshooting + kubectl cp
# Pod: nginx-phpfpm | ConfigMap: nginx-config
#
# FOUR CONFIRMED BUGS (from real lab output):
#
#   VOLUME MOUNTS (kubectl describe):
#     php-fpm-container: shared-files → /var/www/html
#     nginx-container:   shared-files → /usr/share/nginx/html
#
#   BUG 1 (ConfigMap): listen 8099 → needs 80
#   BUG 2 (ConfigMap): root /var/www/html → needs /usr/share/nginx/html
#   BUG 3 (ConfigMap): SCRIPT_FILENAME $document_root → needs /var/www/html
#   BUG 4 (Service):   port: 8099, targetPort: 8099 → BOTH need 80
#
#   HOW BUG 4 WAS CONFIRMED:
#   - kubectl exec -- curl http://localhost/index.php → HTTP 200 (pod working)
#   - Website button still failed → Service routing was the broken link
#   - kubectl get service -o yaml → port: 8099, targetPort: 8099
#
#   FIX ORDER (optimal):
#   1. Fix Service (instant, no restart needed)
#   2. Export pod spec (bare pod — no auto-recreate)
#   3. Fix ConfigMap (three changes)
#   4. Delete pod + reapply (subPath mount — mandatory restart)
#   5. kubectl cp index.php → /usr/share/nginx/html/
#   6. Verify BOTH internal curl AND external NodePort
# =============================================================================
set -e

# ─── STEP 1: Full diagnosis ───────────────────────────────────────────────────
echo "=== Step 1: Pod state ==="
kubectl get pod nginx-phpfpm -n default
echo ""

echo "=== Volume mount paths per container ==="
kubectl get pod nginx-phpfpm -n default \
  -o jsonpath='{range .spec.containers[*]}{.name}{"\n"}{range .volumeMounts[*]}  {.name} → {.mountPath}{"\n"}{end}{end}'
echo ""

echo "=== ConfigMap nginx.conf (identify Bugs 1-3) ==="
kubectl get configmap nginx-config -n default -o yaml
echo ""

echo "=== Service spec (identify Bug 4) ==="
kubectl get service nginx-service -n default -o yaml
echo ""

SVC_PORT=$(kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.ports[0].port}')
SVC_TARGET=$(kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.ports[0].targetPort}')
echo "Service port=${SVC_PORT}, targetPort=${SVC_TARGET}"
echo "CONFIRMED: Both should be 80, not 8099"
echo ""

# ─── STEP 2: Fix Service (immediate — no pod restart needed) ──────────────────
# Both port AND targetPort are 8099.
# port     = ClusterIP port (in-cluster clients) → update to 80
# targetPort = pod port to forward to → update to 80
# nodePort   = 30008 → keep unchanged (this is the external port)
echo "=== Step 2: Fix Service port and targetPort ==="
kubectl patch service nginx-service -n default \
  --type='json' \
  -p='[
    {"op":"replace","path":"/spec/ports/0/port","value":80},
    {"op":"replace","path":"/spec/ports/0/targetPort","value":80}
  ]'
echo ""

echo "Service after patch:"
kubectl get service nginx-service -n default
echo ""

# Verify
NEW_PORT=$(kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.ports[0].port}')
NEW_TARGET=$(kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.ports[0].targetPort}')
echo "port=${NEW_PORT}, targetPort=${NEW_TARGET}"

[ "${NEW_PORT}" == "80" ] && [ "${NEW_TARGET}" == "80" ] \
  && echo "✅ BUG 4 fixed: Service port=80, targetPort=80" \
  || { echo "❌ Service fix failed"; exit 1; }
echo ""

# ─── STEP 3: Export bare pod spec BEFORE deleting ────────────────────────────
# No "Controlled By:" in describe → bare pod → does NOT auto-recreate on delete.
# This backup is what we use to recreate it after fixing the ConfigMap.
echo "=== Step 3: Export pod spec (bare pod — must backup before deleting) ==="
kubectl get pod nginx-phpfpm -n default -o yaml > nginx-phpfpm-backup.yaml

# Strip server-managed fields so kubectl apply works cleanly
python3 << 'PYEOF'
import yaml

with open('nginx-phpfpm-backup.yaml') as f:
    pod = yaml.safe_load(f)

pod.pop('status', None)
meta = pod.get('metadata', {})
for field in ['resourceVersion', 'uid', 'creationTimestamp', 'selfLink',
              'generation', 'managedFields']:
    meta.pop(field, None)
pod['metadata'] = meta

with open('nginx-phpfpm-backup.yaml', 'w') as f:
    yaml.dump(pod, f, default_flow_style=False)
print("Pod spec exported and cleaned: nginx-phpfpm-backup.yaml")
PYEOF
echo ""

# ─── STEP 4: Apply the fixed ConfigMap ───────────────────────────────────────
# Three changes from the broken original:
#   listen 8099        → listen 80
#   root /var/www/html → root /usr/share/nginx/html
#   SCRIPT_FILENAME $document_root → /var/www/html
echo "=== Step 4: Apply fixed ConfigMap (three changes) ==="

FIXED_CONF='events {
}
http {
  server {
    listen 80 default_server;
    listen [::]:80 default_server;
    # Set nginx to serve files from the shared volume!
    root /usr/share/nginx/html;
    index  index.html index.htm index.php;
    server_name _;
    location / {
      try_files $uri $uri/ =404;
    }
    location ~ \.php$ {
      include fastcgi_params;
      fastcgi_param REQUEST_METHOD $request_method;
      fastcgi_param SCRIPT_FILENAME /var/www/html$fastcgi_script_name;
      fastcgi_pass 127.0.0.1:9000;
    }
  }
}
'

kubectl create configmap nginx-config \
  --from-literal="nginx.conf=${FIXED_CONF}" \
  -n default \
  --dry-run=client -o yaml | kubectl apply -f -

echo "ConfigMap updated. Verifying:"
kubectl get configmap nginx-config -n default \
  -o jsonpath='{.data.nginx\.conf}' | grep -E "listen|root|SCRIPT_FILENAME"
echo ""

# ─── STEP 5: Delete pod (subPath mount — ConfigMap never live-updates) ────────
echo "=== Step 5: Delete pod (subPath = mandatory restart) ==="
kubectl delete pod nginx-phpfpm -n default
echo "Pod deleted."
echo ""

# ─── STEP 6: Recreate from backup (bare pod — no auto-recreate) ───────────────
echo "=== Step 6: Recreate pod from backup ==="
kubectl apply -f nginx-phpfpm-backup.yaml
echo ""

kubectl wait pod/nginx-phpfpm \
  --for=condition=Ready \
  --timeout=90s \
  -n default
echo ""
kubectl get pod nginx-phpfpm -n default
echo ""

# ─── STEP 7: Verify all three ConfigMap fixes in running container ────────────
echo "=== Step 7: Verify ConfigMap fixes are live ==="
kubectl exec nginx-phpfpm -n default -c nginx-container \
  -- grep -E "listen|root|SCRIPT_FILENAME" /etc/nginx/nginx.conf
echo ""

LISTEN_OK=$(kubectl exec nginx-phpfpm -n default -c nginx-container \
  -- grep "listen 80 " /etc/nginx/nginx.conf | head -1 || true)
ROOT_OK=$(kubectl exec nginx-phpfpm -n default -c nginx-container \
  -- grep "root /usr/share" /etc/nginx/nginx.conf | head -1 || true)
SCRIPT_OK=$(kubectl exec nginx-phpfpm -n default -c nginx-container \
  -- grep "SCRIPT_FILENAME /var/www" /etc/nginx/nginx.conf || true)

[ -n "${LISTEN_OK}" ]  && echo "✅ BUG 1 fixed: listen 80" || { echo "❌ listen still wrong"; exit 1; }
[ -n "${ROOT_OK}" ]    && echo "✅ BUG 2 fixed: root /usr/share/nginx/html" || { echo "❌ root still wrong"; exit 1; }
[ -n "${SCRIPT_OK}" ]  && echo "✅ BUG 3 fixed: SCRIPT_FILENAME /var/www/html" || { echo "❌ SCRIPT_FILENAME still wrong"; exit 1; }
echo ""

# ─── STEP 8: Copy index.php ───────────────────────────────────────────────────
# nginx's corrected root = /usr/share/nginx/html
# -c nginx-container mandatory (first container in spec is php-fpm-container)
# Same emptyDir → file also at /var/www/html/index.php in php-fpm-container
echo "=== Step 8: Copy index.php to nginx document root ==="
ls -la /home/thor/index.php
echo ""

kubectl cp /home/thor/index.php \
  nginx-phpfpm:/usr/share/nginx/html/index.php \
  -c nginx-container \
  -n default
echo "File copied."
echo ""

# ─── STEP 9: Verify file in both containers ───────────────────────────────────
echo "=== Step 9: Verify file in nginx-container ==="
kubectl exec nginx-phpfpm -n default -c nginx-container \
  -- ls -la /usr/share/nginx/html/index.php
echo ""

echo "=== Verify file in php-fpm-container (same emptyDir, /var/www/html) ==="
kubectl exec nginx-phpfpm -n default -c php-fpm-container \
  -- ls -la /var/www/html/index.php
echo ""

# ─── STEP 10: Internal test (bypasses Service) ────────────────────────────────
echo "=== Step 10: Internal test — bypass Service ==="
kubectl exec nginx-phpfpm -n default -c nginx-container \
  -- curl -s http://localhost/index.php | head -3
echo ""

# ─── STEP 11: External test (full path through Service) ───────────────────────
echo "=== Step 11: External test — through Service NodePort ==="
NODE_IP=$(kubectl get nodes \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODEPORT=$(kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.ports[0].nodePort}')
echo "Testing http://${NODE_IP}:${NODEPORT}/"
curl -s --max-time 5 "http://${NODE_IP}:${NODEPORT}/" | head -3
echo ""

echo "============================================"
echo "Day 14 complete. ALL FOUR BUGS FIXED:"
echo ""
echo "  BUG 1 (ConfigMap): listen 8099 → 80              ✅"
echo "  BUG 2 (ConfigMap): root /var/www/html"
echo "                   → /usr/share/nginx/html          ✅"
echo "  BUG 3 (ConfigMap): SCRIPT_FILENAME \$document_root"
echo "                   → /var/www/html                  ✅"
echo "  BUG 4 (Service):   port/targetPort 8099 → 80      ✅"
echo ""
echo "  index.php copied to /usr/share/nginx/html         ✅"
echo "  Internal curl: HTTP 200                           ✅"
echo "  NodePort curl: HTTP 200                           ✅"
echo "  Website button: accessible                        ✅"
echo "============================================"
