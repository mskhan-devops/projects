# Deploying Nginx with HTTPS using cert-manager on Kind Cluster

A complete step-by-step guide to setting up Nginx with HTTPS on a local Kind cluster, including MetalLB for load balancing and cert-manager for TLS certificate management.

---

## Prerequisites

- Docker installed and running
- kubectl installed
- kind installed
- A running Kind cluster

### Verify Your Setup

```bash
# Check Kind cluster is running
kind get clusters

# Verify kubectl access
kubectl cluster-info

# Check all pods in all namespaces
kubectl get pods -A
```

---

## Step 1: Install MetalLB

Kind clusters don't have a built-in LoadBalancer. MetalLB provides this functionality.

### Install MetalLB Manifests

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
```

### Wait for MetalLB to be Ready

```bash
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s
```

### Create MetalLB Configuration

MetalLB needs an IP address pool to assign external IPs to LoadBalancer services.

```bash
cat > metallb-config.yaml << 'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.18.255.200-172.18.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: first-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
EOF
```

Apply the configuration:

```bash
kubectl apply -f metallb-config.yaml
```

### Verify MetalLB Installation

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspools -n metallb-system
```

---

## Step 2: Install cert-manager

cert-manager automates certificate management for Kubernetes.

### Install cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.1/cert-manager.yaml
```

### Wait for cert-manager to be Ready

```bash
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=120s
```

### Verify cert-manager

```bash
kubectl get pods -n cert-manager
```

---

## Step 3: Create a Certificate Issuer

For local development, we'll use a self-signed issuer. For production with real domains, you would use Let's Encrypt.

### Create Self-Signed Issuer

```bash
cat > issuer.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-issuer
  namespace: nginx-app
spec:
  selfSigned: {}
EOF
```

Apply it:

```bash
kubectl apply -f issuer.yaml
```

---

## Step 4: Deploy Nginx Application

### Create the Namespace

```bash
kubectl create namespace nginx-app
```

### Create Custom HTML Content

```bash
cat > nginx-index-html-configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-index-html
  namespace: nginx-app
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
        <title>Welcome to Nginx with HTTPS!</title>
    </head>
    <body>
        <h1>Hello! Your nginx is running with HTTPS via cert-manager!</h1>
    </body>
    </html>
EOF

kubectl apply -f nginx-index-html-configmap.yaml
```

### Create Nginx Configuration (HTTP to HTTPS Redirect)

```bash
cat > nginx-configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: nginx-app
data:
  nginx.conf: |
    worker_processes auto;
    error_log /var/log/nginx/error.log;
    pid /run/nginx.pid;
    
    events {
        worker_connections 1024;
    }
    
    http {
        log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                        '$status $body_bytes_sent "$http_referer" '
                        '"$http_user_agent" "$http_x_forwarded_for"';
    
        access_log /var/log/nginx/access.log main;
    
        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
        keepalive_timeout 65;
        types_hash_max_size 2048;
    
        include /etc/nginx/mime.types;
        default_type application/octet-stream;
    
        server {
            listen 80;
            server_name localhost;
            
            return 301 https://$server_name$request_uri;
        }
    
        server {
            listen 443 ssl http2;
            server_name localhost;
    
            ssl_certificate /etc/nginx/tls/tls.crt;
            ssl_certificate_key /etc/nginx/tls/tls.key;
    
            ssl_protocols TLSv1.2 TLSv1.3;
            ssl_ciphers HIGH:!aNULL:!MD5;
            ssl_prefer_server_ciphers on;
    
            location / {
                root /usr/share/nginx/html;
                index index.html;
            }
        }
    }
EOF

kubectl apply -f nginx-configmap.yaml
```

### Create the Certificate

```bash
cat > certificate.yaml << 'EOF'
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
EOF

kubectl apply -f certificate.yaml
```

### Verify Certificate Creation

```bash
kubectl get certificate -n nginx-app
kubectl get secret -n nginx-app
```

The certificate should show `READY: True` after a few seconds.

### Create Nginx Deployment with TLS

```bash
cat > nginx-deployment.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: nginx-app
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: nginx-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
          name: http
        - containerPort: 443
          name: https
        volumeMounts:
        - name: html-volume
          mountPath: /usr/share/nginx/html
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: tls-cert
          mountPath: /etc/nginx/tls
          readOnly: true
      volumes:
      - name: html-volume
        configMap:
          name: nginx-index-html
      - name: nginx-config
        configMap:
          name: nginx-config
      - name: tls-cert
        secret:
          secretName: nginx-tls
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: nginx-app
spec:
  selector:
    app: nginx
  ports:
  - name: http
    port: 80
    targetPort: 80
  - name: https
    port: 443
    targetPort: 443
  type: NodePort
EOF

kubectl apply -f nginx-deployment.yaml
```

### Wait for Deployment

```bash
kubectl get pods -n nginx-app
kubectl get svc -n nginx-app
```

---

## Step 5: Test the Setup

### Method 1: Port Forward (Recommended for Testing)

```bash
# Start port forward in background
kubectl port-forward -n nginx-app svc/nginx-service 8443:443 &

# Test HTTPS
curl -k https://localhost:8443

# Verify certificate details
echo | openssl s_client -connect localhost:8443 2>/dev/null | openssl x509 -noout -text | grep -A 5 Issuer

# Stop port forward when done
pkill -f "port-forward"
```

### Method 2: Via NodePort

```bash
# Get node IP
kubectl get nodes -o wide

# Access via HTTPS (replace <node-ip> with actual IP)
curl -k https://<node-ip>:31178

# HTTP should redirect to HTTPS
curl -L http://<node-ip>:30645
```

---

## Problems Encountered and Fixes

### Problem 1: Ingress Controller Image Pull Timeout

**Issue**: When installing the NGINX Ingress Controller, the container images failed to pull, causing pods to stay in `ContainerCreating` state indefinitely.

**Attempted Solution**: 
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml
```

**Result**: Pods stuck in `ContainerCreating` with events showing image pulls timing out.

**Fix Applied**: 
1. Abandoned the Ingress Controller approach for this setup
2. Used **NodePort** service type instead, which works without LoadBalancer
3. This is actually simpler for local development

### Problem 2: Namespace Deletion Stuck in Terminating State

**Issue**: After deleting the Ingress Controller, the `ingress-nginx` namespace got stuck in `Terminating` state.

**Symptoms**:
```bash
kubectl get namespace ingress-nginx
# Output: NAME            STATUS        AGE
#         ingress-nginx   Terminating   3m43s
```

**Fix Applied**:
```bash
# Force delete stuck pods
kubectl delete pod <stuck-pod-name> -n ingress-nginx --force --grace-period=0

# If namespace still stuck, force finalize
kubectl get namespace ingress-nginx -o json | python3 -c "import sys,json; d=json.load(sys.stdin); d['spec']['finalizers']=[]; print(json.dumps(d))" | kubectl replace --raw "/api/v1/namespaces/ingress-nginx/finalize" -f -
```

### Problem 3: Nginx Image Pull Failures

**Issue**: The `nginx:latest` image was timing out during pull, causing deployment rollouts to fail.

**Fix Applied**:
1. Pulled a smaller image explicitly:
   ```bash
   docker pull nginx:alpine
   ```

2. Updated deployment to use `nginx:alpine`:
   ```yaml
   spec:
     containers:
     - name: nginx
       image: nginx:alpine
       imagePullPolicy: IfNotPresent
   ```

### Problem 4: Multiple ReplicaSets Stuck

**Issue**: After image pull failures, old replicaSets remained in terminating state.

**Fix Applied**:
```bash
# Force delete stuck pods
kubectl delete pod <pod-name> -n nginx-app --force --grace-period=0

# This triggers the deployment to create new pods with the correct image
```

### Problem 5: Image Loading into Kind Cluster Failed

**Issue**: Attempted to load Docker image into Kind cluster but failed:
```
ERROR: failed to load image: command "docker exec --privileged -i test-cluster-control-plane ctr ..." failed
```

**Fix Applied**:
Used `imagePullPolicy: IfNotPresent` and let the Kind node pull the image directly. The alpine image is small enough to pull successfully.

---

## Complete File Summary

All files created in this tutorial:

| File | Purpose |
|------|---------|
| `metallb-config.yaml` | MetalLB IP address pool configuration |
| `issuer.yaml` | Self-signed cert-manager Issuer |
| `certificate.yaml` | TLS Certificate definition |
| `nginx-index-html-configmap.yaml` | Custom HTML content |
| `nginx-configmap.yaml` | Nginx server configuration |
| `nginx-deployment.yaml` | Nginx deployment, service, and all resources |

---

## Verification Commands

```bash
# Check all resources
kubectl get all -n nginx-app
kubectl get all -n metallb-system
kubectl get all -n cert-manager

# Verify certificate
kubectl describe certificate nginx-cert -n nginx-app

# Check secret
kubectl describe secret nginx-tls -n nginx-app

# View pod logs
kubectl logs -n nginx-app -l app=nginx

# View cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/instance=cert-manager
```

---

## Cleanup

To remove all resources:

```bash
# Delete nginx-app namespace
kubectl delete namespace nginx-app

# Delete MetalLB
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

# Delete cert-manager
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.1/cert-manager.yaml
```

---

## Next Steps for Production

1. **Use Let's Encrypt Issuer** - Replace self-signed with:
   ```yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: letsencrypt-prod
   spec:
     acme:
       server: https://acme-v02.api.letsencrypt.org/directory
       email: your-email@example.com
       privateKeySecretRef:
         name: letsencrypt-prod
       solvers:
       - http01:
           ingress:
             class: nginx
   ```

2. **Install Ingress Controller** - Once network is working:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml
   ```

3. **Use Ingress for routing** - Instead of NodePort, use Ingress resources with cert-manager annotation:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: nginx-ingress
     annotations:
       cert-manager.io/issuer: letsencrypt-prod
   spec:
     tls:
     - hosts:
       - yourdomain.com
       secretName: nginx-tls
     rules:
     - host: yourdomain.com
       http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: nginx-service
               port:
                 number: 80
   ```

---

## Summary

This tutorial demonstrated:
- Installing MetalLB for LoadBalancer support in Kind
- Setting up cert-manager for automated TLS certificates
- Creating a self-signed certificate for local development
- Configuring Nginx to use TLS with automatic HTTP→HTTPS redirect
- Testing HTTPS access via port-forward and NodePort

The main challenges were image pull timeouts in the Kind environment, which were resolved by using smaller images (alpine) and the NodePort service type instead of Ingress Controller.
