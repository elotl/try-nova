import sys
import yaml

CLUSTER_RESOURCES = set([
    'Namespace',
    'Node',
    'PersistentVolume',
    'CustomResourceDefinition',
    'ClusterRole',
    'ClusterRoleBinding',
    'StorageClass',
    'MutatingWebhookConfiguration',
    'ValidatingWebhookConfiguration',
    'PriorityClass',
    'PodSecurityPolicy',
    'APIService',
    'TokenReview',
    'CertificateSigningRequest',
    'VolumeAttachment'
])

def add_labels(documents, mode, label_key, label_value):
    for doc in documents:
        if doc is None or 'kind' not in doc:
            continue
        if 'metadata' not in doc:
            doc['metadata'] = {}
        if 'labels' not in doc['metadata']:
            doc['metadata']['labels'] = {}

        if mode == "cluster" and doc.get('kind') in CLUSTER_RESOURCES:
            doc['metadata']['labels'][label_key] = label_value
        elif mode == "namespace" and doc.get('kind') not in CLUSTER_RESOURCES:
            doc['metadata']['labels'][label_key] = label_value

    return documents

def main(mode, label_key, label_value):
    try:
        # Load all YAML documents from stdin
        documents = list(yaml.safe_load_all(sys.stdin))
        # Add the labels to the documents
        documents = add_labels(documents, mode, label_key, label_value)
        # Output the updated documents to stdout
        for doc in documents:
            if doc is not None:
                yaml.safe_dump(doc, sys.stdout, default_flow_style=False)
                print('---')
    except Exception as e:
        sys.stderr.write(f"Error: {e}\n")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.stderr.write("Usage: add_labels.py mode labelKey labelValue\n")
        sys.stderr.write("Mode should be either 'cluster' or 'namespace'\n")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
