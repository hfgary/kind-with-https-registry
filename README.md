# Kind Cluster with HTTPS Registry Setup

## Part 1: Prerequisites

1.  **Install Tools**:
    ```bash
    brew install kind mkcert docker kubectl make
    
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

## Part 2: DNS Configuration

1.  **Configure DNS**:
    Add the registry domain to your local hosts file.
    > [!IMPORTANT]
    > The registry name must be `kind-registry.local`.
    ```bash
    export REGISTRY_NAME=kind-registry.local
    # Requires sudo
    sudo sh -c "echo '127.0.0.1 $REGISTRY_NAME' >> /etc/hosts"
    ```

## Part 3: Cluster Spin-up
 
 Once the prerequisites are installing and certificates are generated, you can use `make` or the script directly to manage the cluster.
 
 ### Using Makefile (Recommended)
 
 ```bash
 # Start the cluster and registry
 make up
 
 # Check status
 make status
 
 # Verify connectivity
 make verify
 
 # Tear down
 make down
 ```
 
 ### Using Script Directly
 
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
The script automatically generates the necessary certificates if they are missing.
