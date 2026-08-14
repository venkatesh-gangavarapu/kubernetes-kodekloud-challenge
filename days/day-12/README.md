# Day 12 — Modifying a Deployment and Service In-Place

> #KodeKloud Kubernetes Challenge | Day 12 of 30

---

## 📌 The Task

| Change | From | To |
|--------|------|----|
| Service `nginx-service` nodePort | `30008` | `32165` |
| Deployment `nginx-deployment` replicas | `1` | `5` |
| Deployment `nginx-deployment` image | `nginx:1.17` | `nginx:latest` |
| Constraint | Do NOT delete the deployment or service | — |

---

## 🧠 Core Concepts

### Three Changes, Three Different Tools

This task is a practical exercise in knowing which `kubectl` command to reach for based on what you need to change. Each of the three changes has an idiomatic imperative command that is faster and safer than exporting YAML, editing, and reapplying:

| Change | Idiomatic command | Why this tool |
|--------|-------------------|--------------|
| Service nodePort | `kubectl patch` | Surgical JSON/YAML patch on a specific field |
| Replica count | `kubectl scale` | Purpose-built for replica changes |
| Container image | `kubectl set image` | Purpose-built for image updates, triggers rolling update |

`kubectl edit` (which opens a text editor) is always an option but is the slowest path under lab time limits and the most prone to YAML syntax errors. Know the targeted commands.

### `kubectl patch` — Surgical Field Updates

`kubectl patch` applies a partial update to a resource's spec without touching any other fields. It supports three patch strategies:

| Strategy | Use case | Example |
|----------|---------|---------|
| `merge` (default) | Update specific fields by providing the path as nested YAML/JSON | `{"spec":{"replicas":5}}` |
| `json` | RFC 6902 JSON Patch — explicit operations (`replace`, `add`, `remove`) | `[{"op":"replace","path":"/spec/ports/0/nodePort","value":32165}]` |
| `strategic` | Kubernetes-aware merge that understands list semantics (e.g. containers by name) | Default for most resources |

For a Service nodePort change, the JSON patch is the most precise because it targets `spec.ports[0].nodePort` directly without risking overwriting other port fields.

### NodePort — What It Is and Its Valid Range

A NodePort Service exposes a port on every node in the cluster at a static port number. External traffic hitting `<any-node-IP>:<nodePort>` is forwarded to the Service's ClusterIP, which routes to the matching Pods.

The valid NodePort range is **30000–32767** (default, configurable via `--service-node-port-range` on the API server). Port `32165` is within this range. Port `30008` was previously within range too — this is a pure reassignment, not a range error.

Changing a NodePort takes effect immediately — no Pod restart required. The kube-proxy on each node updates its iptables/IPVS rules to reflect the new port.

### `kubectl scale` — Replica Changes Without Touching the Image

`kubectl scale` updates `spec.replicas` on a Deployment (or ReplicaSet, StatefulSet). It does not touch the Pod template, so no rolling update is triggered — new Pods are created directly using the existing template.

Going from 1 to 5 replicas:
- The ReplicaSet notices 4 Pods are missing
- Creates 4 new Pods simultaneously (subject to cluster capacity)
- No old Pods are terminated — all 5 run concurrently

This is different from a rolling update: no `maxUnavailable`/`maxSurge` applies to a pure scale-up.

### `kubectl set image` — Image Update Triggers a Rolling Update

Changing the container image is the most consequential of the three changes because it triggers a rolling update (Day 05). The Deployment controller:

1. Creates a new ReplicaSet with the updated image (`nginx:latest`)
2. Scales up the new RS while scaling down the old one
3. Respects `maxUnavailable`/`maxSurge` from the rolling update strategy
4. Keeps the old RS at 0 replicas for rollback

**Order matters for this task.** If you scale to 5 replicas first and then update the image, the rolling update has 5 Pods to cycle through — this takes longer but is the correct production pattern. If you update the image first and then scale, the scale-up creates Pods directly with the new image.

### Pre-Operation State Documentation

Before changing anything on a live system, capture the current state:
```bash
kubectl get deployment nginx-deployment -n default -o yaml
kubectl get service nginx-service -n default -o yaml
```

This gives you the rollback baseline — if something goes wrong, you know exactly what to restore.

---

## 🔧 Step-by-Step Solution

### Method 1 — Targeted Imperative Commands (Fastest for Exam/Lab)

**Step 1 — Verify cluster access and document pre-change state**
```bash
kubectl get nodes
kubectl get deployment nginx-deployment -n default
kubectl get service nginx-service -n default
```

**Step 2 — Document current image and container name**
```bash
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].name}'
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```
Store the container name — you need it for `kubectl set image`.

**Step 3 — Change 1: Patch the Service nodePort 30008 → 32165**

Using JSON patch — most precise targeting of `spec.ports[0].nodePort`:
```bash
kubectl patch service nginx-service -n default \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":32165}]'
```

Verify immediately:
```bash
kubectl get service nginx-service -n default
kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.ports[0].nodePort}'
```
Expected: `32165`

**Step 4 — Change 2: Scale replicas 1 → 5**
```bash
kubectl scale deployment nginx-deployment \
  --replicas=5 \
  -n default
```

Verify:
```bash
kubectl get deployment nginx-deployment -n default
```
Expected: `READY 5/5` (may take a moment for new Pods to start).

**Step 5 — Change 3: Update image nginx:1.17 → nginx:latest**

Store container name first:
```bash
CONTAINER=$(kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].name}')
echo "Container name: ${CONTAINER}"

kubectl set image deployment/nginx-deployment \
  ${CONTAINER}=nginx:latest \
  -n default
```

**Step 6 — Wait for rolling update to complete**
```bash
kubectl rollout status deployment/nginx-deployment \
  -n default \
  --timeout=180s
```
Expected: `deployment "nginx-deployment" successfully rolled out`

---

### Method 2 — Declarative Export + Edit + Apply (GitOps Approach)

**Step 1 — Export both resources**
```bash
kubectl get deployment nginx-deployment -n default -o yaml > nginx-deployment.yaml
kubectl get service nginx-service -n default -o yaml > nginx-service.yaml
```

**Step 2 — Patch deployment file (replicas + image)**
```bash
# Update replicas
sed -i 's/replicas: 1/replicas: 5/' nginx-deployment.yaml

# Update image
sed -i 's|image: nginx:1.17|image: nginx:latest|' nginx-deployment.yaml

# Verify changes
grep -E 'replicas:|image:' nginx-deployment.yaml
```

**Step 3 — Patch service file (nodePort)**
```bash
sed -i 's/nodePort: 30008/nodePort: 32165/' nginx-service.yaml

# Verify change
grep 'nodePort' nginx-service.yaml
```

**Step 4 — Apply both**
```bash
kubectl apply -f nginx-deployment.yaml
kubectl apply -f nginx-service.yaml
```

**Step 5 — Monitor rollout**
```bash
kubectl rollout status deployment/nginx-deployment -n default --timeout=180s
```

---

## 💻 Commands Reference

```bash
# Pre-change documentation
kubectl get deployment nginx-deployment -n default
kubectl get service nginx-service -n default
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].name}'
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.ports[0].nodePort}'

# Change 1 — Service nodePort (JSON patch)
kubectl patch service nginx-service -n default \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":32165}]'

# Change 1 — Alternative (merge patch)
kubectl patch service nginx-service -n default \
  -p '{"spec":{"ports":[{"port":80,"nodePort":32165}]}}'

# Change 2 — Replicas
kubectl scale deployment nginx-deployment --replicas=5 -n default

# Change 3 — Image (store container name first)
CONTAINER=$(kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].name}')
kubectl set image deployment/nginx-deployment ${CONTAINER}=nginx:latest -n default

# Rolling update monitor
kubectl rollout status deployment/nginx-deployment -n default --timeout=180s

# Post-change verification
kubectl get deployment nginx-deployment -n default
kubectl get service nginx-service -n default
kubectl get pods -n default -l app=nginx

# Individual field verification
kubectl get service nginx-service -n default \
  -o jsonpath='{.spec.ports[0].nodePort}'
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.replicas}'
kubectl get deployment nginx-deployment -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Rollout history (confirms the image update created a new revision)
kubectl rollout history deployment/nginx-deployment -n default
```

---

## ⚠️ Common Mistakes

1. **Not knowing the container name before running `kubectl set image`**
   From Day 05 and Day 11: `kubectl set image` needs the container name, not the deployment name. If the container is named `nginx` and you pass `nginx-deployment=nginx:latest`, the command returns `error: unable to find container named "nginx-deployment"`. Always inspect with `kubectl get deployment -o jsonpath='{.spec.template.spec.containers[0].name}'` before patching.

2. **NodePort merge patch overwriting other port fields**
   The merge patch `{"spec":{"ports":[{"nodePort":32165}]}}` — without including `port` and `protocol` — can wipe the other port fields depending on the patch strategy. Use the JSON patch (`--type='json'`) with an explicit `replace` operation on `/spec/ports/0/nodePort` for the safest targeted update.

3. **Patching nodePort to an out-of-range value**
   NodePorts must be in the range 30000–32767 (cluster default). Values outside this range produce `The Service "nginx-service" is invalid: spec.ports[0].nodePort: Invalid value`. `32165` is valid. `3216` (missing a digit) is not.

4. **Changing image before confirming replicas — unexpected rolling update scope**
   If you update the image first while replicas=1, the rolling update cycles 1 Pod. If you scale to 5 first and then update the image, the rolling update cycles 5 Pods. For a production update, scale first so all replicas get the new image through the controlled rolling update. For a quick fix, image first is simpler.

5. **Not waiting for `rollout status` after `set image`**
   The image update triggers an asynchronous rolling update. `kubectl get deployment` may show `READY 5/5` immediately — but those 5 Pods may still be running the old image. `rollout status` blocks until all Pods are running the new image. Without it, your verification confirms old Pod count, not new image rollout.

6. **Using `kubectl edit` under lab time pressure**
   `kubectl edit` opens a full YAML document in vi/nano. Finding the right field and editing it correctly without YAML syntax errors takes more time than the targeted commands. Under a lab time limit, `kubectl patch` + `kubectl scale` + `kubectl set image` are always faster.

7. **Verifying only the Deployment, forgetting the Service**
   Three changes across two resources. After the Deployment rollout confirms, always independently verify the Service: `kubectl get service nginx-service -o jsonpath='{.spec.ports[0].nodePort}'`. A complete task confirmation requires all three changes verified separately.

---

## 🌍 Real-World Context

This task mirrors a real production change request: update a live service with zero downtime and no resource recreation. The three-change pattern is a standard release operation:

**Replica scale-up** happens before a high-traffic event — before Black Friday, a product launch, or a scheduled batch job peak. Teams pre-scale Deployments to handle the load, then scale back down afterward.

**Image update** is the core of every application release. The rolling update mechanism (Days 05/06) ensures no downtime during the transition. In GitOps workflows, the image tag change is committed to a Git repo, ArgoCD picks it up, and runs the same `kubectl set image` equivalent automatically.

**NodePort change** is less common in production (most production traffic goes through an Ingress or LoadBalancer, not NodePort), but it happens during port conflict resolution, security hardening, or migration to a new port assignment scheme. Because the Service is not deleted, existing connections in flight are not disrupted — kube-proxy updates happen at the node level within seconds.

The "without deleting" constraint in this task is not just an exam restriction — it is production operational discipline. Every team with SLAs should be able to modify running resources in-place rather than recreating them, which would cause a downtime window.

---

## ❓ Interview Q&A

**Q1: What is the difference between `kubectl patch`, `kubectl edit`, and `kubectl apply` for modifying a resource?**
`kubectl patch` applies a partial update — you provide only the fields you want to change, everything else is untouched. `kubectl edit` opens the full resource YAML in a text editor; you modify it and save, which sends a full strategic merge. `kubectl apply -f` takes a local file and reconciles it against the live resource — fields in the file override live fields, but fields not in the file are left alone for resources that were originally created with `apply`. For targeted changes, `patch` is the fastest and safest; for complex multi-field changes, `edit` or `apply` is more practical.

**Q2: What are the three patch types in `kubectl patch` and when do you use each?**
Strategic merge (`--type=strategic`, the default) is Kubernetes-aware and understands list semantics — it merges containers by name rather than replacing the entire array. Merge patch (`--type=merge`) is a standard JSON Merge Patch (RFC 7396) — it replaces arrays entirely rather than merging them, which can lose data if not careful. JSON patch (`--type=json`) uses RFC 6902 operations (`add`, `remove`, `replace`) and is the most precise — you specify the exact path and operation, making it ideal for targeted field updates like nodePort.

**Q3: Does changing a Service's nodePort cause any downtime?**
No. The Service object is updated immediately — the kube-proxy on each node detects the change via the watch API and updates its iptables/IPVS rules within seconds. In-flight connections on the old port may be momentarily disrupted (TCP connections in progress), but no Pod is restarted and no new Service is created. Clients must reconnect using the new port once it is advertised.

**Q4: How does `kubectl scale` differ from modifying `spec.replicas` in the manifest?**
Functionally they produce the same result — both update `spec.replicas` on the Deployment. `kubectl scale` is the direct imperative command; modifying the manifest and `kubectl apply`-ing is the declarative path. In GitOps workflows, the declarative path is preferred because the Git repo stays as the source of truth. In operational contexts (incident response, pre-event scaling), `kubectl scale` is faster. Be aware that `kubectl scale` on a resource managed by a GitOps controller may be overwritten on the next sync if the manifest in Git still shows `replicas: 1`.

**Q5: Why does `kubectl set image` trigger a rolling update but `kubectl scale` does not?**
Rolling updates are triggered by changes to the Pod template (`spec.template`). `kubectl set image` modifies `spec.template.spec.containers[].image` — a Pod template field — which causes the Deployment controller to create a new ReplicaSet with the updated template. `kubectl scale` only modifies `spec.replicas` — not a Pod template field — so the existing ReplicaSet simply creates more Pods using the same existing template. No new ReplicaSet is created, no old Pods are replaced.

**Q6: How would you safely roll out all three changes in a maintenance window?**
Scale first (so the replica count is at desired before the update), then update the image (the rolling update cycles all 5 replicas through the new image), then patch the Service (immediate, no Pod impact). Monitor each step with `kubectl rollout status` and `kubectl get pods -w` before proceeding to the next. If the image update fails, run `kubectl rollout undo` before changing the Service.

**Q7: What happens to the old ReplicaSet after the image update?**
The same behaviour as Day 05/06: the old ReplicaSet (`nginx-deployment-<old-hash>`) is scaled to 0 replicas and retained for rollback. `kubectl get replicasets` shows both — old with `DESIRED=0`, new with `DESIRED=5`. `kubectl rollout undo deployment/nginx-deployment` would restore the old image by scaling up the old RS. The number of old ReplicaSets kept is controlled by `revisionHistoryLimit` (default: 10).

---

## 📚 Resources

- [Kubernetes Docs — kubectl patch](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/update-api-object-kubectl-patch/)
- [Kubernetes Docs — kubectl scale](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#scale)
- [Kubernetes Docs — kubectl set image](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#set)
- [Kubernetes Docs — Service NodePort](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport)
- **Related days:** [Day 05](../day-05/README.md) — Rolling updates | [Day 06](../day-06/README.md) — Rollback after image updates | [Day 02](../day-02/README.md) — Deployment fundamentals
