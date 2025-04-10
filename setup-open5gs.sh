#!/bin/bash
# This script will build and run Open5GS with roaming configuration

set -e

echo "Starting Open5GS setup with roaming configuration..."

# Add entries to /etc/hosts
echo "Adding required entries to /etc/hosts..."
cat << EOF | sudo tee -a /etc/hosts
127.0.1.10	nrf.5gc.mnc070.mcc999.3gppnetwork.org
127.0.1.11	ausf.5gc.mnc070.mcc999.3gppnetwork.org
127.0.1.12	udm.5gc.mnc070.mcc999.3gppnetwork.org

127.0.2.10	nrf.5gc.mnc001.mcc001.3gppnetwork.org
127.0.2.11	ausf.5gc.mnc001.mcc001.3gppnetwork.org
127.0.2.12	udm.5gc.mnc001.mcc001.3gppnetwork.org
EOF

echo "Entries added to /etc/hosts"

echo "Starting Open5GS setup with roaming configuration..."

# Navigate to the repository directory
cd /home/vagrant/docker-open5gs

# Make sure .env file is properly configured
echo "Checking and updating .env file..."
# Set MongoDB version to 4.4
grep -q "MONGODB_VERSION=4.4" .env || sed -i "s/MONGODB_VERSION=.*/MONGODB_VERSION=4.4/" .env

# Get the VM IP address and update DOCKER_HOST_IP
# Find the correct network interface (might be enp0s8 in Ubuntu or other)
PRIMARY_INTERFACE="enp0s3"
VM_IP=$(ip -4 addr show $PRIMARY_INTERFACE | grep -oP 'inet \K[\d.]+')

echo "Using specific interface: $PRIMARY_INTERFACE"
echo "Using VM IP Address: $VM_IP"
grep -q "DOCKER_HOST_IP=$VM_IP" .env || sed -i "s/DOCKER_HOST_IP=.*/DOCKER_HOST_IP=$VM_IP/" .env

# Create and configure packetrusher.yaml
echo "Creating packetrusher.yaml configuration..."
mkdir -p configs/roaming
cat > configs/roaming/packetrusher.yaml << 'EOF'
gnodeb:
  controlif:
    ip: "gnb.packetrusher.org"
    port: 38412
  dataif:
    ip: "gnb.packetrusher.org"
    port: 2152
  plmnlist:
    mcc: "999"
    mnc: "70"
    tac: "000001"
    gnbid: "000008"
  slicesupportlist:
    sst: "01"
    sd: "000001"

ue:
  hplmn:
    mcc: "001"
    mnc: "01"
  msin: "1234567891"
  key: "7F176C500D47CF2090CB6D91F4A73479"
  opc: "3D45770E83C7BBB6900F3653FDA6330F"
  dnn: "internet"
  snssai:
    sst: 01
    sd: "000001"
  amf: "8000"
  sqn: "00000000"
  routingindicator: "0000"
  protectionScheme: 0
  integrity:
    nia0: false
    nia1: false
    nia2: true
    nia3: false
  ciphering:
    nea0: true
    nea1: false
    nea2: true
    nea3: false

amfif:
  - ip: "amf.5gc.mnc070.mcc999.3gppnetwork.org"
    port: 38412
logs:
  level: 4
EOF
echo "packetrusher.yaml created successfully in configs/roaming/"

echo "Building Open5GS using Docker Buildx Bake..."
docker buildx bake

# Start MongoDB first so we can add subscribers
echo "Starting MongoDB container..."
docker compose -f compose-files/roaming/docker-compose.yaml --env-file=.env up -d db

# Wait for MongoDB to be ready
echo "Waiting for MongoDB to be ready..."
sleep 10

# Create MongoDB script file for adding the PacketRusher test UE
echo "Creating MongoDB script for adding the PacketRusher test UE..."

cat > /home/vagrant/add-packetrusher-ue.js << 'EOF'
// Add the PacketRusher test UE with IMSI 1234567891
db.subscribers.insertOne(
{
    "_id": new ObjectId(),
    "schema_version": NumberInt(1),
    "imsi": "001011234567891",
    "msisdn": [],
    "imeisv": [],
    "mme_host": [],
    "mm_realm": [],
    "purge_flag": [],
    "slice":[
    {
        "sst": NumberInt(1),
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
                    "pre_emption_vulnerability": NumberInt(2)
                }
            },
            "ambr":
            {
                "downlink":
                {
                    "value": NumberInt(1000000000),
                    "unit": NumberInt(0)
                },
                "uplink":
                {
                    "value": NumberInt(1000000000),
                    "unit": NumberInt(0)
                }
            },
            "pcc_rule": [],
            "_id": new ObjectId(),
        }],
        "_id": new ObjectId(),
    }],
    "security":
    {
        "k" : "7F176C500D47CF2090CB6D91F4A73479",
        "op" : null,
        "opc" : "3D45770E83C7BBB6900F3653FDA6330F",
        "amf" : "8000",
    },
    "ambr" :
    {
        "downlink" : { "value": NumberInt(1000000000), "unit": NumberInt(0)},
        "uplink" : { "value": NumberInt(1000000000), "unit": NumberInt(0)}
    },
    "access_restriction_data": 32,
    "network_access_mode": 0,
    "subscriber_status": 0,
    "operator_determined_barring": 0,
    "subscribed_rau_tau_timer": 12,
    "__v": 0
}
);
EOF

# Also create the Home Network and Visiting Network subscriber scripts for completeness
cat > /home/vagrant/add-home-subscriber.js << 'EOF'
db.subscribers.insertOne(
{
    "_id": new ObjectId(),
    "schema_version": NumberInt(1),
    "imsi": "001010000000001",
    "msisdn": [],
    "imeisv": [],
    "mme_host": [],
    "mm_realm": [],
    "purge_flag": [],
    "slice":[
    {
        "sst": NumberInt(1),
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
                    "pre_emption_vulnerability": NumberInt(2)
                }
            },
            "ambr":
            {
                "downlink":
                {
                    "value": NumberInt(1000000000),
                    "unit": NumberInt(0)
                },
                "uplink":
                {
                    "value": NumberInt(1000000000),
                    "unit": NumberInt(0)
                }
            },
            "pcc_rule": [],
            "_id": new ObjectId(),
        }],
        "_id": new ObjectId(),
    }],
    "security":
    {
        "k" : "465B5CE8B199B49FAA5F0A2EE238A6BC",
        "op" : null,
        "opc" : "E8ED289DEBA952E4283B54E88E6183CA",
        "amf" : "8000",
    },
    "ambr" :
    {
        "downlink" : { "value": NumberInt(1000000000), "unit": NumberInt(0)},
        "uplink" : { "value": NumberInt(1000000000), "unit": NumberInt(0)}
    },
    "access_restriction_data": 32,
    "network_access_mode": 0,
    "subscriber_status": 0,
    "operator_determined_barring": 0,
    "subscribed_rau_tau_timer": 12,
    "__v": 0
}
);
EOF

cat > /home/vagrant/add-visiting-subscriber.js << 'EOF'
db.subscribers.insertOne(
{
    "_id": new ObjectId(),
    "schema_version": NumberInt(1),
    "imsi": "999700000000001",
    "msisdn": [],
    "imeisv": [],
    "mme_host": [],
    "mm_realm": [],
    "purge_flag": [],
    "slice":[
    {
        "sst": NumberInt(1),
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
                    "pre_emption_vulnerability": NumberInt(2)
                }
            },
            "ambr":
            {
                "downlink":
                {
                    "value": NumberInt(1000000000),
                    "unit": NumberInt(0)
                },
                "uplink":
                {
                    "value": NumberInt(1000000000),
                    "unit": NumberInt(0)
                }
            },
            "pcc_rule": [],
            "_id": new ObjectId(),
        }],
        "_id": new ObjectId(),
    }],
    "security":
    {
        "k" : "465B5CE8B199B49FAA5F0A2EE238A6BC",
        "op" : null,
        "opc" : "E8ED289DEBA952E4283B54E88E6183CA",
        "amf" : "8000",
    },
    "ambr" :
    {
        "downlink" : { "value": NumberInt(1000000000), "unit": NumberInt(0)},
        "uplink" : { "value": NumberInt(1000000000), "unit": NumberInt(0)}
    },
    "access_restriction_data": 32,
    "network_access_mode": 0,
    "subscriber_status": 0,
    "operator_determined_barring": 0,
    "subscribed_rau_tau_timer": 12,
    "__v": 0
}
);
EOF

# Create script for showing subscribers
cat > /home/vagrant/show-subscribers.js << 'EOF'
// Show all subscribers in a filtered format
db.subscribers.find({},{'_id':0,'imsi':1,'security.k':1, 'security.opc':1,'slice.session.name':1,'slice.session.ue.ipv4':1}).forEach(printjson);
EOF

# Try to add subscribers using different methods to ensure compatibility
echo "Adding subscribers to the database..."

# Method 1: Using the mongo command (standard for MongoDB 4.4)
if docker exec db which mongo &>/dev/null; then
  echo "Using mongo command..."
  
  # Add the PacketRusher test UE (IMSI 1234567891)
  echo "Adding PacketRusher test UE with IMSI 1234567891..."
  docker exec -i db mongo --quiet mongodb://localhost:27017/open5gs < /home/vagrant/add-packetrusher-ue.js
  
  # Add Home Network subscriber (MCC 001, MNC 001)
  echo "Adding Home Network subscriber (MCC 001, MNC 001)..."
  docker exec -i db mongo --quiet mongodb://localhost:27017/open5gs < /home/vagrant/add-home-subscriber.js
  
  # Add Visiting Network subscriber (MCC 999, MNC 070)
  echo "Adding Visiting Network subscriber (MCC 999, MNC 070)..."
  docker exec -i db mongo --quiet mongodb://localhost:27017/open5gs < /home/vagrant/add-visiting-subscriber.js
  
  # Verify subscribers were added
  echo "Verifying subscribers in the database:"
  docker exec -i db mongo --quiet mongodb://localhost:27017/open5gs < /home/vagrant/show-subscribers.js
  
else
  # Alternative approach: Copy the scripts into the container and execute
  echo "Using alternative method to add subscribers..."
  
  # Add the PacketRusher test UE (IMSI 1234567891)
  echo "Adding PacketRusher test UE with IMSI 1234567891..."
  docker exec -i db sh -c "echo 'use open5gs;' > /tmp/commands.js"
  cat /home/vagrant/add-packetrusher-ue.js >> /tmp/commands.js
  docker exec -i db sh -c "cat /tmp/commands.js | mongo"
  
  # Add Home and Visiting network subscribers
  docker exec -i db sh -c "echo 'use open5gs;' > /tmp/commands.js"
  cat /home/vagrant/add-home-subscriber.js >> /tmp/commands.js
  docker exec -i db sh -c "cat /tmp/commands.js | mongo"
  
  docker exec -i db sh -c "echo 'use open5gs;' > /tmp/commands.js"
  cat /home/vagrant/add-visiting-subscriber.js >> /tmp/commands.js
  docker exec -i db sh -c "cat /tmp/commands.js | mongo"
  
  # Show all subscribers
  docker exec -i db sh -c "echo 'use open5gs; db.subscribers.find({},{\"_id\":0,\"imsi\":1,\"security.k\":1,\"security.opc\":1,\"slice.session.name\":1,\"slice.session.ue.ipv4\":1}).forEach(printjson);' | mongo"
fi

# Create a helper script for adding subscribers
cat > /home/vagrant/add-subscriber.sh << 'EOF'
#!/bin/bash
# Script to add a subscriber to Open5GS

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <imsi> <key> <opc>"
    echo "Example: $0 001010000000002 465B5CE8B199B49FAA5F0A2EE238A6BC E8ED289DEBA952E4283B54E88E6183CA"
    exit 1
fi

IMSI=$1
KEY=$2
OPC=$3

# Create temporary MongoDB script
cat > /tmp/add-sub.js << EOL
use open5gs;
db.subscribers.insertOne(
{
    "_id": new ObjectId(),
    "schema_version": NumberInt(1),
    "imsi": "${IMSI}",
    "msisdn": [],
    "imeisv": [],
    "mme_host": [],
    "mm_realm": [],
    "purge_flag": [],
    "slice":[
    {
        "sst": NumberInt(1),
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
                    "pre_emption_vulnerability": NumberInt(2)
                }
            },
            "ambr":
            {
                "downlink":
                {
                    "value": NumberInt(1000000000),
                    "unit": NumberInt(0)
                },
                "uplink":
                {
                    "value": NumberInt(1000000000),
                    "unit": NumberInt(0)
                }
            },
            "pcc_rule": [],
            "_id": new ObjectId(),
        }],
        "_id": new ObjectId(),
    }],
    "security":
    {
        "k" : "${KEY}",
        "op" : null,
        "opc" : "${OPC}",
        "amf" : "8000",
    },
    "ambr" :
    {
        "downlink" : { "value": NumberInt(1000000000), "unit": NumberInt(0)},
        "uplink" : { "value": NumberInt(1000000000), "unit": NumberInt(0)}
    },
    "access_restriction_data": 32,
    "network_access_mode": 0,
    "subscriber_status": 0,
    "operator_determined_barring": 0,
    "subscribed_rau_tau_timer": 12,
    "__v": 0
}
);
EOL

# Try to execute using mongo command first
if docker exec db which mongo &>/dev/null; then
  docker exec -i db mongo < /tmp/add-sub.js
else
  # Copy and execute the command file in the container
  docker cp /tmp/add-sub.js db:/tmp/add-sub.js
  docker exec db mongo < /tmp/add-sub.js
fi

echo "Subscriber ${IMSI} added successfully"
EOF

chmod +x /home/vagrant/add-subscriber.sh

# Start the rest of the services
echo "Starting the remaining Open5GS services..."
docker compose -f compose-files/roaming/docker-compose.yaml --env-file=.env up -d

echo "Checking if services are running..."
docker ps

echo "Open5GS is now running with roaming configuration and test subscribers added!"
echo "You can access MongoDB on localhost:27017"
echo "AMF N2 interface is available on $VM_IP:38412 (SCTP)"
echo "UPF N3 interface is available on $VM_IP:2152 (UDP)"
echo ""
echo "Added subscribers:"
echo "1. PacketRusher test UE: IMSI 1234567891"
echo "2. Home Network: IMSI 001010000000001"
echo "3. Visiting Network: IMSI 999700000000001"
echo ""
echo "To add more subscribers, use the add-subscriber.sh script:"
echo "/home/vagrant/add-subscriber.sh <imsi> <key> <opc>"
echo "Example: /home/vagrant/add-subscriber.sh 001010000000002 465B5CE8B199B49FAA5F0A2EE238A6BC E8ED289DEBA952E4283B54E88E6183CA"
echo ""
echo "To stop the services, run:"
echo "docker compose -f compose-files/roaming/docker-compose.yaml --env-file=.env down"

# Print helpful information
echo ""
echo "Other useful commands:"
echo "- To view logs: docker compose -f compose-files/roaming/docker-compose.yaml --env-file=.env logs -f"
echo "- To restart a specific service: docker compose -f compose-files/roaming/docker-compose.yaml --env-file=.env restart <service-name>"
echo "- To check if PacketRusher test UE is registered: docker logs -f packetrusher"