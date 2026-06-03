#!/bin/bash

# Utility functions for result collection

collect_applications() {
    local oc_opts=$1
    local file_json=$2
    local file_csv=$3
    local jq_cmd=".items[] | [.metadata.creationTimestamp, .metadata.name, .status.conditions[] | select(.type==\"Ready\").status] | @csv"

    oc get applications.appstudio.redhat.com "$oc_opts" -o json >"$file_json"
    jq -rc "$jq_cmd" < "$file_json" | sed -e 's,Z,,g' >>"$file_csv"
}

collect_components() {
    local oc_opts=$1
    local file_json=$2
    local file_csv=$3
    local jq_cmd=".items[] | [.metadata.creationTimestamp, .metadata.name, .status.conditions[] | select(.type==\"Ready\").status] | @csv"

    oc get components.appstudio.redhat.com "$oc_opts" -o json >"$file_json"
    jq -rc "$jq_cmd" < "$file_json" | sed -e 's,Z,,g' >>"$file_csv"
}

collect_pipelineruns() {
    local oc_opts=$1
    local file_json=$2
    local file_csv=$3
    local jq_cmd=".items[] | [.metadata.creationTimestamp, .metadata.name, .status.startTime, .status.completionTime, .status.conditions[] | select(.type==\"Succeeded\").status] | @csv"

    oc get pipelineruns.tekton.dev "$oc_opts" -o json >"$file_json"
    jq "$jq_cmd" < "$file_json" | sed -e "s/\n//g" -e "s/^\"//g" -e "s/\"$//g" -e "s/Z;/;/g" | sort -t ";" -k 13 -r -n >>"$file_csv"
}

collect_taskruns() {
    local oc_opts=$1
    local file_json=$2

    oc get taskruns.tekton.dev "$oc_opts" -o json >"$file_json"
}

collect_pods() {
    local oc_opts=$1
    local file_json=$2
    local pods_on_nodes_csv=$3
    local all_pods_distribution_csv=$4
    local task_pods_distribution_csv=$5

    oc get pod "$oc_opts" -o json >"$file_json"

    jq -r ".items[] | [.spec.nodeName, .metadata.namespace, .metadata.name] | @tsv" < "$file_json" | sort -V >>"$pods_on_nodes_csv"
    jq -r ".items[] | .spec.nodeName" < "$file_json" | sort | uniq -c | sed -e 's,\s\+\([0-9]\+\)\s\+\(.*\),\2;\1,g' >>"$all_pods_distribution_csv"
    jq -r '.items[] | select(.metadata.labels."appstudio.openshift.io/application" != null).spec.nodeName' < "$file_json" | sort | uniq -c | sed -e 's,\s\+\([0-9]\+\)\s\+\(.*\),\2;\1,g' >>"$task_pods_distribution_csv"

    oc get pod "$oc_opts" -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers=true | while IFS=$'\n' read -r row; do
        ns=${row%% *}
        name=${row##* }
        echo "Found pod $name in $ns"
    done
}

collect_events() {
    local oc_opts=$1
    local file_json=$2
    local file_csv=$3
    local jq_cmd=".items[] | [.lastTimestamp, .metadata.namespace, .involvedObject.kind, .involvedObject.name, .reason, .message] | @csv"

    oc get events "$oc_opts" -o json >"$file_json"
    jq -r "$jq_cmd" < "$file_json" >>"$file_csv"
}
