# Get the resource types for both namespace and cluster-level
NS_TYPES=$(kubectl api-resources --verbs=list -o name --namespaced=true | grep "kubeflow")
CLUSTER_TYPES=$(kubectl api-resources --verbs=list -o name --namespaced=false | grep "kubeflow")

echo "Removing finalizers from namespaced Rancher resources"
for type in $NS_TYPES; do
    echo "Removing finalizers for $type"
    kubectl get $type --all-namespaces -o custom-columns='NAMESPACE:.metadata.namespace','NAME:.metadata.name' --no-headers | awk '{print $1 " " $2}' | xargs -L1 bash -c "kubectl patch -n $0 $type/$1 --type=merge -p $(kubectl get -n $0 $type/$1 -o json | jq -Mcr '.metadata.finalizers // [] | {metadata:{finalizers:map(select(. | (contains("controller.cattle.io/") or contains("wrangler.cattle.io/")) | not ))}}')"
done

echo "Removing finalizers from cluster Rancher resources"
for type in $CLUSTER_TYPES; do
    echo "Removing finalizers for $type"
    kubectl get $type -o name --show-kind --no-headers | awk '{print $1 }' | xargs -L1 bash -c "kubectl patch $0 --type=merge -p $(kubectl get $0 -o json | jq -Mcr '.metadata.finalizers // [] | {metadata:{finalizers:map(select(. | (contains("controller.cattle.io/") or contains("wrangler.cattle.io/")) | not ))}}')"
done
