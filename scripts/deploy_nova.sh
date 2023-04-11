#!/usr/bin/env bash

source ./common.sh

NOVA_CONTROL_PLANE_CONTEXT=${1}
NOVA_AGENT_CONTEXTS=${2}

function select_control_plane_cluster {
    local return_value=$1
    IFS=';' read -r -a contexts <<< "${@:2}"

    echo "Please select control plane cluster context. Press Space to select, press Enter to confirm."
    IFS=';'; singleselect result "$(join_by ";" ${contexts[@]})"
    tput cuu1
    for ctx in "${contexts[@]}"; do
        tput el
        tput cuu1
    done
    tput el
    tput cuu1
    tput el
    local idx=0

    local selected_contexts=()
    for ctx in "${contexts[@]}"; do
        if [ "${result[idx]}" == "true" ]; then
            selected_contexts+=("$ctx")
        fi
        ((idx++))
    done

    eval $return_value='("${selected_contexts[@]}")'
}

function select_agent_clusters {
    local return_value=$1
    IFS=';' read -r -a contexts <<< "${@:2}"

    echo "Please select agent cluster contexts (one or more). Press Space to select, press Enter to confirm."
    IFS=';'; multiselect result "$(join_by ";" ${contexts[@]})"
    tput cuu1
    for ctx in "${contexts[@]}"; do
        tput el
        tput cuu1
    done
    tput el
    tput cuu1
    tput el
    local idx=0

    local selected_contexts=()
    for ctx in "${contexts[@]}"; do
        if [ "${result[idx]}" == "true" ]; then
            selected_contexts+=("$ctx")
        fi
        ((idx++))
    done

    eval $return_value='("${selected_contexts[@]}")'
}


function install_control_plane {
    IMAGE_TAG=${SCHEDULER_IMAGE_TAG}
    IMAGE_REPO=${SCHEDULER_IMAGE_REPO}

    export NOVA_KUBE_CONTEXT=${1:-""}
    OUTPUT_DIR="${2:-"$HOME/.elotl"}"
    export NAMESPACE=${4:-"elotl"}
    export IMAGE_TAG=${5:-"$IMAGE_TAG"}
    export IMAGE_REPO=${6:-"$IMAGE_REPO"}
    export EXTRA_IP=${NOVA_NODE_IP:-"127.0.0.1"}
    PARENT_DIR="$(dirname "$(which "$0")")"

    if [ -z "$NOVA_KUBE_CONTEXT" ]
    then
        cat <<EOF > /dev/stderr
Usage:
    $0 <cluster-context> ...
EOF
    exit 1
    fi

    _cert_path="$OUTPUT_DIR/opt/certs"

    if kubectl get --context="${control_plane_context}" deploy nova-scheduler -n elotl 2>/dev/null; then
        echo
        echo "Upgrading Nova Control Plane"
        echo "OUTPUT DIR -> ${OUTPUT_DIR}"
        echo
    else
        echo
        echo "Installing Nova Control Plane"
        echo

        mkdir -p "$OUTPUT_DIR/manifests"
        mkdir -p "$_cert_path"
        mkdir -p "$_cert_path/etcd"

        install_cfssl
        install_cfssljson
        install_envsubst

        echo "Nova Control Plane will be deployed to kube-context:${NOVA_KUBE_CONTEXT}"
        kubectl --context="${NOVA_KUBE_CONTEXT}" cluster-info

        # get a public endpoint for apiserver first, so that we can generate the right apiserver cert
        "$_envsubst" < "templates/apiserver-service.yaml" | kubectl --context="${NOVA_KUBE_CONTEXT}" apply -f -

        APISERVER_ENDPOINT=''

        get_eks () {
        echo $(kubectl --context="${NOVA_KUBE_CONTEXT}" get service apiserver -n "${NAMESPACE}" --template="{{range .status.loadBalancer.ingress}}{{.hostname}} {{end}}" | xargs)
        }

        get_gke () {
        echo $(kubectl --context="${NOVA_KUBE_CONTEXT}" get service apiserver -n "${NAMESPACE}" --template="{{range .status.loadBalancer.ingress}}{{.ip}} {{end}}" | xargs)
        }

        get_apiserver_endpoint () {
        api_server_endpoint=''
        api_server_endpoint=$(get_eks)
        if [[ ! -z "$api_server_endpoint" && "$api_server_endpoint" != "<no value>" ]]; then
            echo "$api_server_endpoint"
            return
        fi

        api_server_endpoint=$(get_gke)
        if [[ ! -z "$api_server_endpoint" && "$api_server_endpoint" != "<no value>" ]]; then
            echo "$api_server_endpoint"
            return
        fi
        }


        wait_apiserver_service() {
            for tmp in {1..30}; do
            external_host="$(get_apiserver_endpoint)"

            if [[ -z "$external_host" ]]; then
                echo "Waiting for the external host of Nova ApiServer to be ready..."
                sleep 6
                continue
            else
                APISERVER_ENDPOINT="${external_host}"
                return 0
            fi
            done
            return 1
        }

        wait_apiserver_service
        echo "--- APISERVER_ENDPOINT=$APISERVER_ENDPOINT"

        if [[ "$OSTYPE" == 'darwin'* && "$NOVA_KUBE_CONTEXT" == 'kind-'* ]]; then
            echo "--- On macos with KIND cluster, setting APISERVER_PUBLIC_ENDPOINT to 0.0.0.0 for docker network mapping"
            export APISERVER_PUBLIC_ENDPOINT="0.0.0.0"
        else
            export APISERVER_PUBLIC_ENDPOINT="$APISERVER_ENDPOINT"
        fi


        init_ca() {
            local key_out=$1
            local cert_out=$2
            local cn=$3
            openssl req -x509 -sha256 -new -nodes -days 365 -newkey rsa:2048 -keyout "$key_out" -out "$cert_out" -subj "/C=xx/ST=x/L=x/O=x/OU=x/CN=$cn/emailAddress=x/"
        }

        # we follow https://kubernetes.io/docs/setup/best-practices/certificates/#single-root-ca to generate ca crt/key pair for kubernetes general ca, etcd, and front-end proxy
        echo "--- generating k8s wide ca"
        init_ca "$_cert_path/ca.key" "$_cert_path/ca.crt" "kubernetes-ca"
        echo "--- generating etcd ca"
        init_ca "$_cert_path/etcd/ca.key" "$_cert_path/etcd/ca.crt" "etcd-ca"
        echo "--- generating front proxy ca"
        init_ca "$_cert_path/front-proxy-ca.key" "$_cert_path/front-proxy-ca.crt" "kubernetes-front-proxy-ca"

        gen_cert() {
            local csr_config=$1
            local ca_key=$2
            local ca=$3
            local profile=$4
            local output=$5
            # Uncomment for debugging
            # envsubst < "$csr_config"
            $_envsubst < "$csr_config" | "$_cfssl" gencert -ca-key="$ca_key" -ca="$ca" -config=certs-config/ca-config.json -profile="$profile" - | "$_cfssljson" -bare "$output"
            rm "$output.csr"
            mv "$output.pem" "$output.crt"
            mv "$output-key.pem" "$output.key"
        }

        # we follow https://kubernetes.io/docs/setup/best-practices/certificates/#all-certificates to generate certificates
        echo "Generating front proxy client crt/key pair, signed by front proxy ca"
        gen_cert "certs-config/front-proxy-client-csr.json" "$_cert_path/front-proxy-ca.key" "$_cert_path/front-proxy-ca.crt" "client" "$_cert_path/front-proxy-client"

        echo "Generating etcd server crt/key pair, signed by etcd ca"
        gen_cert "certs-config/kube-etcd-csr.json" "$_cert_path/etcd/ca.key" "$_cert_path/etcd/ca.crt" "peer" "$_cert_path/etcd/server"

        echo "Generating etcd client crt/key pair, signed by etcd ca"
        gen_cert "certs-config/kube-apiserver-etcd-client-csr.json" "$_cert_path/etcd/ca.key" "$_cert_path/etcd/ca.crt" "client" "$_cert_path/apiserver-etcd-client"

        echo "Generating apiserver crt/key pair, signed by ca"
        gen_cert "certs-config/kube-apiserver-csr.json" "$_cert_path/ca.key" "$_cert_path/ca.crt" "server" "$_cert_path/apiserver"

        echo "Generating apiserver client crt/key pair with cluster-admin permissions, signed by ca"
        gen_cert "certs-config/kube-apiserver-client-csr.json" "$_cert_path/ca.key" "$_cert_path/ca.crt" "client" "$_cert_path/apiserver-client"

        echo "Generating service account key pair"
        openssl genrsa -out "$_cert_path/sa.key" 2048
        openssl rsa -in "$_cert_path/sa.key" -pubout -out "$_cert_path/sa.pub"

        # generating agent secret
        $_envsubst < templates/agent/secret.yaml > "$OUTPUT_DIR/manifests/nova-agent-secret.yaml"
    fi

    ETCD_CA_CERT=$(base64 < "$_cert_path/etcd/ca.crt" | tr -d '\r\n')
    export ETCD_CA_CERT
    ETCD_SERVER_CERT=$(base64 < "$_cert_path/etcd/server.crt" | tr -d '\r\n')
    export ETCD_SERVER_CERT
    ETCD_SERVER_KEY=$(base64 < "$_cert_path/etcd/server.key" | tr -d '\r\n')
    export ETCD_SERVER_KEY

    FRONT_PROXY_CA_CERT=$(base64 < "$_cert_path/front-proxy-ca.crt" | tr -d '\r\n')
    export FRONT_PROXY_CA_CERT
    FRONT_PROXY_CLIENT_CERT=$(base64 < "$_cert_path/front-proxy-client.crt" | tr -d '\r\n')
    export FRONT_PROXY_CLIENT_CERT
    FRONT_PROXY_CLIENT_KEY=$(base64 < "$_cert_path/front-proxy-client.key" | tr -d '\r\n')
    export FRONT_PROXY_CLIENT_KEY

    CA_CERT=$(base64 < "$_cert_path/ca.crt"  | tr -d '\r\n')
    export CA_CERT
    APISERVER_CERT=$(base64 < "$_cert_path/apiserver.crt"  | tr -d '\r\n')
    export APISERVER_CERT
    APISERVER_KEY=$(base64 < "$_cert_path/apiserver.key"  | tr -d '\r\n')
    export APISERVER_KEY
    APISERVER_ETCD_CLIENT_CERT=$(base64 < "$_cert_path/apiserver-etcd-client.crt"  | tr -d '\r\n')
    export APISERVER_ETCD_CLIENT_CERT
    APISERVER_ETCD_CLIENT_KEY=$(base64 < "$_cert_path/apiserver-etcd-client.key"  | tr -d '\r\n')
    export APISERVER_ETCD_CLIENT_KEY
    APISERVER_CLIENT_CERT=$(base64 < "$_cert_path/apiserver-client.crt" | tr -d '\r\n')
    export APISERVER_CLIENT_CERT
    APISERVER_CLIENT_KEY=$(base64 < "$_cert_path/apiserver-client.key" | tr -d '\r\n')
    export APISERVER_CLIENT_KEY

    SA_KEY=$(base64 < "$_cert_path/sa.key" | tr -d '\r\n')
    export SA_KEY
    SA_PUB=$(base64 < "$_cert_path/sa.pub" | tr -d '\r\n')
    export SA_PUB

    # generate kubeconfig
    $_envsubst < templates/nova-kubeconfig > "$OUTPUT_DIR/nova-kubeconfig"

    # generating agent secret
    $_envsubst < templates/agent/secret.yaml > "$OUTPUT_DIR/manifests/nova-agent-secret.yaml"

    for yaml_template in templates/*.yaml; do
    $_envsubst < "$yaml_template" > "$OUTPUT_DIR/manifests/$(basename "$yaml_template")"
    done

    pushd "${OUTPUT_DIR}/manifests"
    kubectl --context="${NOVA_KUBE_CONTEXT}" apply -f etcd-cert.yaml -f etcd.yaml -f nova-cert.yaml -f apiserver.yaml -f kubeconfig-secret.yaml -f controller-manager.yaml
    popd

    # wait for deployment
    echo "Waiting for Nova to be up and running, will timeout in 5m"
    kubectl --context="${NOVA_KUBE_CONTEXT}" rollout status deploy/kube-controller-manager -n "${NAMESPACE}" --watch=true --timeout=5m

    kubectl get --context="${control_plane_context}" deploy nova-scheduler -n elotl >/dev/null # Check if nova is already running
    if [ $? -eq 0 ]; then
        echo "API SERVER should already be available"

    else
        # wait until Nova Control Plane API Server responds with 403.
        # If endpoint is ready, it returns 403 for unauthenticated request.
        GET_COUNTER=0
        while [ "$RETURN_CODE" != 403 ] && [ $GET_COUNTER -lt 100 ]; do
            RETURN_CODE=$(curl -I --http1.1 --insecure https://$APISERVER_PUBLIC_ENDPOINT 2>&1 | grep 'HTTP/1.1' | awk '{ print $2}')
            echo "Waiting for Nova Control Plane's API Server's public endpoint to be available... On AWS, this will take a while..." && sleep 3
            GET_COUNTER=$(($GET_COUNTER +1))
        done
    fi

    # apply crd
    echo "----------------------------------------------------------"
    echo "Nova Control Plane:"
    KUBECONFIG="$OUTPUT_DIR/nova-kubeconfig" kubectl cluster-info --request-timeout='3m'
    echo "----------------------------------------------------------"

    echo "Applying CRDs to Nova Control Plane..."
    KUBECONFIG="$OUTPUT_DIR/nova-kubeconfig" kubectl apply -f crds/cluster.elotl.co_clusters.yaml
    KUBECONFIG="$OUTPUT_DIR/nova-kubeconfig" kubectl apply -f crds/policy.elotl.co_schedulepolicies.yaml
    KUBECONFIG="$OUTPUT_DIR/nova-kubeconfig" kubectl apply -f crds/policy.elotl.co_schedulegroups.yaml
    echo ""

    # apply scheduler
    pushd "${OUTPUT_DIR}/manifests"
    if [ ! -z "$NOVA_IDLE_ENTER_STANDBY_ENABLE" ]
    then
      echo "Nova feature to place idle workload clusters in standby enabled"
      echo "Set env vars AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY for AWS workload clusters standby"
      echo "Set env vars GCE_PROJECT_ID and GCE_ACCESS_KEY for GCE workload clusters standby"
      echo "Set env var NOVA_IDLE_ENTER_STANDBY_SECS if desired to override default idle period before standby"
      echo "Set env var NOVA_DELETE_CLUSTER_IN_STANDBY to delete standby cluster rather than scale down its nodes"
      echo "Set env var NOVA_CREATE_CLUSTER_IF_NEEDED to create new cluster to handle policy (requires NOVA_DELETE_CLUSTER_IN_STANDBY)"
      echo "Set env var NOVA_MAX_CREATED_CLUSTERS if desired to override default maximum nova-created clusters"
    fi
    kubectl --context="${NOVA_KUBE_CONTEXT}" apply -f scheduler.yaml
    popd

    echo "Nova installer script's output dir: ${OUTPUT_DIR}"
    echo ""

    # generating agent secret
    $_envsubst < templates/agent/secret.yaml > "$OUTPUT_DIR/manifests/nova-agent-secret.yaml"

    # store nova-kubeconfig in Nova Control Plane, for use in setting up Nova Agents.
    KUBECONFIG="$OUTPUT_DIR/nova-kubeconfig" kubectl apply -f "${OUTPUT_DIR}/manifests/nova-agent-secret.yaml"

    echo "Nova is deployed in kube-context:$NOVA_KUBE_CONTEXT under namespace:$NAMESPACE "
    echo ""
    echo "To see Nova resources deployed to the hosting cluster, please run:"
    echo "kubectl --context $NOVA_KUBE_CONTEXT get all -n $NAMESPACE"
    echo ""
    echo "To see Nova logs, please run:"
    echo "kubectl --context $NOVA_KUBE_CONTEXT logs -n $NAMESPACE -l component=nova-scheduler"
    echo ""
    echo "To interact with Nova Control Plane, please run:"
    echo "KUBECONFIG=\"$OUTPUT_DIR/nova-kubeconfig\" kubectl get all"
    echo ""
    echo "To deploy Nova agent to a workload cluster, please run:"
    echo "./deploy_nova.sh \"\" <workload-cluster-kube-context> "
    echo "where <cluster-name> is a unique cluster identifier in Nova Control Plane"
}

function install_agent {
    IMAGE_TAG=${AGENT_IMAGE_TAG}
    IMAGE_REPO=${AGENT_IMAGE_REPO}
    NOVA_KUBECONFIG_FILE=${NOVA_KUBECONFIG_FILE:-"./nova-installer-output/nova-kubeconfig"}
    NOVA_EXIT_IF_CLUSTER_EXISTS=${NOVA_EXIT_IF_CLUSTER_EXISTS:-"true"}

    export NOVA_AGENT_CONTEXT=${1:-""}
    export AGENT_CLUSTER_NAME=${2:-""}
    export OUTPUT_DIR=${3:-"/tmp"} # Note: install_agent function does not depend on input from this directory
    export NAMESPACE=${4:-"elotl"}
    export IMAGE_TAG=${6:-"$IMAGE_TAG"}
    export IMAGE_REPO=${7:-"$IMAGE_REPO"}

    PARENT_DIR="$(dirname "$(which "$0")")"

    print_usage() {
    echo "--- Please set nova agent kube context, cluster name "
    echo "--- Example: ./deploy_nova.sh \"\" workload-cluster-context cluster-1"
    }

    source $PARENT_DIR/common.sh

    CLUSTER_WITH_NAME_EXISTS=$(KUBECONFIG=${NOVA_KUBECONFIG_FILE} kubectl get cluster "${AGENT_CLUSTER_NAME}" -o jsonpath='{.spec.name}' 2>/dev/null || true)
    if [ "${AGENT_CLUSTER_NAME}" == "${CLUSTER_WITH_NAME_EXISTS}" ]
    then
      if [ "${NOVA_EXIT_IF_CLUSTER_EXISTS}" == "true" ]
      then
        echo "Cluster with name ${AGENT_CLUSTER_NAME} already exists in Nova, please choose another name."
        exit 1
      fi
    fi

    AGENT_REPLICAS=$(kubectl --context "${NOVA_AGENT_CONTEXT}" get -n ${NAMESPACE} deployment/nova-agent -o jsonpath='{.status.replicas}' 2>/dev/null || echo 0)
    if [ "${AGENT_REPLICAS}" -gt 0 ]
    then
      echo "Nova agent is already installed in the cluster ${NOVA_AGENT_CONTEXT} with different cluster name than ${AGENT_CLUSTER_NAME} or connected to another Nova control plane."
      exit 1
    fi

    install_envsubst

    # Override is used for local kind cluster runs to pick up modified networking config needed for agents to reach nova control plane
    if [ ! -z "${OVERRIDE_NOVA_AGENT_SECRET}" ]
    then
      # store modified nova-kubeconfig in Nova Control Plane, for use in setting up Nova Agents.
      KUBECONFIG="$NOVA_KUBECONFIG_FILE" kubectl apply -f "${OVERRIDE_NOVA_AGENT_SECRET}"
    fi

    echo "Creating kube config secret in ${NOVA_AGENT_CONTEXT} cluster..."
    NOVA_AGENT_SECRET=$(KUBECONFIG=${NOVA_KUBECONFIG_FILE} kubectl get secret nova-kubeconfig -n ${NAMESPACE} -o jsonpath='{.data.kubeconfig}' 2>/dev/null | base64 -d)
    if [ -z "${NOVA_AGENT_SECRET}" ]
    then
      echo "Cannot fetch kube config from nova control plane"
      exit 1
    fi
    kubectl --context "${NOVA_AGENT_CONTEXT}" create namespace ${NAMESPACE}
    kubectl --context "${NOVA_AGENT_CONTEXT}" -n ${NAMESPACE} create secret generic nova-kubeconfig --from-literal=kubeconfig="${NOVA_AGENT_SECRET}"

    # Install log-reader objects
    cat <<EOF | kubectl -n "$NAMESPACE" apply --context "${NOVA_AGENT_CONTEXT}" -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: log-reader
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list"]
EOF

    cat <<EOF | kubectl -n "$NAMESPACE" apply --context "${NOVA_AGENT_CONTEXT}" -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: log-reader
  namespace: ${NAMESPACE}
EOF

    cat <<EOF | kubectl -n "$NAMESPACE" apply --context "${NOVA_AGENT_CONTEXT}" -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: log-reader
subjects:
  - kind: ServiceAccount
    name: log-reader
    namespace: ${NAMESPACE}
roleRef:
  kind: ClusterRole
  name: log-reader
  apiGroup: rbac.authorization.k8s.io
EOF

    cat <<EOF | kubectl -n "$NAMESPACE" apply --context "${NOVA_AGENT_CONTEXT}" -f -
apiVersion: v1
kind: Secret
metadata:
  name: log-reader-secret
  namespace: ${NAMESPACE}
  labels:
    nova.elotl.co/service-account.name: log-reader
  annotations:
    kubernetes.io/service-account.name: log-reader
type: kubernetes.io/service-account-token
EOF

    # Creating log service account not needed if reinstalling agent on existing cluster
    if [ "${AGENT_CLUSTER_NAME}" != "${CLUSTER_WITH_NAME_EXISTS}" ]
    then
      AGENT_CA_CERT=$(kubectl --context "$NOVA_AGENT_CONTEXT" config view --flatten --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
      export AGENT_CA_CERT
      AGENT_SERVER_DNS=$(kubectl --context "$NOVA_AGENT_CONTEXT" config view --flatten --raw -o jsonpath='{.clusters[0].cluster.server}')
      export AGENT_SERVER_DNS
      AGENT_SECRET_TOKEN=$(kubectl --context "$NOVA_AGENT_CONTEXT" get secret -n ${NAMESPACE} log-reader-secret -o jsonpath='{.data.token}' | base64 -d)
      export AGENT_SECRET_TOKEN

      echo "Creating service account for accessing logs"
      CLIENT_KUBECONFIG=$("$_envsubst" < templates/agent-logs-kubeconfig | base64)
      kubectl \
        --namespace "$NAMESPACE" \
        --kubeconfig "${NOVA_KUBECONFIG_FILE}" \
        create configmap "${AGENT_CLUSTER_NAME}" \
        --from-literal=config="${CLIENT_KUBECONFIG}"
    fi

    echo "Generating agent manifest for ${AGENT_CLUSTER_NAME} cluster..."
    mkdir -p "$OUTPUT_DIR/manifests"
    "$_envsubst" < templates/agent/agent.yaml > "${OUTPUT_DIR}/manifests/nova-agent-${AGENT_CLUSTER_NAME}.yaml"

    echo "Installing nova agent in ${NOVA_AGENT_CONTEXT} ..."
    kubectl --context "${NOVA_AGENT_CONTEXT}" apply -f "${OUTPUT_DIR}"/manifests/nova-agent-"${AGENT_CLUSTER_NAME}".yaml

    echo "-----------------------------------------------------------"
    echo "Agent created in ${NOVA_AGENT_CONTEXT} cluster."
    echo "To view agent logs, please run:"
    echo "kubectl --context ${NOVA_AGENT_CONTEXT} -n ${NAMESPACE} logs deploy/nova-agent -f"
    echo "-----------------------------------------------------------"
}

function install_noninteractive {
    install_control_plane=false
    install_agents=false

    if [  -n "${NOVA_CONTROL_PLANE_CONTEXT}" ]; then
        install_control_plane=true
    fi

    if [ -n "${NOVA_AGENT_CONTEXTS}" ]; then
        install_agents=true
    fi

    if [ "$install_control_plane" = true ] ; then
        echo
        echo "Installing Nova Control Plane"
        echo
        install_control_plane ${NOVA_CONTROL_PLANE_CONTEXT} "./nova-installer-output"
    fi

    if [ "$install_agents" = true ] ; then
        echo
        echo "Installing Nova Agents"
        echo
        IFS=',' read -r -a agent_clusters <<< "${NOVA_AGENT_CONTEXTS}"
        for ctx in "${agent_clusters[@]}"; do
            echo "Handling context ${ctx}"
            default_cluster_name=$(echo ${ctx} | sed -r 's/[:/_@.]+/-/g')
            install_agent "${ctx}" "${default_cluster_name}" "./nova-installer-output"
        done
    fi
}

install_noninteractive
