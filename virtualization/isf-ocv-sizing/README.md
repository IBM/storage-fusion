# ISF-OCV-Sizing Tool

## Overview
The ISF-OCV-Sizing Tool is a standalone application designed to help users estimate the number of virtual machines (VMs) that can be supported on a given hardware configuration within OpenShift Virtualization on IBM Fusion. It performs calculations based on user inputs and provides sizing recommendations.

## Features
- User-friendly graphical interface
- Calculation engine for VM sizing
- Cross-platform compatibility
- Outputs displayed on the GUI
- Option to run as a microservice within OpenShift

## Installation
### Prerequisites
- Python 3.9 or later installed on your system

### Installing Python on macOS
1. **Install Python via Homebrew:**
    ```sh
    brew install python
    ```

### Creating and Using a Virtual Environment
1. **Create a virtual environment:**
    ```sh
    python3 -m venv venv
    ```

2. **Activate the virtual environment:**
    ```sh
    source venv/bin/activate
    ```

### Steps
1. Clone the repository:
    ```sh
    git clone https://github.com/sandeepbazar/isf-ocv-sizing.git
    ```
2. Navigate to the project directory:
    ```sh
    cd isf-ocv-sizing
    ```
3. Install dependencies:
    ```sh
    pip install -r requirements.txt
    ```

## Usage
### Running the Application
To run the application as a standalone tool, execute:
    ```
python src/main.py
    ```

## Inputs
- Number of schedulable nodes and their specifications (CPU, Memory, Overhead)
- VM Instance Type
  - Predefined T-shirt size from dropdown (single selection)
  - Custom size (multiple selections or both)

## Outputs
- Total CPU and memory required
- Number of VMs that can be scheduled
- Number of additional nodes or a node with specific CPU/Memory required to schedule all requested VMs if the current configuration is insufficient

## Components
### GUI Application
Handles user interactions and displays results. Can be extended to run as a web interface when deployed as a microservice.

### Calculation Engine
Performs the VM sizing calculations based on the inputs provided by the user.

## Architecture
The application consists of the following key components:
- **GUI Application:** Handles user interactions and displays results.
- **Calculation Engine:** Core logic for sizing calculations.
![image](https://media.github.ibm.com/user/220167/files/20c7d77b-53d1-4c73-9829-974194ea68b4)

## Sequence for VM Sizing Calculation
- User inputs number of Nodes.
- User provides specifications for each Node (CPU, Memory, Overhead).
- User selects VM Instance Type (Predefined T-shirt size or Custom size).
- The GUI interface passes these specifications to the Calculation Engine.
- The Calculation Engine performs calculations based on user inputs.
- Results are sent back to the GUI for display.
![diagram (1)](https://media.github.ibm.com/user/220167/files/697ad05d-684f-4cdd-940b-6d21ff709158)

## Future Enhancements
- Integrate the tool as a microservice within OpenShift.
- Expose a route to access the tool’s UI from the OpenShift console.
- Extend support for additional VM configurations and advanced performance metrics.

