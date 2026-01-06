# Kind Cluster with HTTPS Registry Setup

## Part 1: Prerequisites

1.  **Install Tools**:
    ```bash
    brew install kind mkcert docker
    
    # For Firefox support (optional)
    brew install nss
    ```

2.  **Setup Root CA**:
    Initialize `mkcert` (requires sudo equivalent password prompt usually):
    ```bash
    JAVA_HOME="" sudo mkcert -install
    ```
    Verify CA installation:
    ```bash
    ls "$(mkcert -CAROOT)"
    ```

## Part 2: Certificates & DNS

1.  **Define Registry Name**:
    Decide on a domain name for your registry.
    ```bash
    export REGISTRY_NAME=kind-registry.local
    ```

2.  **Generate Certificates**:
    Generate the certificates for the chosen domain.
    ```bash
    JAVA_HOME="" mkcert $REGISTRY_NAME
    ```

    Isolate the CA certificate (required for the cluster to trust the registry):
    ```bash
    cp "$(mkcert -CAROOT)/rootCA.pem" ./ca.pem
    ```
    *Ensure you are in the root of this repo so the script can find `ca.pem` and the generated certs (e.g., `kind-registry.local.pem`, `kind-registry.local-key.pem`).*

3.  **Configure DNS**:
    Add the registry domain to your local hosts file.
    ```bash
    # Requires sudo
    sudo sh -c "echo '127.0.0.1 $REGISTRY_NAME' >> /etc/hosts"
    ```

## Part 3: Cluster Spin-up

Once the prerequisites are installed and certificates are generated, use the script to manage the cluster.

```bash
# Start the cluster and registry
./scripts/cluster.sh up

# Check status
./scripts/cluster.sh status

# Verify connectivity
./scripts/cluster.sh verify

# Tear down
./scripts/cluster.sh down
```

### Script Usage
The script expects the certificate files to be present in the current directory:
- `$REGISTRY_NAME.pem`
- `$REGISTRY_NAME-key.pem`
- `ca.pem`
