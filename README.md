# vagrant-open5gs-roaming

A Vagrant-based environment for deploying Open5GS with roaming capabilities between two networks. This project automates the setup of a complete 5G core network with inter-PLMN roaming support using Docker containers.

## Features

- Fully automated deployment of Open5GS 5G core network
- Pre-configured roaming between home network (MCC: 001, MNC: 01) and visiting network (MCC: 999, MNC: 70)
- Includes test subscribers for both networks
- PacketRusher integration for UE simulation and testing
- MongoDB database for subscriber management
- Helper scripts for adding and managing subscribers

## Requirements

- Vagrant 2.2.x or higher
- VirtualBox 6.1.x or higher
- At least 4GB RAM and 2 CPU cores available for the VM
