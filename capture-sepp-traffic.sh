#!/bin/bash
# Script to capture traffic between h-sepp and v-sepp containers

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to display help
show_help() {
    echo -e "${BLUE}SEPP Traffic Capture Tool${NC}"
    echo "This script helps capture and analyze traffic between h-sepp and v-sepp containers."
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help       Show this help message"
    echo "  -t, --time TIME  Capture duration in seconds (default: 60)"
    echo "  -o, --output FILE Output file name (default: sepp_traffic.pcap)"
    echo "  -f, --filter FILTER Additional tcpdump filter (default: tcp port 80)"
    echo "  -w, --wireshark  Open Wireshark after capture (if installed)"
    echo "  -i, --interface IFACE  Specify interface (default: auto-detect)"
    echo
}

# Default values
CAPTURE_TIME=60
OUTPUT_FILE="sepp_traffic.pcap"
FILTER="tcp port 80"
OPEN_WIRESHARK=false
INTERFACE=""

# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -t|--time)
            CAPTURE_TIME="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -f|--filter)
            FILTER="$2"
            shift 2
            ;;
        -w|--wireshark)
            OPEN_WIRESHARK=true
            shift
            ;;
        -i|--interface)
            INTERFACE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

# Check if tcpdump is installed
if ! command_exists tcpdump; then
    echo -e "${YELLOW}tcpdump is not installed. Installing...${NC}"
    apt-get update && apt-get install -y tcpdump
fi

# Install Wireshark if requested and not installed
if [ "$OPEN_WIRESHARK" = true ] && ! command_exists wireshark; then
    echo -e "${YELLOW}Wireshark is not installed. Installing...${NC}"
    apt-get update && apt-get install -y wireshark-qt
    # Add current user to wireshark group
    usermod -aG wireshark $SUDO_USER
    echo -e "${YELLOW}Added $SUDO_USER to wireshark group. You might need to log out and back in.${NC}"
fi

echo -e "${BLUE}Getting IP addresses of SEPP containers...${NC}"

# Get container IPs
H_SEPP_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' h-sepp 2>/dev/null)
V_SEPP_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' v-sepp 2>/dev/null)

if [ -z "$H_SEPP_IP" ] || [ -z "$V_SEPP_IP" ]; then
    echo -e "${RED}Failed to get container IPs. Are the containers running?${NC}"
    echo "h-sepp IP: ${H_SEPP_IP:-Not found}"
    echo "v-sepp IP: ${V_SEPP_IP:-Not found}"
    exit 1
fi

echo -e "${GREEN}h-sepp IP: $H_SEPP_IP${NC}"
echo -e "${GREEN}v-sepp IP: $V_SEPP_IP${NC}"

# Auto-detect network interface if not specified
if [ -z "$INTERFACE" ]; then
    # Try to find the br-ogs interface first
    INTERFACE=$(ip link show | grep br-ogs | awk -F: '{print $2}' | tr -d ' ')
    
    # If br-ogs not found, try to find docker0
    if [ -z "$INTERFACE" ]; then
        INTERFACE=$(ip link show | grep docker0 | awk -F: '{print $2}' | tr -d ' ')
    fi
    
    # If still not found, use any interface that's up
    if [ -z "$INTERFACE" ]; then
        INTERFACE=$(ip -o link show up | grep -v "lo" | awk -F': ' '{print $2}' | head -n 1)
    fi
fi

if [ -z "$INTERFACE" ]; then
    echo -e "${RED}Failed to auto-detect network interface. Please specify with -i flag.${NC}"
    exit 1
fi

echo -e "${GREEN}Using network interface: $INTERFACE${NC}"

# Prepare tcpdump command with filter for h-sepp and v-sepp traffic
TCPDUMP_CMD="tcpdump -i $INTERFACE -nn 'host $H_SEPP_IP and host $V_SEPP_IP and ($FILTER)' -w $OUTPUT_FILE"
echo -e "${BLUE}Capture command: ${TCPDUMP_CMD}${NC}"

# Start capture
echo -e "${YELLOW}Starting capture for $CAPTURE_TIME seconds...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop capture early${NC}"

eval "$TCPDUMP_CMD &"
TCPDUMP_PID=$!

# Wait for specified time
sleep $CAPTURE_TIME &
SLEEP_PID=$!

# Wait for either sleep to finish or user to press Ctrl+C
wait $SLEEP_PID
kill $TCPDUMP_PID 2>/dev/null

echo -e "${GREEN}Capture complete. Output saved to $OUTPUT_FILE${NC}"

# Check file size
FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
PACKET_COUNT=$(tcpdump -r "$OUTPUT_FILE" -nn | wc -l)

echo -e "${GREEN}Captured $PACKET_COUNT packets ($FILE_SIZE)${NC}"

# Open in Wireshark if requested
if [ "$OPEN_WIRESHARK" = true ] && command_exists wireshark; then
    echo -e "${BLUE}Opening capture in Wireshark...${NC}"
    if [ -n "$SUDO_USER" ]; then
        su - $SUDO_USER -c "wireshark $OUTPUT_FILE &"
    else
        wireshark "$OUTPUT_FILE" &
    fi
else
    # Suggest command to analyze with tshark
    if command_exists tshark; then
        echo -e "${BLUE}To analyze with tshark, run:${NC}"
        echo "tshark -r $OUTPUT_FILE -Y 'http'"
    fi
    
    echo -e "${BLUE}To copy the capture file to your local machine, run:${NC}"
    echo "scp $OUTPUT_FILE your-username@your-host:/destination/path/"
fi

echo -e "${BLUE}To see HTTP traffic in the capture file with tcpdump, run:${NC}"
echo "tcpdump -A -r $OUTPUT_FILE 'tcp port 80'"