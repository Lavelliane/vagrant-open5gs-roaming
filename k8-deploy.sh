#!/bin/bash

# Script to deploy all 5G network functions, MongoDB, and packetrusher
# Created: April 16, 2025

# Exit on error
set -e

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to deploy components from a directory
deploy_components() {
    local dir=$1
    local has_configmap=${2:-true}
    
    echo -e "${BLUE}Deploying components from $dir...${NC}"
    
    # Change to the directory
    cd "$dir"
    
    # Apply configmap if it exists or if has_configmap is true
    if [ "$has_configmap" = true ] && [ -f "configmap.yaml" ]; then
        echo -e "Applying configmap for $dir..."
        microk8s kubectl apply -f configmap.yaml
    fi
    
    # Apply deployment
    if [ -f "deployment.yaml" ]; then
        echo -e "Applying deployment for $dir..."
        microk8s kubectl apply -f deployment.yaml
    else
        echo -e "${RED}Warning: No deployment.yaml found in $dir${NC}"
    fi
    
    # Apply service
    if [ -f "service.yaml" ]; then
        echo -e "Applying service for $dir..."
        microk8s kubectl apply -f service.yaml
    else
        echo -e "${RED}Warning: No service.yaml found in $dir${NC}"
    fi
    
    echo -e "${GREEN}Finished deploying $dir${NC}"
    echo "----------------------------------------"
    
    # Return to original directory
    cd - > /dev/null
}

# Create namespace if it doesn't exist
NAMESPACE="open5gs"
echo -e "${BLUE}Creating namespace $NAMESPACE if it doesn't exist...${NC}"
microk8s kubectl create namespace $NAMESPACE --dry-run=client -o yaml | microk8s kubectl apply -f -
echo -e "${GREEN}Namespace ready${NC}"
echo "----------------------------------------"

# Deploy home directory components
echo -e "${BLUE}Deploying components from the home directory...${NC}"
HOME_COMPONENTS=("ausf" "nrf" "sepp" "udm" "udr")
for component in "${HOME_COMPONENTS[@]}"; do
    deploy_components "home/$component"
done

# Deploy shared directory components (MongoDB has no configmap)
echo -e "${BLUE}Deploying components from the shared directory...${NC}"
deploy_components "shared/mongodb" false
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

echo -e "${GREEN}All 5G network functions, MongoDB, and packetrusher have been deployed!${NC}"