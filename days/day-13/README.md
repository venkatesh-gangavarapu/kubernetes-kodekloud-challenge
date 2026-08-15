# Day 13 — Exposing a ReplicaSet with a NodePort Service

> #KodeKloud Kubernetes Challenge | Day 13 of 30

---

## 📌 The Task

| Requirement         | Value              |
|---------------------|--------------------|
| Existing ReplicaSet | `nginx-replicaset` |
| Pod labels          | `app=nginx_app`, `type=front-end` |
| Service name        | `nginx-service`    |
| Service type        | `NodePort`         |
| `port`              | `80`               |
| `targetPort`        | `80`               |
| `nodePort`          | `30080`            |
| Constraint          | Do not modify the ReplicaSet |
| Namespace           | `default`          |

---

## 🧠 Core Concepts

### Services Don't Connect to ReplicaSets — They Connect to Pods

This is the most important concept to understand in this task. A Service does **not** reference a ReplicaSet, Deployment, or any other controller object. It connects to **Pods directly** via **label selectors**.

When you create a Service with `selector: app: nginx_app`, Kubernetes continuously watches for Pods whose labels match that selector. It adds those Pods' IP addresses to the Service's **Endpoints** object. Traffic sent to the Service is load-balanced across all healthy matching Pods — regardless of which controller created them.

This design means:
- The same Service can sit in front of a ReplicaSet, a Deployment, or manually created Pods — as long as labels match
- The Service keeps working when Pods are replaced (rolling update, rescheduling) because the new Pods carry the same labels
- Getting the selector wrong is a silent failure — the Service exists, but its Endpoints list is empty, and traffic goes nowhere

### The Three Port Fields — Port, TargetPort, NodePort

This is consistently one of the most confused concepts in Kubernetes networking:

```
External client
      │
      ▼
  Node IP:30080        ← nodePort — port opened on every cluster node
      │
      ▼
Service ClusterIP:80   ← port — the Service's own port, used for cluster-internal access
      │
      ▼
Pod container:80       ← targetPort — the port the container process listens on
```

| Field | What it is | Who uses it |
|-------|-----------|------------|
| `nodePort` | Port opened on every node's external network interface | External clients, load balancers |
| `port` | The Service's ClusterIP port | Other Pods inside the cluster |
| `targetPort` | The port the container actually listens on | kube-proxy, when forwarding to the Pod |

In this task, all three are related to port 80 on the application side, but the exposure point is `nodePort: 30080`. A client outside the cluster reaches the application at `<node-IP>:30080`.

If `targetPort` is omitted from the manifest, it defaults to the same value as `port` — so `port: 80` without `targetPort` also works here since nginx/httpd listens on 80.

### Why `kubectl expose` Doesn't Support `--node-port`

`kubectl expose` is a convenience command that creates a Service from an existing resource. It copies the selector from the source resource (ReplicaSet in this case) automatically — which is extremely useful. But it has a limitation: **it does not accept a `--node-port` flag**.

When you run `kubectl expose --type=NodePort`, Kubernetes assigns a random nodePort from the valid range (30000–32767). To set a specific nodePort (30080), you must either:

1. **Expose first, then patch the nodePort** — two commands, but the selector is copied automatically
2. **Write the YAML directly** — one step, full control, selector must be typed manually

Both are documented below. Method 1 is faster in a lab; Method 2 is cleaner for version-controlled infrastructure.

### `kubectl expose replicaset` — The Selector Is Copied Automatically

When you expose a ReplicaSet:
```bash
kubectl expose replicaset nginx-replicaset --name=nginx-service --type=NodePort --port=80
```

Kubernetes reads `nginx-replicaset.spec.selector.matchLabels` and copies those key-value pairs directly into the Service's `spec.selector`. You do not need to type `app=nginx_app` and `type=front-end` manually — the command does it for you.

This is safer than writing the selector manually because there is no risk of a typo introducing a selector mismatch. Always prefer `kubectl expose` over writing a Service from scratch when an existing resource already has the correct selector.

### Verifying Service → Pod Connectivity via Endpoints

After creating the Service, the critical verification is not just `kubectl get service` — it is `kubectl get endpoints`:

```bash
kubectl get endpoints nginx-service -n default
```

An endpoint like `10.244.1.5:80,10.244.1.6:80` means the Service has found and registered the matching Pods. An empty `<none>` means the selector matched nothing — the Service exists but routes no traffic.

---

## 🔧 Step-by-Step Solution

### Method 1 — kubectl expose + patch (Imperative — Exam Technique)

**Step 1 — Verify cluster access and inspect the existing ReplicaSet**
```bash
kubectl get nodes
kubectl get replicaset nginx-replicaset -n default
```

**Step 2 — Confirm the ReplicaSet's Pod labels**

You need to know the exact labels so you can verify the Service selector will match:
```bash
kubectl get replicaset nginx-replicaset -n default \
  -o jsonpath='{.spec.selector.matchLabels}'
```
Expected: `{"app":"nginx_app","type":"front-end"}`

**Step 3 — Verify Pods are running and carry the correct labels**
```bash
kubectl get pods -n default --show-labels
kubectl get pods -n default -l "app=nginx_app,type=front-end"
```

**Step 4 — Expose the ReplicaSet as a NodePort Service**

`kubectl expose replicaset` copies the selector from the RS automatically:
```bash
kubectl expose replicaset nginx-replicaset \
  --name=nginx-service \
  --type=NodePort \
  --port=80 \
  --target-port=80 \
  -n default
```

This creates the Service but assigns a **random** nodePort (e.g. 31254). The next step sets it to the required 30080.

**Step 5 — Patch nodePort to 30080**

Use JSON patch from Day 12 — precise, no risk of overwriting adjacent port fields:
```bash
kubectl patch service nginx-service -n default \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080}]'
```

**Step 6 — Verify the Service**
```bash
kubectl get service nginx-service -n default
kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.ports[0].nodePort}'
```
Expected: `30080`

**Step 7 — Verify Endpoints (Pods registered)**
```bash
kubectl get endpoints nginx-service -n default
```
Expected: one entry per Pod IP, all on port 80. Empty `<none>` = selector mismatch.

---

### Method 2 — YAML Manifest Written Directly (Declarative — Full Control)

When you need a specific nodePort from the start, writing the YAML avoids the two-step expose+patch flow.

```yaml
# nginx-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: default
spec:
  type: NodePort
  selector:
    app: nginx_app        # must match ReplicaSet Pod labels exactly
    type: front-end       # both labels required — partial match is not enough
  ports:
    - port: 80            # Service ClusterIP port (cluster-internal access)
      targetPort: 80      # container port nginx/httpd listens on
      nodePort: 30080     # external port on every cluster node
```

**Apply and verify:**
```bash
kubectl apply -f nginx-service.yaml
kubectl get service nginx-service -n default
kubectl get endpoints nginx-service -n default
```

**Test accessibility:**
```bash
# Get any node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl http://${NODE_IP}:30080
```

---

## 💻 Commands Reference

```bash
# Pre-task inspection
kubectl get replicaset nginx-replicaset -n default
kubectl get replicaset nginx-replicaset -n default \
  -o jsonpath='{.spec.selector.matchLabels}'
kubectl get pods -n default --show-labels
kubectl get pods -n default -l "app=nginx_app,type=front-end"

# Method 1 — expose + patch
kubectl expose replicaset nginx-replicaset \
  --name=nginx-service \
  --type=NodePort \
  --port=80 \
  --target-port=80 \
  -n default
kubectl patch service nginx-service -n default \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080}]'

# Method 2 — declarative YAML
kubectl apply -f nginx-service.yaml

# Service verification
kubectl get service nginx-service -n default
kubectl describe service nginx-service -n default
kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.selector}'
kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.ports[0].nodePort}'

# Endpoint verification — CRITICAL
kubectl get endpoints nginx-service -n default
kubectl describe endpoints nginx-service -n default

# Accessibility test
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl http://${NODE_IP}:30080

# Confirm RS is unchanged (constraint check)
kubectl get replicaset nginx-replicaset -n default
kubectl describe replicaset nginx-replicaset -n default

# Cleanup (run manually when done)
# kubectl delete service nginx-service -n default
```

---

## ⚠️ Common Mistakes

1. **`kubectl expose` does not accept `--node-port` — a random port is assigned**
   `kubectl expose replicaset ... --type=NodePort` creates a NodePort Service but assigns a random port (e.g. 31254). The task requires `30080` specifically. Without a follow-up `kubectl patch` to set the nodePort, the Service exists but on the wrong port. Always verify `kubectl get service -o jsonpath='{.spec.ports[0].nodePort}'` before declaring success.

2. **Service Endpoints are empty — selector doesn't match Pod labels**
   `kubectl get service nginx-service` showing a ClusterIP and nodePort looks correct. But `kubectl get endpoints nginx-service` showing `<none>` means zero Pods matched the selector. Traffic hits the nodePort and goes nowhere. Causes: typo in the selector value (`nginx_app` vs `nginx-app`), missing one of the two labels, or labels set on the Service not matching what's actually on the Pods. Verify with `kubectl get pods --show-labels` before writing the selector.

3. **Confusing `port`, `targetPort`, and `nodePort`**
   These three fields are asked about constantly in CKA exams and interviews. `nodePort` is what external clients use. `port` is what Pods inside the cluster use to reach the Service. `targetPort` is what the container process actually listens on. In this task all three land near port 80, but they are independent fields with different purposes.

4. **Using `type: ClusterPort` instead of `type: NodePort`**
   There is no `ClusterPort` type. The correct value is `ClusterIP` (cluster-internal only) or `NodePort` (external exposure via node port). `NodePort` actually creates both — a ClusterIP for internal access AND a nodePort for external access. `LoadBalancer` creates all three.

5. **Attempting to modify the ReplicaSet when the Service selector doesn't match**
   The task explicitly says do not modify the ReplicaSet. When the Service endpoint list is empty, the instinct is to add or change labels on the RS. The correct fix is to update the Service selector to match the existing Pod labels — not the other way around.

6. **Writing `selector: app: nginx-app` instead of `selector: app: nginx_app`**
   The label value uses an underscore: `nginx_app`. A hyphen (`nginx-app`) is a different value. Kubernetes label selectors are case-sensitive and exact-match. `kubectl get pods -l app=nginx_app` returning results is the only reliable way to confirm your selector string is correct before using it in a Service manifest.

7. **Not testing `curl` against the nodePort after creation**
   `kubectl get service` and `kubectl get endpoints` both looking correct does not guarantee the application is actually accessible. The application might be running but not listening on port 80, or a NetworkPolicy might be blocking traffic. Always end with `curl http://<node-ip>:30080` from a context that can reach the cluster nodes.

---

## 🌍 Real-World Context

In production, NodePort Services are the least common Service type for external traffic. Production workloads typically use:
- **LoadBalancer** — cloud-provider provisioned external LB (AWS ALB/NLB, GCP LB)
- **Ingress** — HTTP/HTTPS routing with host and path rules, backed by an Ingress controller (nginx-ingress, Traefik, HAProxy)

NodePort's production use cases are:
- **Bare-metal clusters** where cloud LBs aren't available (MetalLB fills this gap)
- **Development environments** for quick external access without an Ingress controller
- **Internal microservices** that need to be reachable from outside the cluster but are behind a corporate firewall that only allows specific ports
- **CI/CD pipelines** running integration tests against a specific cluster port

The Service → Pods-via-labels design is what makes Kubernetes service discovery so powerful. A Service created today will automatically pick up Pods created tomorrow, next week, or after a failover — as long as the labels match. This is the foundation of blue-green deployments, canary releases, and zero-downtime upgrades: swap the Pods behind a stable Service, and clients never know a change happened.

---

## ❓ Interview Q&A

**Q1: What is a Kubernetes Service and why is it needed?**
Pods are ephemeral — they get new IP addresses when they restart or are rescheduled. A Service provides a stable network identity (ClusterIP, DNS name) that persists regardless of which Pods are currently running behind it. It also load-balances traffic across all matching Pods. Without a Service, every client would need to discover current Pod IPs dynamically, which is impractical at scale.

**Q2: What is the difference between ClusterIP, NodePort, and LoadBalancer service types?**
ClusterIP (the default) creates an internal-only virtual IP — reachable only from within the cluster. NodePort opens a port (30000–32767) on every cluster node and forwards traffic from `<node-IP>:<nodePort>` to the Service — accessible from outside the cluster. LoadBalancer provisions a cloud provider load balancer in front of the NodePort — the standard for production external traffic. Each type builds on the previous: a LoadBalancer Service also creates a NodePort, which also creates a ClusterIP.

**Q3: How does a Service know which Pods to route traffic to?**
Through label selectors. The Service's `spec.selector` defines key-value label pairs. The endpoints controller continuously watches Pods in the namespace and adds any Pod whose labels match the selector to the Service's Endpoints object. Traffic is round-robin load balanced across all healthy Pod IPs in the Endpoints list. No reference to ReplicaSets, Deployments, or controllers is needed.

**Q4: What does an empty Endpoints list (`<none>`) mean for a Service?**
No Pods in the namespace matched the Service's selector. Possible causes: wrong label key or value in the selector, Pods haven't started yet, Pods are in a different namespace, or no Pods exist with those labels at all. Check with `kubectl get pods --show-labels` and compare against `kubectl describe service <name>` Selector field. Traffic sent to the Service goes nowhere when Endpoints is empty.

**Q5: Why doesn't `kubectl expose` support setting a specific `nodePort` value?**
`kubectl expose` is a convenience command for quick Service creation. It exposes most common options (port, type, name, selector) but not every Service spec field. Setting a specific nodePort falls outside what the command supports — it lets the API server auto-assign one. For a specific nodePort, either use a YAML manifest or create the Service with `expose` and then `kubectl patch` to set the nodePort.

**Q6: What is the valid nodePort range and what happens if you use a port outside it?**
The default valid range is 30000–32767, configured by `--service-node-port-range` on the API server. Using a port outside this range (e.g. 80 or 8080) returns `The Service is invalid: spec.ports[0].nodePort: Invalid value`. The range was chosen to avoid conflict with ports commonly used by applications and system services.

**Q7: If you have 5 replicas behind a NodePort Service, how is traffic distributed?**
kube-proxy on each node implements the load balancing via iptables rules (or IPVS in newer clusters). Traffic arriving at `<node-IP>:nodePort` is randomly distributed across all Pod IPs listed in the Service's Endpoints — regardless of which node the Pod runs on. The traffic may be forwarded to a Pod on a different node transparently. IPVS mode supports more sophisticated load balancing algorithms (round-robin, least connections, shortest expected delay).

---

## 📚 Resources

- [Kubernetes Docs — Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Kubernetes Docs — NodePort](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport)
- [Kubernetes Docs — kubectl expose](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#expose)
- [Kubernetes Docs — Debugging Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)
- **Related days:** [Day 07](../day-07/README.md) — ReplicaSet (the resource being exposed) | [Day 12](../day-12/README.md) — kubectl patch for nodePort changes | [Day 01](../day-01/README.md) — Labels as selectors (the mechanism that connects Services to Pods)
