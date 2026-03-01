# Kubernetes Cluster Setup – Detailed Documentation

> **Table of Contents**  
> 1. [Prerequisites](#prerequisites)  
> 2. [Certificate & Secret (`certificate.yaml`)](#certificate-and-secret)  
> 3. [Self‑Signed ClusterIssuer (`cluster‑issuer.yaml`)](#self‑signed-clusterissuer)  
> 4. [Ingress‑Nginx (`ingress‑nginx.yaml`)](#ingress‑nginx)  
> 5. [MetalLB Load‑Balancer (`metallb‑config.yaml`)](#metallb-load‑balancer)  
> 6. [Nginx Application (`nginx‑deployment.yaml`)](#nginx-application)  
> 7. [Deployment Workflow](#deployment-workflow)  
> 8. [Observability & Troubleshooting](#observability-and-troubleshooting)  

> All manifests use **YAML** – copy the code blocks as‑is or adjust namespaces, image tags, or provider settings for your environment.

---

## 1. Prerequisites

| Component | Minimum Version | Install Method |
|-----------|----------------|----------------|
| **Kubernetes** | 1.19+ | kubeadm, GKE, EKS, AKS, etc. |
| **cert‑manager** | v1.13+ | Helm or `kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.13.0/cert-manager.yaml` |
| **MetalLB** | v0.14+ | Helm or `kubectl apply -f https://github.com/metallb/metallb/releases/download/v0.14.6/metalLB.yaml` |
| **Ingress-Nginx-Controller** | version 0.14.8) | `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.14.3/deploy/static/provider/cloud/deploy.yaml`|
| **Helm** | 3.9+ (optional) | to manage all manifests as a chart |

**Namespace Note** – This setup creates two namespaces:

- `ingress-nginx` – holds Ingress‑Nginx controller.
- `nginx-app` – hosts the demo Nginx app and its TLS secret.

---

## 2. Certificate & Secret (`certificate.yaml`)

Creates a *namespaced* `Issuer` and `Certificate`. These resources are processed by **cert‑manager** to generate a TLS secret (`nginx-tls`) containing `tls.crt` & `tls.key`.

```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-issuer
  namespace: nginx-app
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nginx-cert
  namespace: nginx-app
spec:
  secretName: nginx-tls
  issuerRef:
    name: selfsigned-issuer
    kind: Issuer
  commonName: localhost
  dnsNames:
  - localhost
  - nginx-service
  - nginx-service.nginx-app
  - nginx-service.nginx-app.svc
  ipAddresses:
  - 127.0.0.1
```

### What It Does

| Resource | Purpose | Key Fields |
|----------|---------|------------|
| `Issuer` (`selfsigned-issuer`) | Generates self‑signed certificates **local to this namespace**. | `spec.selfSigned: {}` |
| `Certificate` (`nginx-cert`) | Requests a certificate, signed by the issuer, and stores it as a secret. | `secretName: nginx-tls`<br>`issuerRef` <br>`commonName`, `dnsNames`, `ipAddresses` |

- **Scope** – Namespaced, so it cannot be referenced from other namespaces.
- **TLS Secret** – `nginx-tls` is mounted by the Nginx Deployment to serve HTTPS.
- **Browser Trust** – Self‑signed; browsers will warn unless you import the cert. For production, replace with a CA‑issued issuer.

### Deployment Tips

```bash
# Apply after cert‑manager is running
kubectl apply -f certificate.yaml
```

Verify the secret creation:

```bash
kubectl -n nginx-app describe secret nginx-tls
```

---

## 3. Self‑Signed ClusterIssuer (`cluster-issuer.yaml`)

Provides a **cluster‑wide** `ClusterIssuer` with the same name. cert‑manager uses this if a `Certificate` references a `ClusterIssuer` instead of a namespaced one.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
```

### Why It Exists

| Use‑Case | When to Use |
|----------|-------------|
| **Cluster‑Scoped Issuer** | If you want a single issuer that many namespaces can share. |
| **Simplified Management** | No per‑namespace configuration needed. |

> **Tip** – If you only need namespaced IUs, omit this file. If you plan to generate certificates for multiple apps, create the `ClusterIssuer` once.

---

## 4. Ingress‑Nginx (`ingress-nginx.yaml`)

Deploys the Ingress‑Nginx controller together with RBAC, TLS configuration, and a dedicated `ConfigMap`. The controller is exposed via MetalLB (see section 5).

```yaml
# Namespace
apiVersion: v1
kind: Namespace
metadata:
  name: ingress-nginx
---
# ServiceAccount – used by the controller
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
---
# RBAC – ClusterRole for listing/reading resources
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/managed-by: Helm
rules:
- apiGroups: [""]
  resources:
  - events
  verbs:
  - create
  - patch
- apiGroups: ["extensions","networking.k8s.io"]
  resources:
  - ingresses
  - ingresses/status
  verbs:
  - get
  - list
  - watch
  - update
- apiGroups: ["networking.k8s.io"]
  resources:
  - ingressclasses
  verbs:
  - get
  - list
  - watch
- apiGroups: ["policy"]
  resources:
  - podsecuritypolicies
  verbs:
  - use
---
# RoleBinding – bind role to ServiceAccount
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
subjects:
- kind: ServiceAccount
  name: ingress-nginx
  namespace: ingress-nginx
roleRef:
  kind: ClusterRole
  name: ingress-nginx
  apiGroup: rbac.authorization.k8s.io
---
# ConfigMap – minimal Nginx config shipped with upstream image
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  enable-webhook: "false"
---
# Deployment – runs the controller container
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
      app.kubernetes.io/instance: ingress-nginx
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ingress-nginx
        app.kubernetes.io/instance: ingress-nginx
    spec:
      containers:
      - args:
        - /nginx-ingress-controller
        - --config-map=$(POD_NAMESPACE)/ingress-nginx-controller
        - --watch-namespace=$(POD_NAMESPACE)
        - --default-ssl-certificate=$(POD_NAMESPACE)/ingress-nginx-controller
        - --publish-service=$(POD_NAMESPACE)/ingress-nginx-controller
        - --election-id=ingress-nginx-leader
        - --ingress-class=nginx
        - --enable-ssl-passthrough=true
        - --enable-debug-logs=true
        - --enable-multiple-ingress-groups
        - --enable-real-ip
        command:
        - /opt/bitnami/scripts/nginx-ingress-controller/entrypoint.sh
        env:
        - name: NGINX_LOG_FORMAT_JSON
          value: "false"
        image: docker.io/k8s.gcr.io/ingress-nginx/controller:v1.9.4@sha256:b9f6d8a7f9e5a2b3c8c7e7f6a4e1a2b0c0d1e2f3a4b5c6
        name: ingress-nginx
        resources:
          limits:
            cpu: 500m
            memory: 1Gi
          requests:
            cpu: 250m
            memory: 64Mi
        securityContext:
          runAsUser: 65534
          runAsNonRoot: true
      initContainers:
      - command:
        - /opt/bitnami/scripts/init-servicemonitors.sh
        image: docker.io/bitnami/nginx:1.25.5
        name: init-servicemonitors
        resources:
          limits:
            cpu: 10m
            memory: 5Mi
          requests:
            cpu: 5m
            memory: 5Mi
      serviceAccountName: ingress-nginx
---
# Service – exposes the controller to MetalLB
apiVersion: v1
kind: Service
metadata:
  annotations:
    metallb.universe.tf/address-pool: first-pool
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  ports:
  - port: 80
    name: http
  - port: 443
    name: https
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ingress-nginx
  type: LoadBalancer
```

### Core Concepts

- **RBAC** – `ClusterRole` & `RoleBinding` give the controller permissions to discover Ingress objects.
- **ServiceAccount** – `ingress-nginx` runs the controller pod.
- **ConfigMap** – Allows you to tweak Nginx settings if you upgrade the controller.
- **LoadBalancer** – MetalLB will provide an external IP (see section 5).

---

## 3. Self‑Signed ClusterIssuer (`cluster-issuer.yaml`)

Provides a **cluster‑wide** self‑signed issuer. Useful when you want *any* namespace to reference this issuer without creating a namespaced one.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
```

> **Caveat** – The `certificate.yaml` also creates an issuer with the same name but in `nginx-app`. The two are independent; the cluster‑issuer can be referenced by a `Certificate` configured to use it (`kind: ClusterIssuer`). This file might be redundant if only the namespaced issuer is desired.

---

## 4. Ingress‑Nginx (`ingress‑nginx.yaml`)

Deploys the **NGINX Ingress‑Controller** with full RBAC and a minimal configuration.

```yaml
# ① Namespace
apiVersion: v1
kind: Namespace
metadata:
  name: ingress-nginx
---
# ② ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
---
# ③ ClusterRole – governs what the controller can see
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/managed-by: Helm
rules:
- apiGroups: [""]
  resources:
    - events
  verbs:
    - create
    - patch
- apiGroups: ["extensions","networking.k8s.io"]
  resources:
    - ingresses
    - ingresses/status
  verbs:
    - get
    - list
    - watch
    - update
- apiGroups: ["networking.k8s.io"]
  resources:
    - ingressclasses
  verbs:
    - get
    - list
    - watch
- apiGroups: ["policy"]
  resources:
    - podsecuritypolicies
  verbs:
    - use
---
# ④ RoleBinding – grants ClusterRole to ServiceAccount
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
subjects:
- kind: ServiceAccount
  name: ingress-nginx
  namespace: ingress-nginx
roleRef:
  kind: ClusterRole
  name: ingress-nginx
  apiGroup: rbac.authorization.k8s.io
---
# ⑤ ConfigMap – minimal Nginx configuration for the controller
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  enable-webhook: "false"
---
# ⑥ Deployment – runs the controller pod
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
      app.kubernetes.io/instance: ingress-nginx
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ingress-nginx
        app.kubernetes.io/instance: ingress-nginx
    spec:
      containers:
      - args:
        - /nginx-ingress-controller
        - --config-map=$(POD_NAMESPACE)/ingress-nginx-controller
        - --watch-namespace=$(POD_NAMESPACE)
        - --default-ssl-certificate=$(POD_NAMESPACE)/ingress-nginx-controller
        - --publish-service=$(POD_NAMESPACE)/ingress-nginx-controller
        - --election-id=ingress-nginx-leader
        - --ingress-class=nginx
        - --enable-ssl-passthrough=true
        - --enable-debug-logs=true
        - --enable-multiple-ingress-groups
        - --enable-real-ip
        - --enable-multiple-ingress-groups
        - --enable-real-ip
        - --election-id=ingress-nginx-leader
        - --configmap=$(POD_NAMESPACE)/ingress-nginx-controller
        - --watch-namespace=$(POD_NAMESPACE)
        - --default-ssl-certificate=$(POD_NAMESPACE)/ingress-nginx-controller
        - --publish-service=$(POD_NAMESPACE)/ingress-nginx-controller
        - --election-id=ingress-nginx-leader
        - --enable-ssl-passthrough
        - --enable-debug-logs
        - --enable-multiple-ingress-groups
        - --enable-real-ip
        command:
        - /opt/bitnami/scripts/nginx-ingress-controller/entrypoint.sh
        env:
        - name: NGINX_LOG_FORMAT_JSON
          value: "false"
        image: docker.io/k8s.gcr.io/ingress-nginx/controller:v1.9.4@sha256:b9f... # truncated
      initContainers: ...
      serviceAccountName: ingress-nginx
---
# ⑥ Service – exposes controller with LoadBalancer
apiVersion: v1
kind: Service
metadata:
  annotations:
    metallb.universe.tf/address-pool: first-pool
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  ports:
  - port: 80
    name: http
  - port: 443
    name: https
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ingress-nginx
  type: LoadBalancer
```

### Why All Those Steps?

| Step | Purpose |
|------|----------|
| **Namespace** | Group all controller resources together. |
| **ServiceAccount** | Runs as `ingress‑nginx`. |
| **ClusterRole/RBAC** | Gives the controller permission to discover, log, and update Ingress resources. |
| **ConfigMap** | Customizes controller runtime (e.g., enabling real‑IP). |
| **Service** | Exposes Nginx externally via MetalLB. |

---

## 5. MetalLB Configuration (Section 5)

MetalLB sits in the control plane and watches for `Service` objects annotated with `metallb.universe.tf/address-pool`. In the controller’s service you saw:
```yaml
annotations:
  metallb.universe.tf/address-pool: first-pool
```
This tells MetalLB to allocate an IP from the pool named **first‑pool**. Your pool definition (`pool.yaml`) presumably already exists.

> **Example MetalLB pool**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: first-pool
      protocol: layer2
      addresses:
      - 192.168.1.200-192.168.1.210
```

### Verifying the External IP

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller -o wide
```

You should see an `EXTERNAL-IP` allocated from the MetalLB pool. Use it to reach any Ingress exposed by the controller.

---

## 6. Putting It All Together – A Simple Workflow

1. **Deploy cert‑manager** (via Helm, kubeadm, or manual manifests).
2. **Deploy MetalLB** (with a pool that covers your cluster’s external IP range).
3. **Deploy the Ingress‑Nginx controller** (sections 4 & 5).  
   ```bash
   kubectl apply -f ingress-nginx.yaml
   ```
4. **Create the demo app** (sections 1 & 2).  
   ```bash
   kubectl apply -f certificate.yaml
   kubectl apply -f deployment.yaml   # your app's pod/service
   ```
5. **Create an Ingress resource** (not included here) pointing to your app’s Service and referencing the `ClusterIssuer` or `ClusterRole`.  
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: demo-app
     namespace: nginx-app
     annotations:
       kubernetes.io/ingress.class: nginx
   spec:
     rules:
     - host: demo.example.com
       http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: demo
               port:
                 name: http
     tls:
     - hosts:
       - demo.example.com
       secretName: nginx-app/ingress-nginx-controller   # referenced cert
   ```

6. **Access the app** via the external IP MetalLB provided for the controller.

---

## 7. Common Pitfalls & Troubleshooting

| Symptom | Likely Cause | Fix |
|--------|--------------|-----|
| Controller pod stuck in `imagePullBackOff` | Wrong image digest or tags | Use imagePullPolicy: Always; verify image repo. |
| No external IP assigned | MetalLB not correctly configured or address pool missing | Validate pool config; check MetalLB pods status. |
| Ingress not routing | Missing IngressClass or cluster‑wide `ClusterRole` | Ensure Ingress has `ingressClassName: nginx`. |
| Secret not found for TLS | certificate not yet created or wrong namespace | Verify namespace, secret name, and annotation. |

---

## 8. Next Steps

- **Add TLS to your application** – create a Ingress resource using the `ClusterIssuer` or the namespaced `Issuer`.  
- **Monitor** – Enable metrics and scrape with Prometheus (config in the Service annotations).  
- **Upgrade** – Keep the controller updated; use Helm for easier management.

---

## Appendix – Quick Verify Commands

```bash
# 1. cert‑manager pods
kubectl -n kube-system get pods -l app=cert-manager

# 2. External IP for Ingress
kubectl -n ingress-nginx get svc ingress-nginx-controller
# 3. Test Ingress (curl)
curl -v http://<EXTERNAL_IP>/demo-app
```

Feel free to modify the configuration values per your cluster topology and security requirements. Happy hacking!