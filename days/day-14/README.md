# Day 14 — Troubleshooting Nginx + PHP-FPM and kubectl cp

> #KodeKloud Kubernetes Challenge | Day 14 of 30

---

## 📌 The Task

| Requirement          | Value                               |
|----------------------|-------------------------------------|
| Pod name             | `nginx-phpfpm`                      |
| ConfigMap name       | `nginx-config`                      |
| Containers           | `nginx-container` + `php-fpm-container` |
| Goal 1               | Identify and fix all issues         |
| Goal 2               | Copy `/home/thor/index.php` from jump host to nginx-container document root |
| Goal 3               | Website accessible via browser      |

---

## 🧠 Core Concepts

### Four Bugs — Three in the ConfigMap, One in the Service

All four bugs were confirmed from actual lab output. The pod was Running (READY 2/2) throughout — every bug was pure configuration.

**Volume mount reality (from kubectl describe):**
```
php-fpm-container: shared-files → /var/www/html
nginx-container:   shared-files → /usr/share/nginx/html
```

**ConfigMap nginx.conf (broken):**
```nginx
listen 8099 default_server;                             ← Bug 1
root /var/www/html;                                     ← Bug 2
fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;  ← Bug 3
```

**Service nginx-service (broken):**
```yaml
ports:
  - nodePort: 30008
    port: 8099        ← Bug 4a
    targetPort: 8099  ← Bug 4b
```

---

### Bug 1 — `listen 8099` instead of `listen 80`

nginx was bound to port 8099. The Service (and the website button) routes to port 80. Every inbound connection was refused before nginx processed anything.

---

### Bug 2 — `root /var/www/html` wrong for nginx-container

`nginx-container` mounts `shared-files` at `/usr/share/nginx/html`. The ConfigMap told nginx to serve from `/var/www/html` — a path where the shared emptyDir is **not mounted** in nginx-container. nginx looked for PHP files in the wrong directory.

---

### Bug 3 — `SCRIPT_FILENAME $document_root` resolves to nginx's path

After fixing Bug 2, `$document_root` = `/usr/share/nginx/html`. nginx would tell PHP-FPM: execute `/usr/share/nginx/html/index.php`. But `php-fpm-container` mounts `shared-files` at `/var/www/html` — that path does not exist inside php-fpm-container. PHP-FPM cannot find the script.

Fix: hardcode PHP-FPM's actual mount path:
```nginx
fastcgi_param SCRIPT_FILENAME /var/www/html$fastcgi_script_name;
```

---

### Bug 4 — Service `port: 8099` and `targetPort: 8099`

**This is what caused the "website not accessible" failure after all three ConfigMap fixes.**

The Service was deployed when nginx listened on 8099. Both `port` (the ClusterIP port) and `targetPort` (the pod port to forward to) were set to 8099. After fixing nginx to listen on 80, the Service still forwarded traffic to pod port 8099 — where nginx no longer listened. Inbound traffic via nodePort 30008 → Service → pod:8099 → connection refused.

The tell: `curl http://localhost/index.php` from inside the pod returned **HTTP 200** — proving nginx and PHP-FPM were working correctly. But the Website button (which goes through the Service) still failed. When inside-pod works but nodePort doesn't — the Service is the broken link.

Fix:
```bash
kubectl patch service nginx-service -n default \
  --type='json' \
  -p='[
    {"op":"replace","path":"/spec/ports/0/port","value":80},
    {"op":"replace","path":"/spec/ports/0/targetPort","value":80}
  ]'
```

### The Complete Traffic Path (All Four Bugs Fixed)

```
Browser → NodePort 30008
              ↓
          Service port: 80       (Bug 4a fixed — was 8099)
          targetPort: 80         (Bug 4b fixed — was 8099)
              ↓
          nginx-container: listen 80    (Bug 1 fixed)
          root /usr/share/nginx/html    (Bug 2 fixed)
              ↓ (.php requests)
          SCRIPT_FILENAME /var/www/html/index.php   (Bug 3 fixed)
              ↓
          php-fpm-container:9000 → finds /var/www/html/index.php ✅
              ↓
          HTTP 200 PHP response → nginx → Browser ✅
```

### The Two-Test Discipline

Always test both paths after a fix:

| Test | Command | What it tests |
|------|---------|--------------|
| Internal | `kubectl exec -c nginx-container -- curl http://localhost/index.php` | nginx + PHP-FPM directly, **bypasses Service** |
| External | `curl http://<node-ip>:<nodePort>/` | Full path: Service → targetPort → nginx |

If internal works but external fails → bug is in the Service. This distinction caught Bug 4.

### SubPath Mount — ConfigMap Changes Never Live-Update

`path="nginx.conf"` in describe = subPath mount. Written once at container start. Editing the ConfigMap has no effect on the running nginx. Pod must be deleted and recreated.

### Bare Pod — No Auto-Recreate

No `Controlled By:` in describe = bare pod. `kubectl delete pod nginx-phpfpm` removes it permanently. **Always export before deleting.**

---

## 🔧 Step-by-Step Solution

### Phase 1 — Full Diagnosis (All Four Bugs)

**Step 1 — Volume mount paths**
```bash
kubectl get pod nginx-phpfpm -n default \
  -o jsonpath='{range .spec.containers[*]}{.name}{"\n"}{range .volumeMounts[*]}  {.name} → {.mountPath}{"\n"}{end}{end}'
```

**Step 2 — ConfigMap** (Bugs 1, 2, 3)
```bash
kubectl get configmap nginx-config -n default -o yaml
```

**Step 3 — Service** (Bug 4) — always check this
```bash
kubectl get service nginx-service -n default -o yaml
```
Look at `port:` and `targetPort:` — both must match what nginx listens on.

---

### Phase 2 — Fix the Service (No Pod Restart Needed)

**Step 4 — Patch both `port` and `targetPort` to 80**
```bash
kubectl patch service nginx-service -n default \
  --type='json' \
  -p='[
    {"op":"replace","path":"/spec/ports/0/port","value":80},
    {"op":"replace","path":"/spec/ports/0/targetPort","value":80}
  ]'
```

**Verify:**
```bash
kubectl get service nginx-service -n default
# Expected: 80:30008/TCP
```

---

### Phase 3 — Export Pod Spec Before Touching It

**Step 5 — Export the bare pod spec**
```bash
kubectl get pod nginx-phpfpm -n default -o yaml > nginx-phpfpm-backup.yaml
```

---

### Phase 4 — Fix the ConfigMap (Three Changes)

**Step 6 — Edit nginx-config**
```bash
kubectl edit configmap nginx-config -n default
```

**Corrected nginx.conf:**
```nginx
events {
}
http {
  server {
    listen 80 default_server;
    listen [::]:80 default_server;
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
```

---

### Phase 5 — Restart the Pod

**Step 7 — Delete the pod** (subPath = no live update)
```bash
kubectl delete pod nginx-phpfpm -n default
```

**Step 8 — Recreate from backup** (bare pod — does NOT auto-recreate)
```bash
kubectl apply -f nginx-phpfpm-backup.yaml
kubectl wait pod/nginx-phpfpm --for=condition=Ready --timeout=90s -n default
```

**Step 9 — Verify all three ConfigMap fixes are live**
```bash
kubectl exec nginx-phpfpm -n default -c nginx-container \
  -- grep -E "listen|root|SCRIPT_FILENAME" /etc/nginx/nginx.conf
```

---

### Phase 6 — Copy the PHP File

**Step 10 — Copy to nginx document root**
```bash
kubectl cp /home/thor/index.php \
  nginx-phpfpm:/usr/share/nginx/html/index.php \
  -c nginx-container \
  -n default
```

---

### Phase 7 — Verify Both Paths

**Step 11 — Internal test** (bypasses Service)
```bash
kubectl exec nginx-phpfpm -n default -c nginx-container \
  -- curl -s http://localhost/index.php | head -5
```

**Step 12 — External test** (full traffic path through Service)
```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl http://${NODE_IP}:30008/
```

---

## 💻 Commands Reference

```bash
# ── Full diagnosis ──────────────────────────────────────────────────────────
kubectl describe pod nginx-phpfpm -n default
kubectl get configmap nginx-config -n default -o yaml
kubectl get service nginx-service -n default -o yaml   # ALWAYS check Service
kubectl get pod nginx-phpfpm -n default \
  -o jsonpath='{range .spec.containers[*]}{.name}{"\n"}{range .volumeMounts[*]}  {.name} → {.mountPath}{"\n"}{end}{end}'

# ── Fix Service (no restart) ────────────────────────────────────────────────
kubectl patch service nginx-service -n default \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/port","value":80},{"op":"replace","path":"/spec/ports/0/targetPort","value":80}]'
kubectl get service nginx-service -n default   # verify: 80:30008/TCP

# ── Export bare pod spec ────────────────────────────────────────────────────
kubectl get pod nginx-phpfpm -n default -o yaml > nginx-phpfpm-backup.yaml

# ── Fix ConfigMap ───────────────────────────────────────────────────────────
kubectl edit configmap nginx-config -n default
# listen 8099 → 80
# root /var/www/html → root /usr/share/nginx/html
# SCRIPT_FILENAME $document_root → /var/www/html

# ── Delete + recreate ───────────────────────────────────────────────────────
kubectl delete pod nginx-phpfpm -n default
kubectl apply -f nginx-phpfpm-backup.yaml
kubectl wait pod/nginx-phpfpm --for=condition=Ready --timeout=90s -n default

# ── Verify fixes live ───────────────────────────────────────────────────────
kubectl exec nginx-phpfpm -n default -c nginx-container \
  -- grep -E "listen|root|SCRIPT_FILENAME" /etc/nginx/nginx.conf

# ── Copy PHP file ───────────────────────────────────────────────────────────
kubectl cp /home/thor/index.php \
  nginx-phpfpm:/usr/share/nginx/html/index.php \
  -c nginx-container -n default

# ── Two-path verification ───────────────────────────────────────────────────
# Internal (bypasses Service):
kubectl exec nginx-phpfpm -n default -c nginx-container \
  -- curl -s http://localhost/index.php | head -3

# External (full path through Service):
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl http://${NODE_IP}:30008/
```

---

## ⚠️ Common Mistakes

1. **⚠️ CONFIRMED BUG 1 — `listen 8099` instead of `listen 80`**
   nginx bound to wrong port. Every connection to port 80 refused before nginx processed anything.

2. **⚠️ CONFIRMED BUG 2 — `root /var/www/html` wrong for nginx-container**
   nginx-container mounts `shared-files` at `/usr/share/nginx/html`. Serving from `/var/www/html` — not mounted there — meant nginx found no PHP files. Fix: `root /usr/share/nginx/html`.

3. **⚠️ CONFIRMED BUG 3 — `SCRIPT_FILENAME $document_root` uses nginx's path, not PHP-FPM's**
   `$document_root` = nginx's root = `/usr/share/nginx/html`. PHP-FPM only has `/var/www/html`. Path not found → blank page. Fix: `SCRIPT_FILENAME /var/www/html$fastcgi_script_name`.

4. **⚠️ CONFIRMED BUG 4 — Service `port: 8099` and `targetPort: 8099`**
   This caused the "Website not accessible" failure after all three ConfigMap fixes. Internal curl (`kubectl exec -- curl localhost`) returned HTTP 200 — proving nginx and PHP-FPM worked. But the website button (through the Service) still failed. `kubectl get service -o yaml` confirmed `targetPort: 8099` — the Service still forwarded to the old port. When inside-pod works but nodePort doesn't: the Service is always the suspect.

5. **Fixing only `targetPort` but not `port`**
   The Service had both `port: 8099` AND `targetPort: 8099`. The `port` field is the Service's ClusterIP port — used by in-cluster clients. `targetPort` is what gets forwarded to the pod. Both needed patching in a single `kubectl patch` with two operations.

6. **Deleting the bare pod without exporting first**
   No `Controlled By:` = bare pod. Export with `kubectl get pod -o yaml > backup.yaml` before `kubectl delete`. Then `kubectl apply -f backup.yaml` to recreate. Without this, the pod is permanently gone.

7. **Testing only from inside the pod, not via NodePort**
   `curl localhost` inside the pod bypasses the Service entirely. A passing internal test does not guarantee the website button works. Always run both: internal (proves nginx+PHP-FPM config) and external via NodePort (proves Service routing).

---

## 🌍 Real-World Context

This task produced the most realistic failure sequence in the challenge: a multi-layered configuration bug where fixing one layer revealed the next. Each fix exposed the next broken link:

```
Port 8099 blocks all traffic
  → Fix listen port → nginx reachable → but wrong root
    → Fix root → nginx serves files → but wrong SCRIPT_FILENAME
      → Fix SCRIPT_FILENAME → PHP works inside pod → but Service still routes to 8099
        → Fix Service targetPort → website accessible ✅
```

In production incident response this is called a **cascading fix** — and the key discipline is testing the full traffic path at each step, not just the layer you just fixed. The `kubectl exec -- curl localhost` test is fast and valuable, but it proves nothing about Service routing. Always follow it with a nodePort test.

The Service `port` vs `targetPort` distinction is a common source of confusion:
- `port` = what clients inside the cluster use to reach the Service ClusterIP
- `targetPort` = what port on the pod receives the forwarded traffic
- `nodePort` = what external clients (like the website button) use

All three must be consistent with what the application actually listens on.

---

## ❓ Interview Q&A

**Q1: The internal `curl localhost` returned HTTP 200, but the website button failed. How did you diagnose the Service as the issue?**
The internal curl bypasses the Service entirely — it hits nginx directly on localhost. When that works but the external path (nodePort → Service → pod) fails, the Service is the only remaining link. `kubectl get service -o yaml` confirmed `targetPort: 8099` while nginx was now listening on 80. Connection refused.

**Q2: What is the difference between `port` and `targetPort` in a Kubernetes Service?**
`port` is the Service's own port — what in-cluster clients (other pods, ClusterIP consumers) use to reach the Service. `targetPort` is the port on the pod container that the Service forwards traffic to — must match what the application actually listens on. In this task, both were 8099. After fixing nginx to listen on 80, both needed updating to 80.

**Q3: Why did you patch both `port` and `targetPort` and not just `targetPort`?**
Patching only `targetPort` fixes the pod-side routing but leaves `port: 8099`. In-cluster clients that call `nginx-service:8099` would fail. Changing both to 80 makes the Service consistent: external traffic hits nodePort 30008 → Service at 80 → pod port 80.

**Q4: How do you test whether a problem is in the pod vs the Service?**
Test from inside the pod with `kubectl exec`: `curl http://localhost/<path>`. This goes directly to the application, bypassing the Service entirely. If this returns a correct response, the pod configuration is sound. Then test via the Service: `curl http://<node-ip>:<nodePort>/<path>`. If inside works and outside fails, the Service is broken — check selector, endpoints, `port`, and `targetPort`.

**Q5: Why must the ConfigMap fix require a pod restart but the Service fix does not?**
The nginx.conf is a subPath-mounted ConfigMap key — it's written once at container start and never refreshed. Only a new container (pod restart) picks up ConfigMap changes via subPath. The Service is a separate API object — kube-proxy watches it and updates iptables/IPVS routing rules immediately when the Service spec changes. No application restart is involved.

**Q6: Why was the Service's `targetPort` set to 8099 in the first place?**
The Service was deployed alongside the original broken ConfigMap, when nginx was configured to listen on 8099. At that point, `targetPort: 8099` was the correct setting. Fixing the ConfigMap without updating the Service left the Service and the pod out of sync. This is a classic deployment drift problem — the two resources were created together but fixed independently.

**Q7: If you had to fix this in one command sequence without multiple attempts, what would the order be?**
Check Service first (`kubectl get service -o yaml`) and note `targetPort`. Check pod volumes and ConfigMap. Then: (1) patch the Service immediately — takes effect without restart; (2) export pod spec; (3) edit ConfigMap; (4) delete and reapply pod; (5) kubectl cp the PHP file; (6) verify both internal curl and external nodePort. The Service patch is first because it's instant and independent, and confirming it before the pod restart sequence avoids a second iteration.

---

## 📚 Resources

- [Kubernetes Docs — Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Kubernetes Docs — Volumes subPath](https://kubernetes.io/docs/concepts/storage/volumes/#using-subpath)
- [Kubernetes Docs — kubectl cp](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#cp)
- [Kubernetes Docs — kubectl patch](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/update-api-object-kubectl-patch/)
- **Related days:** [Day 12](../day-12/README.md) — kubectl patch for Service changes | [Day 13](../day-13/README.md) — Service port, targetPort, nodePort anatomy
