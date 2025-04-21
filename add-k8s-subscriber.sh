#!/bin/bash
# Script to add a subscriber to Open5GS MongoDB running in Kubernetes

# Default values
NAMESPACE="open5gs"
MONGODB_POD=""
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

# Find MongoDB pod
echo "Finding MongoDB pod in namespace $NAMESPACE..."
MONGODB_POD=$(microk8s kubectl get pods -n $NAMESPACE -l app=mongodb -o jsonpath='{.items[0].metadata.name}')

if [ -z "$MONGODB_POD" ]; then
  echo "Error: MongoDB pod not found in namespace $NAMESPACE"
  exit 1
fi

echo "Found MongoDB pod: $MONGODB_POD"

# Create MongoDB script
cat > /tmp/add-subscriber.js << EOF
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

// Print confirmation
print("Subscriber " + "$IMSI" + " added or updated successfully");

// Show updated subscriber
print("Subscriber details:");
db.subscribers.find({imsi:"$IMSI"},{'_id':0,'imsi':1,'security.k':1,'security.opc':1,'slice.session.name':1}).forEach(printjson);
EOF

# Copy script to pod
echo "Copying script to MongoDB pod..."
microk8s kubectl cp /tmp/add-subscriber.js $NAMESPACE/$MONGODB_POD:/tmp/add-subscriber.js

# Execute script in pod
echo "Executing script in MongoDB pod..."
microk8s kubectl exec -n $NAMESPACE $MONGODB_POD -- mongo --quiet mongodb://localhost:27017/open5gs /tmp/add-subscriber.js

echo "Subscriber operation completed."

# Cleanup
rm /tmp/add-subscriber.js 