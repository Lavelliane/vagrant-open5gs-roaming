#!/bin/bash

# Script to deploy MongoDB first, add subscribers, then deploy other components
# Exit on error
set -e

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default subscriber values
NAMESPACE="open5gs"
IMSI="001011234567891"
KEY="7F176C500D47CF2090CB6D91F4A73479"
OPC="3D45770E83C7BBB6900F3653FDA6330F"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --imsi)
      IMSI="$2"
      shift 2
      ;;
    --key)
      KEY="$2"
      shift 2
      ;;
    --opc)
      OPC="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 [--namespace namespace] [--imsi IMSI] [--key KEY] [--opc OPC]"
      exit 1
      ;;
  esac
done

# Create namespace if it doesn't exist
echo -e "${BLUE}Creating namespace $NAMESPACE if it doesn't exist...${NC}"
microk8s kubectl create namespace $NAMESPACE --dry-run=client -o yaml | microk8s kubectl apply -f -
echo -e "${GREEN}Namespace ready${NC}"
echo "----------------------------------------"

# Step 1: Deploy only MongoDB first
echo -e "${BLUE}Deploying MongoDB...${NC}"
if [ -f "shared/mongodb/deployment.yaml" ]; then
    echo -e "Applying MongoDB deployment..."
    microk8s kubectl apply -f shared/mongodb/deployment.yaml -n $NAMESPACE
else
    echo -e "${RED}Error: MongoDB deployment file not found${NC}"
    exit 1
fi

if [ -f "shared/mongodb/service.yaml" ]; then
    echo -e "Applying MongoDB service..."
    microk8s kubectl apply -f shared/mongodb/service.yaml -n $NAMESPACE
else
    echo -e "${RED}Error: MongoDB service file not found${NC}"
    exit 1
fi

# Wait for MongoDB to be ready
echo -e "${BLUE}Waiting for MongoDB pod to be ready...${NC}"
microk8s kubectl wait --for=condition=ready pods -l app=mongodb -n $NAMESPACE --timeout=180s

# Find MongoDB pod
echo -e "${BLUE}Finding MongoDB pod...${NC}"
MONGODB_POD=$(microk8s kubectl get pods -n $NAMESPACE -l app=mongodb -o jsonpath='{.items[0].metadata.name}')

if [ -z "$MONGODB_POD" ]; then
  echo -e "${RED}Error: MongoDB pod not found${NC}"
  exit 1
fi

echo -e "${GREEN}Found MongoDB pod: $MONGODB_POD${NC}"

# Step 2: Add subscriber to MongoDB
echo -e "${BLUE}Adding subscriber with IMSI $IMSI to MongoDB...${NC}"

# Create MongoDB script with fixed syntax
cat > /tmp/add-subscriber.js << EOF
db = db.getSiblingDB('open5gs');

// Check if subscribers collection exists
if (!db.getCollectionNames().includes('subscribers')) {
    db.createCollection('subscribers');
    print("Created subscribers collection");
}

// Add subscriber with IMSI $IMSI
db.subscribers.updateOne(
    { imsi: "$IMSI" },
    {
        \$setOnInsert: {
            "schema_version": NumberInt(1),
            "imsi": "$IMSI",
            "msisdn": [],
            "imeisv": "1110000000000000",
            "mme_host": [],
            "mm_realm": [],
            "purge_flag": [],
            "slice":[
            {
                "sst": NumberInt(1),
                "sd": "000001",
                "default_indicator": true,
                "session": [
                {
                    "name" : "internet",
                    "type" : NumberInt(3),
                    "qos" :
                    { "index": NumberInt(9),
                        "arp":
                        {
                            "priority_level" : NumberInt(8),
                            "pre_emption_capability": NumberInt(1),
                            "pre_emption_vulnerability": NumberInt(1)
                        }
                    },
                    "ambr":
                    {
                        "downlink":
                        {
                            "value": NumberInt(1),
                            "unit": NumberInt(3)
                        },
                        "uplink":
                        {
                            "value": NumberInt(1),
                            "unit": NumberInt(3)
                        }
                    },
                    "pcc_rule": [],
                    "_id": new ObjectId(),
                }],
                "_id": new ObjectId(),
            }],
            "security":
            {
                "k" : "$KEY",
                "op" : null,
                "opc" : "$OPC",
                "amf" : "8000",
                "sqn" : NumberLong(1184)
            },
            "ambr" :
            {
                "downlink" : { "value": NumberInt(1), "unit": NumberInt(3)},
                "uplink" : { "value": NumberInt(1), "unit": NumberInt(3)}
            },
            "access_restriction_data": 32,
            "network_access_mode": 2,
            "subscriber_status": 0,
            "operator_determined_barring": 0,
            "subscribed_rau_tau_timer": 12,
            "__v": 0
        }
    },
    { upsert: true }
);

// Verify subscriber was added
var subscriber = db.subscribers.findOne({imsi: "$IMSI"});
if (subscriber) {
    print("Subscriber " + "$IMSI" + " added or updated successfully");
} else {
    print("ERROR: Failed to add subscriber " + "$IMSI");
}

// Count total subscribers
var count = db.subscribers.count();
print("Total subscribers in database: " + count);
EOF

# Copy script to pod
echo -e "Copying script to MongoDB pod..."
microk8s kubectl cp /tmp/add-subscriber.js $NAMESPACE/$MONGODB_POD:/tmp/add-subscriber.js

# Execute script in pod
echo -e "Executing script in MongoDB pod..."
microk8s kubectl exec -n $NAMESPACE $MONGODB_POD -- mongo --quiet /tmp/add-subscriber.js

# Create verification script with fixed syntax
cat > /tmp/verify-subscriber.js << EOF
db = db.getSiblingDB('open5gs');
var subscriber = db.subscribers.findOne({imsi: "$IMSI"});
if (subscriber) {
    print("SUCCESS: Subscriber " + "$IMSI" + " exists in database");
    printjson(subscriber);
} else {
    print("ERROR: Subscriber " + "$IMSI" + " not found in database");
}
EOF

# Copy and execute verification script
echo -e "Verifying subscriber was added..."
microk8s kubectl cp /tmp/verify-subscriber.js $NAMESPACE/$MONGODB_POD:/tmp/verify-subscriber.js
microk8s kubectl exec -n $NAMESPACE $MONGODB_POD -- mongo --quiet /tmp/verify-subscriber.js

echo -e "${GREEN}Subscriber addition completed${NC}"
echo "----------------------------------------"

# Step 3: Deploy remaining components

# Function to deploy components from a directory
deploy_components() {
    local dir=$1
    local has_configmap=${2:-true}
    
    echo -e "${BLUE}Deploying components from $dir...${NC}"
    
    # Change to the directory
    cd "$dir"
    
    # Apply configmap if it exists and has_configmap is true
    if [ "$has_configmap" = true ] && [ -f "configmap.yaml" ]; then
        echo -e "Applying configmap for $dir..."
        microk8s kubectl apply -f configmap.yaml -n $NAMESPACE
    fi
    
    # Apply deployment
    if [ -f "deployment.yaml" ]; then
        echo -e "Applying deployment for $dir..."
        microk8s kubectl apply -f deployment.yaml -n $NAMESPACE
    else
        echo -e "${RED}Warning: No deployment.yaml found in $dir${NC}"
    fi
    
    # Apply service
    if [ -f "service.yaml" ]; then
        echo -e "Applying service for $dir..."
        microk8s kubectl apply -f service.yaml -n $NAMESPACE
    else
        echo -e "${RED}Warning: No service.yaml found in $dir${NC}"
    fi
    
    echo -e "${GREEN}Finished deploying $dir${NC}"
    echo "----------------------------------------"
    
    # Return to original directory
    cd - > /dev/null
}

# Deploy home directory components
echo -e "${BLUE}Deploying components from the home directory...${NC}"
HOME_COMPONENTS=("ausf" "nrf" "sepp" "udm" "udr")
for component in "${HOME_COMPONENTS[@]}"; do
    deploy_components "home/$component"
done

# Deploy packetrusher
echo -e "${BLUE}Deploying packetrusher...${NC}"
deploy_components "shared/packetrusher"

# Deploy visiting directory components
echo -e "${BLUE}Deploying components from the visiting directory...${NC}"
VISITING_COMPONENTS=("amf" "ausf" "bsf" "nrf" "nssf" "pcf" "sepp" "smf" "upf")
for component in "${VISITING_COMPONENTS[@]}"; do
    deploy_components "visiting/$component"
done

# Wait for all pods to be ready
echo -e "${BLUE}Waiting for all pods to be ready...${NC}"
microk8s kubectl wait --for=condition=ready pods --all --namespace=$NAMESPACE --timeout=300s

# Show status of all resources
echo -e "${BLUE}Showing status of all resources in the $NAMESPACE namespace:${NC}"
echo "----------------------------------------"
echo "Pods:"
microk8s kubectl get pods -n $NAMESPACE
echo "----------------------------------------"
echo "Services:"
microk8s kubectl get services -n $NAMESPACE
echo "----------------------------------------"
echo "Deployments:"
microk8s kubectl get deployments -n $NAMESPACE
echo "----------------------------------------"

echo -e "${GREEN}Deployment complete with subscriber IMSI: $IMSI added to MongoDB${NC}"
echo -e "${GREEN}To add more subscribers, use the add-k8s-subscriber.sh script${NC}" 