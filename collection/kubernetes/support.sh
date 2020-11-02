#!/bin/sh

# The script dumps cluster info out suitable for debugging and diagnosing cluster problems.
# It dumps everything from all namespaces to a file

out_dir=
tmp_dir=
output_file=
log_time=$(date +%s)


cleanup() {
  exit_code=$?

  if [ $exit_code -eq "0" ]; then
    if [ -d "${tmp_dir}" ]; then
      rm -rf "${tmp_dir}"
    fi
    exit 0
  fi

  echo "Exiting without cleanup as script...collected logs at" $tmp_dir
}

trap cleanup EXIT
trap cleanup INT



checkKubeCtl() {
    test=$(kubectl version --short)
    if [ $? -eq 1 ]; then
        echo "Won't collect cluster-info dump as there is problem connecting kubelet to the kube-api server"
        exit 1
    fi
}



parseInputArgs() {
    while getopts "o:" OPTION; do
        case $OPTION in
        o)
            out_dir=$OPTARG
            ;;
        *)
            echo "Incorrect options provided"
            exit 1
            ;;
        esac
    done


    if [ -z "$out_dir" ]; then
        echo "One or more parameters are missing."
        echo "Usage: $(basename $0) -o output-directory "
        exit 1
    fi

    currentContext=$(kubectl config current-context)
    echo "Collecting Support Information from $currentContext"
    echo "Logs Path:" $out_dir

    tmp_dir=$out_dir/cluster-logs-${log_time}
    tmp_dir_k8s=$out_dir/cluster-logs-${log_time}
    output_file=$out_dir/$currentContext-support-collection-${log_time}.tar.gz
}


setupLogDirectory() {
    rm -rf $tmp_dir
    rm -rf $output_file
    echo "Temp directory where the logs are stored $tmp_dir"
    echo "Support collection Name: $output_file"
    mkdir -p ${tmp_dir}
    mkdir -p ${tmp_dir_k8s}
}

colletClusterLogs() {
    echo "Collecting cluster-info dump..."
    kubectl cluster-info dump --all-namespaces --output-directory=${tmp_dir_k8s}
}

colletNodeLogs() {
    echo "Collecting node logs..."
    kubectl apply -f support-DaemonSet.yaml
    kubectl get nodes -o wide > ${tmp_dir}/nodes.txt
    pods=$(kubectl get pods -l app=support-tool  --no-headers -o custom-columns=":metadata.name")
    echo "Waiting for Collector Pods to be ready"
    kubectl wait --for=condition=Ready pod -l app=support-tool
    echo "Creating Logs"
    sleep 60
    for pod in ${pods}
    do
        node=$(kubectl get pods -l app=support-tool --field-selector metadata.name==${pod} --no-headers -o custom-columns=":spec.nodeName")
        echo $pod
        echo $node
        echo ${pod}:tmp/${node}-info.tar.gz
        kubectl cp ${pod}:tmp/${node}-info.tar.gz ${tmp_dir}/${node}-info.tar.gz 
    done
    #kubectl delete -f support-DaemonSet.yaml
}

createDump() {
    echo "Create cluster dump..."
    tar -czf ${output_file} ${tmp_dir}
    echo
    echo
    echo "Support collection Name: $output_file"
    echo
    echo "!!!Please note: This file can contain sensitive data from various logs and Kubernetes manifests!!!"
    echo "Please upload the file $output_file to https://kubermatic.support"
}


checkKubeCtl
parseInputArgs "$@"
setupLogDirectory
colletClusterLogs
colletNodeLogs
createDump


