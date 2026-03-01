
You should have Kubernetes running with and `kubectl` installed.

cert‑manager:
````bash\
# Install cert-manager
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Install metalLB
kubectl apply -f https://github.com/metallb/metallb/releases/download/v0.14.6/metalLB.yaml`

# Install ingress-nginx
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.14.3/deploy/static/provider/cloud/deploy.yaml

-- Respective namespaces should have been created:
kubectl get ns

# Install nginx as sample web app:
kubectl apply -f nginx-deployment-withSvc.yaml

# Install ingress resource to access the nginx via load balancer:


```
