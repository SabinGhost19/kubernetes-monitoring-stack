# Deploying and Configuring ArgoCD on Kubernetes – Step-by-Step Guide

## Overview

This document provides a detailed, step-by-step guide for installing **ArgoCD** on a Kubernetes cluster using **Helm**. It also covers configuration, authentication, adding repositories, performing port forwarding, and addressing common issues.

ArgoCD is a declarative, GitOps continuous delivery tool for Kubernetes. It allows you to manage application deployments via Git repositories, ensuring that the desired state defined in Git matches the live cluster.

---

## Prerequisites

Before starting, ensure you have the following installed and configured:

* **kubectl** (configured to access your Kubernetes cluster)
* **Helm** (version 3 or later)
* **Git**
* **An active Kubernetes cluster** (e.g., Minikube, Kind, K3s, or a cloud-based cluster such as EKS, GKE, or AKS)

Check connectivity and tools:

```bash
kubectl cluster-info
kubectl get nodes
helm version
kubectl version --client
```

---

## Step 1: Create the Namespace for ArgoCD

By convention, ArgoCD is deployed into its own namespace named `argocd`.

```bash
kubectl create namespace argocd
```

Verify the namespace:

```bash
kubectl get ns
```

---

## Step 2: Add the Argo Helm Repository

Add the official Argo Helm repository and update your local Helm cache.

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

You can confirm that the repository is added:

```bash
helm search repo argo
```

---

## Step 3: Install ArgoCD Using Helm

Install ArgoCD into the `argocd` namespace.

```bash
helm install argocd argo/argo-cd -n argocd
```

You can optionally customize your installation using a `values.yaml` file.

For example:

```bash
helm install argocd argo/argo-cd -n argocd -f values.yaml
```

Check if the pods are running:

```bash
kubectl get pods -n argocd
```

You should see output similar to:

```
NAME                                  READY   STATUS    RESTARTS   AGE
argocd-server-xxxxxxx-xxxxx           1/1     Running   0          2m
argocd-repo-server-xxxxxxx-xxxxx      1/1     Running   0          2m
argocd-application-controller-xxxxx   1/1     Running   0          2m
argocd-dex-server-xxxxxxx-xxxxx       1/1     Running   0          2m
```

---

## Step 4: Access the ArgoCD API Server

The ArgoCD API server is not exposed by default. To access the web UI, you can use **port forwarding**:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Now you can access the UI in your browser at:

```
https://localhost:8080
```

Note that the connection is HTTPS, and you may need to bypass a browser security warning because it uses a self-signed certificate.

---

## Step 5: Retrieve the Admin Password

The default username is **admin**.
The password is stored in a Kubernetes secret named `argocd-initial-admin-secret`.

Get the password using:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
```

Use this password to log into the web UI.

---

## Step 6: Login to ArgoCD CLI (Optional but Recommended)

Install the ArgoCD CLI tool.
For Linux or macOS:

```bash
brew install argocd
```

or from binary:

```bash
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/
```

Login to the ArgoCD server using CLI:

```bash
argocd login localhost:8080 --username admin --password <your-password> --insecure
```

You should see a message confirming a successful login.

---

## Step 7: Add a Git Repository to ArgoCD

ArgoCD can sync and deploy applications directly from a Git repository.

To add a Git repository:

```bash
argocd repo add git@github.com:YOUR_USERNAME/YOUR_REPOSITORY.git \
  --ssh-private-key-path ~/.ssh/id_rsa
```

Or if the repository is public and uses HTTPS:

```bash
argocd repo add https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git
```

To list all repositories added to ArgoCD:

```bash
argocd repo list
```

---

## Step 8: Create an Application

You can create an application either from the ArgoCD UI or via CLI.

Example command:

```bash
argocd app create my-app \
  --repo https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git \
  --path apps/prometheus-stack-app \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace monitoring \
  --sync-policy automated
```

Or you can define it declaratively in a YAML file (`prometheus-app.yaml`) and store it in Git:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-stack
  namespace: argocd
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  source:
    repoURL: "https://prometheus-community.github.io/helm-charts"
    chart: kube-prometheus-stack
    targetRevision: 45.0.0
    helm:
      valueFiles:
        - apps/prometheus-stack-app/values.yaml
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Apply it:

```bash
kubectl apply -f apps/prometheus-stack-app/prometheus-app.yaml
```

---

## Step 9: App of Apps Pattern (Optional but Recommended)

You can manage multiple applications using a single “root” ArgoCD Application.

**Example:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: apps-bootstrap-root
  namespace: argocd
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  source:
    repoURL: "git@github.com:YOUR_USERNAME/YOUR_REPOSITORY.git"
    targetRevision: main
    path: apps
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Apply it to the cluster:

```bash
kubectl apply -f apps/apps-bootstrap-root.yaml
```

This root application will automatically create all child applications defined under the `apps/` directory.

---

## Step 10: Verifying the Installation

Check application synchronization status:

```bash
argocd app list
```

Sync all apps manually (if automation is disabled):

```bash
argocd app sync my-app
```

Check logs if something fails:

```bash
kubectl logs -n argocd deploy/argocd-application-controller
kubectl describe app my-app -n argocd
```

---

## Common Errors and Solutions

### 1. Certificate Issues When Accessing the UI

If your browser shows a certificate warning on `https://localhost:8080`, this is normal for self-signed certificates. Simply proceed with “Advanced” → “Accept Risk”.

### 2. “Permission Denied” on SSH Repository

Ensure that the SSH key used by ArgoCD is added to your Git provider. You can generate and configure it:

```bash
ssh-keygen -t ed25519 -C "argocd@yourdomain.com"
kubectl create secret generic argocd-ssh-secret \
  --from-file=sshPrivateKey=~/.ssh/id_ed25519 -n argocd
```

### 3. Application Sync Errors

Check for:

* Incorrect path (`path:` field in Application YAML)
* Invalid branch (`targetRevision`)
* Missing namespace permissions

### 4. ArgoCD Pods CrashLoopBackOff

Check logs for the specific pod:

```bash
kubectl logs -n argocd pod/<pod-name>
```

Ensure your cluster has sufficient memory and CPU resources.

---

## Step 11: Cleanup (Optional)

To completely remove ArgoCD:

```bash
helm uninstall argocd -n argocd
kubectl delete namespace argocd
```