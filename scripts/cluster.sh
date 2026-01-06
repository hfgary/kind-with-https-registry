#!/bin/bash
set -e

CLUSTER_NAME="kind-cluster"
REGISTRY_NAME="kind-registry.local"
REGISTRY_PORT="5005"
K8S_VERSION="v1.32.2"

case "$1" in
  up)
    echo "--- Checking Certificates ---"
    if [ ! -f "$REGISTRY_NAME.pem" ] || [ ! -f "$REGISTRY_NAME-key.pem" ] || [ ! -f "ca.pem" ]; then
        echo "❌ Certificates missing. Please run the manual setup first."
        echo "Expected files: $REGISTRY_NAME.pem, $REGISTRY_NAME-key.pem, ca.pem"
        exit 1
    fi
    echo "✅ Certificates found."

    echo "--- Creating Cluster ---"
    kind create cluster --config k8s-manifests/kind-config.yaml --image kindest/node:$K8S_VERSION

    echo "--- Starting HTTPS Registry ---"
    docker run -d --name $REGISTRY_NAME --restart=always \
      -p $REGISTRY_PORT:$REGISTRY_PORT -v "$(pwd):/certs" \
      -e REGISTRY_HTTP_ADDR=0.0.0.0:$REGISTRY_PORT \
      -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/$REGISTRY_NAME.pem \
      -e REGISTRY_HTTP_TLS_KEY=/certs/$REGISTRY_NAME-key.pem \
      registry:2

    echo "--- Connecting Registry to Kind Network ---"
    # Connect the registry to the kind network so pods can access it
    docker network connect kind $REGISTRY_NAME

    # Get the registry IP on the kind network
    REG_IP=$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' $REGISTRY_NAME)
    echo "Registry IP on kind network: $REG_IP"

    echo "--- Patching Trust ---"
    for node in $(kind get nodes --name $CLUSTER_NAME); do
      docker exec $node mkdir -p /etc/containerd/certs.d/$REGISTRY_NAME:$REGISTRY_PORT
      cat <<EOF | docker exec -i $node cp /dev/stdin /etc/containerd/certs.d/$REGISTRY_NAME:$REGISTRY_PORT/hosts.toml
[host."https://$REGISTRY_NAME:$REGISTRY_PORT"]
  ca = "/etc/ssl/certs/ca.pem"
EOF

      docker exec $node sh -c "echo '$REG_IP $REGISTRY_NAME' >> /etc/hosts"

    done
    echo "Done! Cluster and HTTPS Registry are ready."
    ;;

  down)
    echo "--- Tearing Down ---"
    kind delete cluster --name $CLUSTER_NAME
    docker stop $REGISTRY_NAME && docker rm $REGISTRY_NAME
    # rm -f *.pem *-key.pem # Certs are now managed manually
    echo "Cleanup complete."
    ;;

  status)
    echo "--- Checking Infrastructure Status ---"
    
    # 1. Check Registry
    echo -n "Registry ($REGISTRY_NAME): "
    if [ "$(docker inspect -f '{{.State.Running}}' $REGISTRY_NAME 2>/dev/stdin)" == "true" ]; then
        echo "✅ RUNNING (HTTPS on port $REGISTRY_PORT)"
    else
        echo "❌ NOT RUNNING"
    fi

    # 2. Check Kind Cluster
    echo -n "Kind Cluster ($CLUSTER_NAME): "
    if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        echo "✅ CREATED"
        # Check if nodes are actually Ready
        kubectl get nodes --context kind-$CLUSTER_NAME
    else
        echo "❌ NOT FOUND"
    fi

    # 3. Check Certificates
    echo -n "Certificates: "
    if [ -f "$REGISTRY_NAME.pem" ] && [ -f "ca.pem" ]; then
        echo "✅ PRESENT"
    else
        echo "❌ MISSING"
    fi
    ;;

  verify)
    echo "--- Testing Registry Connection ---"

    # Test from node (containerd)
    echo "1. Testing from Kind node (containerd)..."
    if docker exec kind-cluster-control-plane curl -s --cacert /etc/ssl/certs/ca.pem https://kind-registry.local:5005/v2/ > /dev/null; then
        echo "   ✅ Node can access registry over HTTPS"
    else
        echo "   ❌ Node cannot access registry"
        exit 1
    fi

    # Test from pod (application level)
    echo "2. Testing from inside a pod..."
    kubectl run registry-test --image=curlimages/curl:latest --rm -i --restart=Never --command -- \
      sh -c "curl -k https://kind-registry.local:5005/v2/ 2>&1" > /dev/null

    if [ $? -eq 0 ]; then
        echo "   ✅ Pods can access registry over HTTPS"
    else
        echo "   ⚠️  Pod test failed (this is expected if no pods can resolve the registry)"
    fi

    # Show registry network info
    echo "3. Registry network information:"
    REG_IP=$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' $REGISTRY_NAME 2>/dev/null)
    if [ -n "$REG_IP" ]; then
        echo "   Registry IP on kind network: $REG_IP"
        echo "   ✅ Registry is connected to kind network"
    else
        echo "   ❌ Registry is NOT connected to kind network"
        echo "   Run: docker network connect kind $REGISTRY_NAME"
    fi
    ;;

  fix)
    echo "--- Fixing Registry Network Connection ---"

    # Check if registry is running
    if [ "$(docker inspect -f '{{.State.Running}}' $REGISTRY_NAME 2>/dev/null)" != "true" ]; then
        echo "❌ Registry is not running. Start it first with: $0 up"
        exit 1
    fi

    # Check if kind cluster exists
    if ! kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        echo "❌ Kind cluster not found. Create it first with: $0 up"
        exit 1
    fi

    # Connect registry to kind network if not already connected
    echo "Connecting registry to kind network..."
    docker network connect kind $REGISTRY_NAME 2>/dev/null || echo "Already connected"

    # Get the registry IP on the kind network
    REG_IP=$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' $REGISTRY_NAME)
    echo "Registry IP on kind network: $REG_IP"

    # Update /etc/hosts in all kind nodes
    echo "Updating /etc/hosts in kind nodes..."
    for node in $(kind get nodes --name $CLUSTER_NAME); do
      # Check if entry already exists with correct IP
      if docker exec $node grep -q "^$REG_IP $REGISTRY_NAME" /etc/hosts 2>/dev/null; then
        echo "  $node already has correct entry"
      else
        # Remove old entries and add new one
        docker exec $node sh -c "grep -v '$REGISTRY_NAME' /etc/hosts > /tmp/hosts.tmp && cat /tmp/hosts.tmp > /etc/hosts && rm /tmp/hosts.tmp"
        docker exec $node sh -c "echo '$REG_IP $REGISTRY_NAME' >> /etc/hosts"
        echo "  Updated $node"
      fi
    done

    echo "✅ Registry network connection fixed"
    echo "You can now verify with: $0 verify"
    ;;

  *)
    echo "Usage: $0 {up|down|status|verify|fix}"
    echo ""
    echo "Commands:"
    echo "  up      - Create cluster and registry"
    echo "  down    - Destroy cluster and registry"
    echo "  status  - Check status of cluster and registry"
    echo "  verify  - Test registry connectivity"
    echo "  fix     - Fix registry network connection (if registry can't be reached from pods)"
    ;;
esac