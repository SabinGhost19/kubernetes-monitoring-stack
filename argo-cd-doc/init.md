# Adding a GitHub Repository to ArgoCD Using SSH

## Prerequisites

* **ArgoCD CLI installed** on the local machine.
* **Admin credentials** for the ArgoCD server.
* **SSH key** configured in GitHub and accessible locally.

Example credentials for demonstration purposes:

* ArgoCD username: `admin`
* ArgoCD password: `b0yHV43ugBjIzBcy`
* ArgoCD server URL: `https://localhost:8080`
* SSH private key path: `~/.ssh/githubUbuntuKey`

---

## Common Error

When attempting to add a GitHub repository:

```bash
argocd repo add git@github.com:SabinGhost19/kubernetes-logging-stack.git --ssh-private-key-path ~/.ssh/githubUbuntuKey
```

Users may encounter the following error:

```
rpc error: code = Unauthenticated desc = invalid session: token signature is invalid: signature is invalid
```

**Cause:**
This error indicates that the ArgoCD CLI session is not authenticated. It is **not related to the GitHub SSH key**.

---

## Step 1: Verify SSH Key

Before integrating the repository, ensure that the SSH key works with GitHub:

```bash
ssh -i ~/.ssh/githubUbuntuKey -T git@github.com
```

Expected output:

```
Hi <username>! You've successfully authenticated, but GitHub does not provide shell access.
```

If authentication fails, check the permissions on the private key:

```bash
chmod 600 ~/.ssh/githubUbuntuKey
```

---

## Step 2: Authenticate with ArgoCD

To resolve the `invalid session` error, log in to the ArgoCD server using the CLI:

```bash
argocd login localhost:8080 --username admin --password b0yHV43ugBjIzBcy --insecure
```

**Notes:**

* Do not include `https://` in the server address. Use only `localhost:8080`.
* The `--insecure` flag is required if the server uses a self-signed certificate.

Verify that the login was successful:

```bash
argocd account get-user
```

---

## Step 3: Add the GitHub Repository

Once authenticated, add the repository using the SSH key:

```bash
argocd repo add git@github.com:SabinGhost19/kubernetes-logging-stack.git --ssh-private-key-path ~/.ssh/key
```
