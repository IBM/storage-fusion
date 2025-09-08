import re
import sys
import pandas as pd
from PyQt5.QtGui import QIcon
from PyQt5.QtWidgets import (QApplication, QWidget, QLabel, QLineEdit, QVBoxLayout, QHBoxLayout, QPushButton,
                             QGroupBox, QSpinBox, QListWidget, QAbstractItemView, QFileDialog, QTableWidget,
                             QTableWidgetItem, QStackedWidget, QFormLayout, QTextEdit, QMainWindow, QGridLayout,
                             QDoubleSpinBox, QComboBox, QTextBrowser, QSpacerItem, QSizePolicy, QScrollArea)
from engine import calculate_vm_sizing, perform_calculation, calculate_infrastructure
from PyQt5.QtCore import Qt


class InfrastructureSelectionPage(QWidget):
    def __init__(self, stack):
        super().__init__()
        self.stack = stack
        self.initUI()

    def initUI(self):
        layout = QVBoxLayout()
        layout.setContentsMargins(30, 20, 30, 20)
        layout.setSpacing(20)

        self.headingLabel = QLabel("OpenShift Virtualization Sizing Tool")
        self.headingLabel.setStyleSheet("font-weight: bold; font-size: 30px;")
        self.headingLabel.setAlignment(Qt.AlignCenter)

        self.descriptionBox = QTextBrowser()
        self.descriptionBox.setOpenExternalLinks(True)
        self.descriptionBox.setText(
            "\nThis sizing tool helps you estimate the number of virtual machines (VMs) "
            "that can be provisioned on IBM Fusion HCI infrastructure.\n"
        )
        self.descriptionBox.append('<a href=https://bit.ly/ocv-sizing>Learn More</a>')
        self.descriptionBox.setStyleSheet("font-size: 16px; background: transparent; ")
        self.descriptionBox.setOpenExternalLinks(True)
        self.descriptionBox.setFixedHeight(130)

        self.label1 = QLabel("Choose how to style your infrastructure")
        self.label1.setStyleSheet("font-weight: bold; font-size: 24px;")
        self.label1.setAlignment(Qt.AlignLeft)

        self.selectionGroup = QGroupBox()
        self.selectionGroup.setStyleSheet("font-weight: bold; font-size: 18px;")
        self.selectionGroup.setAlignment(Qt.AlignLeft)

        selectionLayout = QVBoxLayout()
        selectionLayout.setContentsMargins(20, 20, 20, 20)
        selectionLayout.setSpacing(15)

        self.customInfraButton = QPushButton(

            'Determine if an existing VMware configuration can fit on a predetermined IBM Fusion HCI system'
        )
        self.customInfraButton.setStyleSheet("font-size: 14px; padding: 15px; margin: 10px;")
        self.customInfraButton.clicked.connect(self.goToCustomInfraPage)

        self.uploadInfraButton = QPushButton(
            "Size infrastructure based on an existing VMware configuration"
        )
        self.uploadInfraButton.setStyleSheet("font-size: 14px; padding: 15px; margin: 10px; text-align: left;")
        self.uploadInfraButton.clicked.connect(self.goToUploadInfraPage)

        self.availableInfraButton = QPushButton(
            "Determine how many VMs can be hosted on a predetermined IBM Fusion HCI system"
        )
        self.availableInfraButton.setStyleSheet("font-size: 14px; padding: 15px; margin: 10px; text-align: left;")
        self.availableInfraButton.clicked.connect(self.goToAvailableInfraPage)

        selectionLayout.addWidget(self.customInfraButton)
        selectionLayout.addWidget(self.uploadInfraButton)
        selectionLayout.addWidget(self.availableInfraButton)

        self.selectionGroup.setLayout(selectionLayout)

        layout.addWidget(self.headingLabel)
        layout.addSpacing(40)
        layout.addWidget(self.descriptionBox)
        layout.addSpacing(10)
        layout.addWidget(self.label1)
        layout.addWidget(self.selectionGroup)
        layout.addStretch(1)

        self.setLayout(layout)

    def goToCustomInfraPage(self):
        self.stack.setCurrentIndex(1)

    def goToUploadInfraPage(self):
        self.stack.setCurrentIndex(2)

    def goToAvailableInfraPage(self):
        self.stack.setCurrentIndex(3)


class CustomInfrastructurePage(QWidget):
    def __init__(self, stack):
        super().__init__()
        self.stack = stack
        self.vm_inputs = {}
        self.displayed_vm_types = set()
        self.initUI()

    def initUI(self):
        self.mainLayout = QVBoxLayout()

        self.scrollContent = QWidget()
        self.scrollContent.setLayout(self.mainLayout)

        self.headingLabel = QLabel("Check VMware compatibility with IBM Fusion HCI")
        self.headingLabel.setStyleSheet("font-weight: bold; font-size: 19px;")
        self.headingLabel.setAlignment(Qt.AlignCenter)
        self.mainLayout.addWidget(self.headingLabel)

        self.mainLayout.addSpacing(2)

        self.headingLabel1 = QLabel(
            "For determining if an existing VMware configuration can fit on a predetermined IBM Fusion HCI system")
        self.headingLabel1.setStyleSheet("font-size: 14px; ")
        self.headingLabel1.setAlignment(Qt.AlignCenter)
        self.mainLayout.addWidget(self.headingLabel1)

        self.mainLayout.addSpacing(15)

        self.headingLabel2 = QLabel("IBM Fusion HCI infrastructure details")
        self.headingLabel2.setStyleSheet("font-size: 16px; font-weight: bold;")
        self.mainLayout.addWidget(self.headingLabel2)

        self.hciDetailsLayout = QVBoxLayout()

        nodeHeaderLayout = QHBoxLayout()
        self.nodeCountLabel = QLabel("Number of worker/storage nodes:")
        self.nodeCountLabel.setStyleSheet("font-size: 15px;")
        self.nodeCountSpinBox = QSpinBox()
        self.nodeCountSpinBox.setValue(1)
        self.nodeCountSpinBox.setMinimum(1)
        self.nodeCountSpinBox.setRange(1, 100)
        self.nodeCountSpinBox.valueChanged.connect(self.updateNodeFields)

        nodeHeaderLayout.addWidget(self.nodeCountLabel)
        nodeHeaderLayout.addWidget(self.nodeCountSpinBox)
        nodeHeaderLayout.setSpacing(7)
        nodeHeaderLayout.addStretch()
        nodeHeaderLayout.setContentsMargins(0, 0, 0, 0)

        self.hciDetailsLayout.addLayout(nodeHeaderLayout)

        self.nodeFieldsContainer = QWidget()
        self.nodeFieldsLayout = QVBoxLayout(self.nodeFieldsContainer)
        self.hciDetailsLayout.addWidget(self.nodeFieldsContainer)

        overheadLayout1 = QGridLayout()
        cpuOverheadLabel1 = QLabel("Number of storage nodes:")
        self.cpuOverheadInput1 = QLineEdit()
        memoryOverheadLabel1 = QLabel("Number of disks per node:")
        self.memoryOverheadInput1 = QLineEdit()
        storageOverheadLabel1 = QLabel("Size of the disk per node:")
        self.storageOverheadInput1 = QLineEdit()
        overheadLayout1.addWidget(cpuOverheadLabel1, 0, 0)
        overheadLayout1.addWidget(self.cpuOverheadInput1, 0, 1)
        overheadLayout1.addWidget(memoryOverheadLabel1, 0, 2)
        overheadLayout1.addWidget(self.memoryOverheadInput1, 0, 3)
        overheadLayout1.addWidget(storageOverheadLabel1, 0, 4)
        overheadLayout1.addWidget(self.storageOverheadInput1, 0, 5)

        self.hciDetailsLayout.addLayout(overheadLayout1)


        clusterLayout = QHBoxLayout()
        storageLabel = QLabel("Enter storage of entire cluster (GiB):")
        storageLabel.setStyleSheet("font-size: 14px;")
        storageLabel.setFixedWidth(245)

        self.storageInput = QLineEdit()
        self.storageInput.setFixedSize(140, 20)
        self.storageInput.setStyleSheet("font-size: 12px;")

        clusterLayout.addWidget(storageLabel)
        clusterLayout.addWidget(self.storageInput)
        clusterLayout.setAlignment(Qt.AlignLeft)

        self.hciDetailsLayout.addLayout(clusterLayout)
        self.hciDetailsLayout.addSpacing(5)

        overheadLayout = QGridLayout()
        cpuOverheadLabel = QLabel("CPU Overhead (vCPU):")
        self.cpuOverheadInput = QLineEdit()
        memoryOverheadLabel = QLabel("Memory Overhead (GiB):")
        self.memoryOverheadInput = QLineEdit()
        storageOverheadLabel = QLabel("Storage Overhead (GiB):")
        self.storageOverheadInput = QLineEdit()
        overheadLayout.addWidget(cpuOverheadLabel, 0, 0)
        overheadLayout.addWidget(self.cpuOverheadInput, 0, 1)
        overheadLayout.addWidget(memoryOverheadLabel, 0, 2)
        overheadLayout.addWidget(self.memoryOverheadInput, 0, 3)
        overheadLayout.addWidget(storageOverheadLabel, 0, 4)
        overheadLayout.addWidget(self.storageOverheadInput, 0, 5)

        self.hciDetailsLayout.addLayout(overheadLayout)
        self.hciDetailsLayout.addSpacing(10)

        otherDetailsLayout = QGridLayout()
        highAvailabilityLabel = QLabel("High Availability (%): ")
        highAvailabilityLabel.setFixedWidth(140)
        #highAvailabilityLabel.setAlignment(Qt.AlignLeft)
        self.highAvailabilityInput = QLineEdit()
        self.highAvailabilityInput.setFixedSize(210, 20)
        #self.highAvailabilityInput.setStyleSheet("font-size: 15px;")
        #self.highAvailabilityInput.setAlignment(Qt.AlignLeft)

        overcommitRatioLabel = QLabel("Overcommit Ratio (vCPU): ")
        overcommitRatioLabel.setFixedWidth(170)
        self.overcommitRatioInput = QLineEdit()
        self.overcommitRatioInput.setFixedSize(200, 20)
        #self.overcommitRatioInput.setStyleSheet("font-size: 15px;")
        #self.overcommitRatioInput.setAlignment(Qt.AlignLeft)

        otherDetailsLayout.addWidget(highAvailabilityLabel, 0, 0)
        otherDetailsLayout.addWidget(self.highAvailabilityInput, 0, 1)
        otherDetailsLayout.addWidget(overcommitRatioLabel, 0, 2)
        otherDetailsLayout.addWidget(self.overcommitRatioInput, 0, 3)

        self.hciDetailsLayout.addLayout(otherDetailsLayout)

        self.hciDetailsGroup = QGroupBox()
        self.hciDetailsGroup.setLayout(self.hciDetailsLayout)
        self.mainLayout.addWidget(self.hciDetailsGroup)

        self.mainLayout.addSpacing(5)

        self.headingLabel3 = QLabel("VM deployment configuration")
        self.headingLabel3.setStyleSheet("font-size: 16px; font-weight: bold;")
        self.mainLayout.addWidget(self.headingLabel3)

        self.vmConfigurationGroup = QGroupBox()
        vmConfigLayout = QVBoxLayout()
        self.vm_selection_label = QLabel("Select VM Types:")
        self.vm_selection_list = QListWidget()
        self.vm_selection_list.setSelectionMode(QAbstractItemView.MultiSelection)
        self.vm_selection_list.addItems([
            'Custom VM',
            'small (1 CPU, 2 GiB)',
            'medium (1 CPU, 4 GiB)',
            'large (2 CPUs, 8 GiB)'
        ])
        self.vm_selection_list.setFixedHeight(65)
        vmConfigLayout.addWidget(self.vm_selection_label)
        vmConfigLayout.addWidget(self.vm_selection_list)
        self.vmFieldsContainer = QWidget()
        self.vmFieldsLayout = QVBoxLayout(self.vmFieldsContainer)
        vmConfigLayout.addWidget(self.vmFieldsContainer)
        self.vmConfigurationGroup.setLayout(vmConfigLayout)
        self.mainLayout.addWidget(self.vmConfigurationGroup)
        self.vm_selection_list.itemSelectionChanged.connect(self.handle_vm_selection_change)

        buttonLayout = QHBoxLayout()
        self.calculateButton = QPushButton("Calculate")
        self.calculateButton.setStyleSheet(
            "font-size: 14px; padding: 10px; font-weight: bold; background-color: #525CEB;;")
        self.calculateButton.clicked.connect(self.performCalculation)

        self.backButton = QPushButton("Start over")
        self.backButton.setStyleSheet("font-size: 14px; padding: 10px; font-weight: bold; background-color: #0F0F0F;")
        self.backButton.clicked.connect(self.goToSelectionPage)

        buttonLayout.addWidget(self.calculateButton)
        buttonLayout.addWidget(self.backButton)
        buttonLayout.setSpacing(20)
        self.mainLayout.addLayout(buttonLayout)

        self.outputLabel = QLabel("Result:")
        self.outputLabel.setStyleSheet("font-weight: bold;")
        self.outputArea = QTextEdit()
        self.outputArea.setStyleSheet("border: 1px solid #ddd; padding: 10px;")
        self.outputArea.setFixedHeight(220)
        self.outputArea.setReadOnly(True)
        self.mainLayout.addSpacing(10)
        self.mainLayout.addWidget(self.outputLabel)
        self.mainLayout.addWidget(self.outputArea)

        self.scrollArea = QScrollArea()
        self.scrollArea.setWidget(self.scrollContent)
        self.scrollArea.setWidgetResizable(True)

        layout = QVBoxLayout(self)
        layout.addWidget(self.scrollArea)
        self.resize(900, 900)

        self.updateNodeFields()

    def updateNodeFields(self):
        for i in reversed(range(self.nodeFieldsLayout.count())):
            layout_item = self.nodeFieldsLayout.itemAt(i)
            if layout_item:
                widget = layout_item.widget()
                if widget:
                    widget.deleteLater()
                else:
                    layout_item.layout().deleteLater()

        num_nodes = self.nodeCountSpinBox.value()
        for i in range(1, num_nodes + 1):
            nodeLayout = QHBoxLayout()
            nodeCpuLabel = QLabel(f"Node {i} CPU (cpu cores)")
            nodeCpuInput = QLineEdit()
            nodeMemLabel = QLabel(f" Memory (GiB)")
            nodeMemInput = QLineEdit()
            nodeLayout.addWidget(nodeCpuLabel)
            nodeLayout.addWidget(nodeCpuInput)
            nodeLayout.addWidget(nodeMemLabel)
            nodeLayout.addWidget(nodeMemInput)
            self.nodeFieldsLayout.addLayout(nodeLayout)

        #self.adjustSize()

    def handle_vm_selection_change(self):
        """
        This method will handle the VM type selection
        """
        selected_items = [item.text() for item in self.vm_selection_list.selectedItems()]

        new_vm_types = set(selected_items) - self.displayed_vm_types
        removed_vm_types = self.displayed_vm_types - set(selected_items)

        self.clear_vm_fields(removed_vm_types)

        for vm_type in new_vm_types:
            if vm_type == 'Custom VM':
                self.setup_custom_vm_inputs()
            else:
                self.setup_vm_inputs(vm_type)

        self.displayed_vm_types.update(new_vm_types)
        self.displayed_vm_types.difference_update(removed_vm_types)

    def setup_vm_inputs(self, vm_type):
        """
        This method will accept inputs of selected VM types.
        """
        if vm_type in self.displayed_vm_types:
            return

        label = QLabel(vm_type + ":")
        num_vms_label = QLabel("Number of VMs:")
        num_vms_input = QSpinBox()
        num_vms_input.setRange(1, 1000)
        num_vms_input.setValue(1)

        storage_label = QLabel("Storage (GiB):")
        storage_input = QSpinBox()
        storage_input.setRange(1, 1000)
        storage_input.setValue(30)

        cpu, memory = self.extract_cpu_memory(vm_type)

        cpu_input = QSpinBox()
        cpu_input.setValue(cpu)

        memory_input = QSpinBox()
        memory_input.setValue(memory)

        input_layout = QHBoxLayout()
        input_layout.addWidget(label)
        input_layout.addWidget(num_vms_label)
        input_layout.addWidget(num_vms_input)
        input_layout.addWidget(storage_label)
        input_layout.addWidget(storage_input)

        self.vmFieldsLayout.addLayout(input_layout)

        self.vm_inputs[vm_type] = {
            'num_vms_input': num_vms_input,
            'cpu': cpu_input,
            'memory': memory_input,
            'storage': storage_input
        }

    def setup_custom_vm_inputs(self):
        """
        This method will accept inputs of custom VM types.
        """
        if 'Custom VM' in self.displayed_vm_types:
            return

        label = QLabel("Custom VM :")
        self.vmFieldsLayout.addWidget(label)
        num_vms_label = QLabel("Number of VMs:")
        num_vms_input = QSpinBox()
        num_vms_input.setRange(1, 1000)
        num_vms_input.setValue(1)

        cpu_label = QLabel("CPU (vCPU):")
        cpu_input = QSpinBox()
        cpu_input.setRange(1, 1024)
        cpu_input.setValue(1)

        mem_label = QLabel("Memory (GiB):")
        mem_input = QSpinBox()
        mem_input.setRange(1, 1024)
        mem_input.setValue(1)

        st_label = QLabel("Storage (GiB):")
        st_input = QSpinBox()
        st_input.setRange(1, 1000)
        st_input.setValue(1)

        input_layout = QHBoxLayout()
        input_layout.addWidget(num_vms_label)
        input_layout.addWidget(num_vms_input)
        input_layout.addWidget(cpu_label)
        input_layout.addWidget(cpu_input)
        input_layout.addWidget(mem_label)
        input_layout.addWidget(mem_input)
        input_layout.addWidget(st_label)
        input_layout.addWidget(st_input)

        self.vmFieldsLayout.addLayout(input_layout)

        self.vm_inputs['Custom VM'] = {
            'num_vms_input': num_vms_input,
            'cpu': cpu_input,
            'memory': mem_input,
            'storage': st_input
        }

    def clear_vm_fields(self, vm_types_to_clear):
        """
        Clears VM input fields for the specified VM types.
        """
        for vm_type in vm_types_to_clear:
            for i in reversed(range(self.vmFieldsLayout.count())):
                layout_item = self.vmFieldsLayout.itemAt(i)
                if layout_item:
                    layout = layout_item.layout()
                    if layout:
                        should_remove_layout = False
                        for j in range(layout.count()):
                            sub_item = layout.itemAt(j)
                            if sub_item:
                                widget = sub_item.widget()
                                if widget and vm_type in widget.text():
                                    should_remove_layout = True
                                    break

                        if should_remove_layout:
                            for j in reversed(range(layout.count())):
                                sub_item = layout.itemAt(j)
                                if sub_item:
                                    widget = sub_item.widget()
                                    if widget:
                                        widget.deleteLater()
                                    else:
                                        sub_item.layout().deleteLater()
                            self.vmFieldsLayout.removeItem(layout)
                            layout.deleteLater()

        self.vmFieldsLayout.update()
        self.update()

    def extract_cpu_memory(self, vm_type):
        """
        Extract CPU, memory based on VM type
        param vm_type: type of VM
        return: tuple of (cpu, memory)
        """
        if vm_type == 'small (1 CPU, 2 GiB)':
            return 1, 2
        elif vm_type == 'medium (1 CPU, 4 GiB)':
            return 1, 4
        elif vm_type == 'large (2 CPUs, 8 GiB)':
            return 2, 8
        return 0, 0

    def performCalculation(self):
        try:
            node_count = self.nodeCountSpinBox.value()
            cpu_overhead = float(self.cpuOverheadInput.text() or 0)
            memory_overhead = float(self.memoryOverheadInput.text() or 0)
            storage_overhead = float(self.storageOverheadInput.text() or 0)
            total_storage_capacity = float(self.storageInput.text() or 0)
            ha_reserve_percent = float(self.highAvailabilityInput.text() or 0) / 100
            overcommit_ratio = float(self.overcommitRatioInput.text() or 1.0)
            num_drives = int(self.memoryOverheadInput1.text() or 0)

            node_details = []
            for i in range(self.nodeFieldsLayout.count()):
                layout_item = self.nodeFieldsLayout.itemAt(i)
                if layout_item:
                    layout = layout_item.layout()
                    if layout:
                        cpu_widget = layout.itemAt(1).widget()
                        mem_widget = layout.itemAt(3).widget()
                        if cpu_widget and mem_widget:
                            try:
                                cpu_value = float(cpu_widget.text())
                                memory_value = float(mem_widget.text())
                                node_details.append({'cpu': cpu_value, 'memory': memory_value})
                            except ValueError:
                                pass

            vm_inputs = {}
            for vm_type, vm_info in self.vm_inputs.items():
                num_vms = vm_info['num_vms_input'].value()
                cpu_value = vm_info['cpu'].value()
                memory_value = vm_info['memory'].value()
                storage_value = vm_info['storage'].value()

                vm_inputs[vm_type] = {
                    'num_vms': num_vms,
                    'cpu': cpu_value,
                    'memory': memory_value,
                    'storage': storage_value
                }

            result_text = perform_calculation(
                node_count, cpu_overhead, memory_overhead, storage_overhead,
                total_storage_capacity, ha_reserve_percent, overcommit_ratio,
                node_details, vm_inputs, num_drives
            )

            self.outputArea.setPlainText(result_text)

        except Exception as e:
            self.outputArea.setPlainText(f"Error: {str(e)}")

    def goToSelectionPage(self):
        self.stack.setCurrentIndex(0)


class UploadInfrastructurePage(QWidget):
    def __init__(self, stack):
        super().__init__()
        self.stack = stack
        self.initUI()

    def initUI(self):
        self.mainLayout = QVBoxLayout()
        self.mainLayout.setContentsMargins(20, 20, 20, 20)
        self.mainLayout.setSpacing(10)

        headingLayout = QVBoxLayout()
        headingLayout.setSpacing(1)

        self.headingLabel = QLabel("Size your IBM Fusion HCI infrastructure for VMware")
        self.headingLabel.setStyleSheet("font-weight: bold; font-size: 20px;")
        self.headingLabel.setAlignment(Qt.AlignCenter)
        headingLayout.addWidget(self.headingLabel)

        self.headingLabel1 = QLabel(
            "For sizing infrastructure based on an existing VMware configuration"
        )
        self.headingLabel1.setStyleSheet("font-size: 14px;")
        self.headingLabel1.setAlignment(Qt.AlignCenter)
        headingLayout.addWidget(self.headingLabel1)

        self.mainLayout.addLayout(headingLayout)

        self.mainLayout.addSpacing(10)

        self.fileUploadGroup = QGroupBox("Import the VM configuration exported from VCenter")
        self.fileUploadGroup.setStyleSheet("font-weight: bold; font-size: 14px; padding: 10px;")
        fileUploadLayout = QVBoxLayout()
        fileUploadLayout.setSpacing(5)

        self.upload_label = QLabel('Upload File:')
        self.upload_label.setStyleSheet("font-size: 12px;")

        self.upload_button = QPushButton('Upload')
        self.upload_button.setStyleSheet("font-size: 14px; padding: 10px; background-color: #525CEB; color: white;")
        self.upload_button.setFixedSize(250, 40)

        self.upload_button.clicked.connect(self.upload_file_dialog)

        fileUploadLayout.addWidget(self.upload_label)
        fileUploadLayout.addWidget(self.upload_button)
        self.fileUploadGroup.setLayout(fileUploadLayout)

        self.mainLayout.addWidget(self.fileUploadGroup)

        self.mainLayout.addSpacing(10)

        self.detailsGroup = QGroupBox("Additional requirements for IBM Fusion HCI infrastructure")
        self.detailsGroup.setStyleSheet("font-weight: bold; font-size: 14px; padding: 10px;")

        detailsLayout = QFormLayout()
        detailsLayout.setLabelAlignment(Qt.AlignRight)
        detailsLayout.setFieldGrowthPolicy(QFormLayout.ExpandingFieldsGrow)

        self.overhead_cpu = QLineEdit()
        self.overhead_cpu.setAlignment(Qt.AlignLeft)
        self.overhead_cpu.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)

        self.overhead_memory = QLineEdit()
        self.overhead_memory.setAlignment(Qt.AlignLeft)
        self.overhead_memory.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)

        self.overhead_storage = QLineEdit()
        self.overhead_storage.setAlignment(Qt.AlignLeft)
        self.overhead_storage.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)

        self.ha = QLineEdit()
        self.ha.setAlignment(Qt.AlignLeft)
        self.ha.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)

        self.overcommit_cpu = QLineEdit()
        self.overcommit_cpu.setAlignment(Qt.AlignLeft)
        self.overcommit_cpu.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)

        detailsLayout.addRow("CPU Overhead (vCPU):", self.overhead_cpu)
        detailsLayout.addRow("Memory Overhead (GiB):", self.overhead_memory)
        detailsLayout.addRow("Storage Overhead (GiB):", self.overhead_storage)
        detailsLayout.addRow("High Availability (%):", self.ha)
        detailsLayout.addRow("Overcommit Ratio (vCPU):", self.overcommit_cpu)

        self.detailsGroup.setLayout(detailsLayout)

        self.buttonLayout = QHBoxLayout()
        self.buttonLayout.setSpacing(20)

        self.calculateButton = QPushButton("Calculate")
        self.calculateButton.setStyleSheet(
            "font-size: 14px; padding: 10px; font-weight: bold; background-color: #525CEB;")
        self.calculateButton.clicked.connect(self.performCalculation)

        self.backButton = QPushButton("Start over")
        self.backButton.setStyleSheet("font-size: 14px; padding: 10px; font-weight: bold; background-color: #0F0F0F;")
        self.backButton.clicked.connect(self.goToSelectionPage)

        self.buttonLayout.addWidget(self.calculateButton)
        self.buttonLayout.addWidget(self.backButton)

        self.result_label = QLabel('Results:')
        self.result_label.setStyleSheet("font-size: 14px; font-weight: bold; margin-top: 5px;")

        self.result_text = QTextEdit()
        self.result_text.setReadOnly(True)
        self.result_text.setFixedHeight(230)
        self.result_text.setStyleSheet("border: 1px solid #ddd; padding: 10px;")

        self.mainLayout.addWidget(self.detailsGroup)
        self.mainLayout.addSpacing(15)
        self.mainLayout.addLayout(self.buttonLayout)
        self.mainLayout.addSpacing(0)
        self.mainLayout.addWidget(self.result_label)
        self.mainLayout.addWidget(self.result_text)

        self.setLayout(self.mainLayout)
        self.resize(900, 900)

    def upload_file_dialog(self):
        """
        Open file dialog to select a CSV or Excel file.
        """
        options = QFileDialog.Options()
        options |= QFileDialog.DontUseNativeDialog
        file_name, _ = QFileDialog.getOpenFileName(self, "Select File", "",
                                                   "Excel Files (*.xlsx);;CSV Files (*.csv)",
                                                   options=options)

        if file_name:
            self.file_name = file_name
            self.result_text.clear()
            self.processFile(file_name)

    def processFile(self, file_path):
        """
        Process the selected file to extract VM specifications.
        """
        if file_path.endswith('.xlsx'):
            df = pd.read_excel(file_path)
        elif file_path.endswith('.csv'):
            df = pd.read_csv(file_path)
        else:
            self.result_text.setPlainText("Unsupported file format.")
            return

        required_columns = {
            'Provisioned Space': 'storage',
            'CPUs': 'cpu',
            'Memory Size': 'memory'
        }

        missing_columns = [col for col in required_columns.keys() if col not in df.columns]
        if missing_columns:
            self.result_text.setPlainText(f"Error: Missing columns - {', '.join(missing_columns)}")
            return

        total_storage = 0
        total_cpu = 0
        total_memory = 0

        # Regex patterns for different units
        storage_pattern = re.compile(r'(\d+\.?\d*)\s*(GB|MB|TB)', re.IGNORECASE)
        memory_pattern = re.compile(r'(\d+\.?\d*)\s*(GB|MB)', re.IGNORECASE)

        # Conversion factors
        gb_to_gb = 1  # GB to GB
        mb_to_gb = 1 / 1024  # MB to GB
        tb_to_gb = 1024  # TB to GB

        for _, row in df.iterrows():
            # Process Provisioned Space
            storage_str = row.get('Provisioned Space', '')
            storage_match = storage_pattern.search(storage_str)
            if storage_match:
                value = float(storage_match.group(1))
                unit = storage_match.group(2).upper()
                if unit == 'GB':
                    total_storage += value * gb_to_gb
                elif unit == 'MB':
                    total_storage += value * mb_to_gb
                elif unit == 'TB':
                    total_storage += value * tb_to_gb

            # Process CPU
            cpu_str = row.get('CPUs', '')
            if isinstance(cpu_str, (int, float)):
                total_cpu += float(cpu_str)

            # Process Memory Size
            memory_str = row.get('Memory Size', '')
            memory_match = memory_pattern.search(memory_str)
            if memory_match:
                value = float(memory_match.group(1))
                unit = memory_match.group(2).upper()
                if unit == 'GB':
                    total_memory += value * gb_to_gb
                elif unit == 'MB':
                    total_memory += value * mb_to_gb

        self.requested_specs = {
            'total_cpu': total_cpu,
            'total_memory': total_memory,
            'total_storage': total_storage
        }

        self.result_text.setPlainText(
            f"Uploaded VM Configuration:\n"
            f"Total CPU: {total_cpu} VCPU\n"
            f"Total Memory: {total_memory:.2f} GiB\n"
            f"Total Storage: {total_storage:.2f} GiB\n"
        )

    def performCalculation(self):
        """
        Perform calculations based on the requested specs and configuration details.
        """
        if not hasattr(self, 'requested_specs'):
            self.result_text.setPlainText("Please upload a file first.")
            return

        requested_specs = self.requested_specs

        try:
            overhead_cpu = float(self.overhead_cpu.text())
        except ValueError:
            overhead_cpu = 0.0

        try:
            overhead_memory = float(self.overhead_memory.text())
        except ValueError:
            overhead_memory = 0.0

        try:
            overhead_storage = float(self.overhead_storage.text())
        except ValueError:
            overhead_storage = 0.0

        try:
            ha = float(self.ha.text()) / 100
        except ValueError:
            ha = 0.0

        try:
            overcommit_cpu = float(self.overcommit_cpu.text())
        except ValueError:
            overcommit_cpu = 1.0

        results = calculate_infrastructure(requested_specs, overhead_cpu, overhead_memory, overhead_storage, ha,
                                           overcommit_cpu)

        result_text = (
            f"Uploaded VM configuration:\n"
            f"Total CPU: {requested_specs['total_cpu']:.2f} vCPU\n"
            f"Total Memory: {requested_specs['total_memory']:.2f} GiB\n"
            f"Total Storage: {requested_specs['total_storage']:.2f} GiB\n\n"
            f"Required Fusion Infrastructure configuration:\n"
            f"Total CPU Needed: {results['required_cpu']:.2f} vCPU\n"
            f"Total Memory Needed: {results['required_memory']:.2f} GiB\n"
            f"Total Storage Needed: {results['required_storage']:.2f} GiB\n"
        )

        self.result_text.setPlainText(result_text)

    def goToSelectionPage(self):
        self.stack.setCurrentIndex(0)


class availableInfrastructurePage(QWidget):
    def __init__(self, stack):
        super().__init__()
        self.stack = stack
        self.initUI()

    def initUI(self):
        self.mainLayout = QVBoxLayout()
        self.mainLayout.setContentsMargins(20, 20, 20, 20)
        self.mainLayout.setSpacing(15)

        self.scrollContent = QWidget()
        self.scrollContent.setLayout(self.mainLayout)

        self.headingLabel = QLabel("Estimate VM capacity on IBM Fusion HCI")
        self.headingLabel.setStyleSheet("font-weight: bold; font-size: 20px;")
        self.headingLabel.setAlignment(Qt.AlignCenter)

        self.mainLayout.addWidget(self.headingLabel)

        self.headingLabel1 = QLabel(
            "For determining how many VMs can be hosted on a predetermined IBM Fusion HCI system")
        self.headingLabel1.setStyleSheet("font-size: 14px; ")
        self.headingLabel1.setAlignment(Qt.AlignCenter)

        self.mainLayout.addWidget(self.headingLabel1)

        self.headingLabel2 = QLabel(
            "IBM Fusion HCI infrastructure details")
        self.headingLabel2.setStyleSheet("font-size: 16px; font-weight: bold;")
        self.mainLayout.addWidget(self.headingLabel2)

        self.hciDetailsLayout = QVBoxLayout()

        nodeHeaderLayout = QHBoxLayout()
        self.nodeCountLabel = QLabel("Number of worker/storage nodes:")
        self.nodeCountLabel.setStyleSheet("font-size: 15px;")
        self.nodeCountSpinBox = QSpinBox()
        self.nodeCountSpinBox.setValue(1)
        self.nodeCountSpinBox.setMinimum(1)
        self.nodeCountSpinBox.valueChanged.connect(self.updateNodeFields)

        nodeHeaderLayout.addWidget(self.nodeCountLabel)
        nodeHeaderLayout.addWidget(self.nodeCountSpinBox)
        nodeHeaderLayout.setSpacing(7)
        nodeHeaderLayout.addStretch()
        nodeHeaderLayout.setContentsMargins(0, 0, 0, 0)

        self.hciDetailsLayout.addLayout(nodeHeaderLayout)

        self.nodeFieldsContainer = QWidget()
        self.nodeFieldsLayout = QVBoxLayout(self.nodeFieldsContainer)
        self.hciDetailsLayout.addWidget(self.nodeFieldsContainer)

        overheadLayout1 = QGridLayout()
        cpuOverheadLabel1 = QLabel("Number of storage nodes:")
        self.cpuOverheadInput1 = QLineEdit()
        memoryOverheadLabel1 = QLabel("Number of disks per node:")
        self.memoryOverheadInput1 = QLineEdit()
        storageOverheadLabel1 = QLabel("Size of the disk per node:")
        self.storageOverheadInput1 = QLineEdit()
        overheadLayout1.addWidget(cpuOverheadLabel1, 0, 0)
        overheadLayout1.addWidget(self.cpuOverheadInput1, 0, 1)
        overheadLayout1.addWidget(memoryOverheadLabel1, 0, 2)
        overheadLayout1.addWidget(self.memoryOverheadInput1, 0, 3)
        overheadLayout1.addWidget(storageOverheadLabel1, 0, 4)
        overheadLayout1.addWidget(self.storageOverheadInput1, 0, 5)

        self.hciDetailsLayout.addLayout(overheadLayout1)

        clusterLayout1 = QHBoxLayout()
        storageLabel1 = QLabel("Overcommit ratio for CPU (cores):")
        storageLabel1.setStyleSheet("font-size: 14px;")
        storageLabel1.setFixedWidth(245)

        self.storageInput1 = QLineEdit()
        self.storageInput1.setFixedSize(140, 20)
        self.storageInput1.setStyleSheet("font-size: 12px;")

        clusterLayout1.addWidget(storageLabel1)
        clusterLayout1.addWidget(self.storageInput1)
        clusterLayout1.setAlignment(Qt.AlignLeft)

        self.hciDetailsLayout.addLayout(clusterLayout1)
        self.hciDetailsLayout.addSpacing(5)

        clusterLayout = QHBoxLayout()
        storageLabel = QLabel("Enter storage of entire cluster (GiB):")
        storageLabel.setStyleSheet("font-size: 14px;")
        storageLabel.setFixedWidth(245)

        self.storageInput = QLineEdit()
        self.storageInput.setFixedSize(140, 20)
        self.storageInput.setStyleSheet("font-size: 12px;")

        clusterLayout.addWidget(storageLabel)
        clusterLayout.addWidget(self.storageInput)
        clusterLayout.setAlignment(Qt.AlignLeft)

        self.hciDetailsLayout.addLayout(clusterLayout)
        self.hciDetailsLayout.addSpacing(5)


        overheadLayout = QGridLayout()
        cpuOverheadLabel = QLabel("CPU Overhead (cores):")
        self.cpuOverheadInput = QLineEdit()
        memoryOverheadLabel = QLabel("Memory Overhead (GiB):")
        self.memoryOverheadInput = QLineEdit()
        storageOverheadLabel = QLabel("Storage Overhead (GiB):")
        self.storageOverheadInput = QLineEdit()
        overheadLayout.addWidget(cpuOverheadLabel, 0, 0)
        overheadLayout.addWidget(self.cpuOverheadInput, 0, 1)
        overheadLayout.addWidget(memoryOverheadLabel, 0, 2)
        overheadLayout.addWidget(self.memoryOverheadInput, 0, 3)
        overheadLayout.addWidget(storageOverheadLabel, 0, 4)
        overheadLayout.addWidget(self.storageOverheadInput, 0, 5)

        self.hciDetailsLayout.addLayout(overheadLayout)
        #self.hciDetailsLayout.addSpacing(10)

        # Set the layout to the outer group box
        self.hciDetailsGroup = QGroupBox()
        self.hciDetailsGroup.setLayout(self.hciDetailsLayout)
        self.mainLayout.addWidget(self.hciDetailsGroup)

        #self.mainLayout.addSpacing(5)

        self.headingLabel3 = QLabel(
            "VM deployment configuration")
        self.headingLabel3.setStyleSheet("font-size: 16px; font-weight: bold;")

        self.vmConfigGroup = QGroupBox()
        vmConfigLayout = QVBoxLayout()
        self.vm_selection_label = QLabel("Select T-Shirt Size for VM:")
        self.vm_selection_combobox = QComboBox()
        self.vm_selection_combobox.addItems([
            'u1.micro (1 vCPU, 1 GiB)', 'cx1.medium (1 vCPU, 2 GiB)',
            'u1.small (1 vCPU, 2 GiB)',
            'u1.medium (1 vCPU, 4 GiB)', 'cx1.large (2 vCPU, 4 GiB)',
            'u1.large (2 vCPU, 8 GiB)',
            'cx1.xlarge (4 vCPU, 8 GiB)', 'n1.large (4 vCPU, 8 GiB)',
            'm1.large (2 vCPU, 16 GiB)',
            'gn1.xlarge (4 vCPU, 16 GiB)', 'u1.xlarge (4 vCPU, 16 GiB)',
            'cx1.2xlarge (8 vCPU, 16 GiB)',
            'n1.xlarge (8 vCPU, 16 GiB)', 'm1.xlarge (4 vCPU, 32 GiB)',
            'gn1w.2xlarge (8 vCPU, 32 GiB)'
        ])
        vmConfigLayout.addWidget(self.vm_selection_label)
        vmConfigLayout.addWidget(self.vm_selection_combobox)
        vmConfigLayout.addSpacing(10)

        self.stGroup = QGroupBox()
        self.stGroup.setStyleSheet("font-weight: bold;")
        stLayout = QGridLayout()
        customStorageLayout = QHBoxLayout()
        self.custom_storage_label = QLabel("Enter the storage per VM:")
        self.custom_storage_input = QSpinBox()

        self.custom_storage_input.setFixedWidth(100)

        self.custom_storage_input.setRange(1, 100000)
        self.custom_storage_input.setValue(30)

        customStorageLayout.addWidget(self.custom_storage_label)
        customStorageLayout.addSpacing(10)
        customStorageLayout.addWidget(self.custom_storage_input)
        customStorageLayout.addStretch()

        vmConfigLayout.addLayout(customStorageLayout)
        self.vmConfigGroup.setLayout(vmConfigLayout)

        self.buttonLayout = QHBoxLayout()
        self.calculateButton = QPushButton("Calculate")
        self.calculateButton.setStyleSheet(
            "font-size: 14px; padding: 10px; font-weight: bold; background-color: #525CEB;")
        self.calculateButton.clicked.connect(self.calculate_ocv_size)

        self.backButton = QPushButton("Start over")
        self.backButton.setStyleSheet("font-size: 14px; padding: 10px; font-weight: bold; background-color: #0F0F0F;")
        self.backButton.clicked.connect(self.goToSelectionPage)

        self.buttonLayout.addWidget(self.calculateButton)
        self.buttonLayout.addSpacing(15)
        self.buttonLayout.addWidget(self.backButton)

        self.outputLabel = QLabel("Output:")
        self.outputLabel.setStyleSheet("font-size: 14px; font-weight: bold; margin-top: 20px;")

        self.outputArea = QTextEdit()
        self.outputArea.setReadOnly(True)
        self.outputArea.setStyleSheet("border: 1px solid #ddd; padding: 10px;")

        self.mainLayout.addSpacing(5)
        self.mainLayout.addWidget(self.headingLabel3)
        self.mainLayout.addWidget(self.vmConfigGroup)
        self.mainLayout.addLayout(self.buttonLayout)
        self.mainLayout.addWidget(self.outputLabel)
        self.mainLayout.addWidget(self.outputArea)

        self.scrollArea = QScrollArea()
        self.scrollArea.setWidget(self.scrollContent)
        self.scrollArea.setWidgetResizable(True)

        self.setLayout(self.mainLayout)
        self.resize(900, 900)

        self.updateNodeFields()

    def updateNodeFields(self):
        for i in reversed(range(self.nodeFieldsLayout.count())):
            layout_item = self.nodeFieldsLayout.itemAt(i)
            if layout_item:
                widget = layout_item.widget()
                if widget:
                    widget.deleteLater()
                else:
                    layout_item.layout().deleteLater()

        num_nodes = self.nodeCountSpinBox.value()
        for i in range(1, num_nodes + 1):
            nodeLayout = QHBoxLayout()
            nodeCpuLabel = QLabel(f"Node {i} CPU (CPU cores)")
            nodeCpuInput = QLineEdit()
            nodeMemLabel = QLabel(" Memory (GiB)")
            nodeMemInput = QLineEdit()
            nodeLayout.addWidget(nodeCpuLabel)
            nodeLayout.addWidget(nodeCpuInput)
            nodeLayout.addWidget(nodeMemLabel)
            nodeLayout.addWidget(nodeMemInput)
            self.nodeFieldsLayout.addLayout(nodeLayout)

    def calculate_ocv_size(self):
        """
        This method will calculate the OCV sizing
        """
        try:
            node_count = self.nodeCountSpinBox.value()
            storage = int(self.storageInput.text() or 0)
            cpu_overhead = int(self.cpuOverheadInput.text() or 0)
            memory_overhead = int(self.memoryOverheadInput.text() or 0)
            storage_overhead = int(self.storageOverheadInput.text() or 0)
            overcommit_ratio = int(self.storageInput1.text() or 0)
            num_drives = int(self.memoryOverheadInput1.text() or 0)
            total_cpu = 0
            total_memory = 0

            selected_template = self.vm_selection_combobox.currentText().split('(')[1].split(')')[0]

            vm_cpu, vm_mem = map(int, [part.split(' ')[0] for part in selected_template.split(', ')])
            vms = [(vm_cpu, vm_mem, 1)]
            custom_st = self.custom_storage_input.value()

            for i in range(self.nodeFieldsLayout.count()):
                layout_item = self.nodeFieldsLayout.itemAt(i)
                if layout_item:
                    layout = layout_item.layout()
                    if layout:
                        cpu_widget = layout.itemAt(1).widget()
                        mem_widget = layout.itemAt(3).widget()
                        if cpu_widget and mem_widget:
                            try:
                                cpu_value = int(cpu_widget.text())
                                memory_value = int(mem_widget.text())
                                total_cpu += cpu_value
                                total_memory += memory_value
                            except ValueError:
                                pass

            result = calculate_vm_sizing(total_cpu, total_memory, storage, cpu_overhead, memory_overhead,
                                         storage_overhead, overcommit_ratio, vms, custom_st, num_drives)
            self.outputArea.setText(result)
        except Exception as e:
            self.outputArea.setText(f"Error: {str(e)}")

    def goToSelectionPage(self):
        self.stack.setCurrentIndex(0)


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.initUI()

    def initUI(self):
        self.setWindowTitle("OpenShift Virtualization Sizing Tool")

        self.stack = QStackedWidget()

        self.infraSelectionPage = InfrastructureSelectionPage(self.stack)
        self.customInfraPage = CustomInfrastructurePage(self.stack)
        self.uploadInfraPage = UploadInfrastructurePage(self.stack)
        self.availableInfraPage = availableInfrastructurePage(self.stack)

        self.stack.addWidget(self.infraSelectionPage)
        self.stack.addWidget(self.customInfraPage)
        self.stack.addWidget(self.uploadInfraPage)
        self.stack.addWidget(self.availableInfraPage)

        self.setCentralWidget(self.stack)
        self.resize(400, 400)


if __name__ == '__main__':
    app = QApplication(sys.argv)
    mainWin = MainWindow()
    mainWin.show()
    sys.exit(app.exec_())
