def calculate_cpu_reserved_for_ocp(cpu_cores):
    """
        Calculates the CPU overhead reserved for OpenShift based on the
        total CPU cores.

        OpenShift reserves CPU resources on a tiered basis:
            - First core: 6%
            - Second core: 1%
            - Next 2 cores: 0.5% each
            - Remaining cores: 0.25% each

        Args:
            cpu_cores (int or float): Total number of physical CPU
            cores available.

        Returns:
            float: Total CPU cores reserved for OpenShift
            (rounded to 4 decimal places).
    """
    overhead = 0.0
    remaining = cpu_cores

    if remaining >= 1:
        overhead += 1 * 0.06
        remaining -= 1
    if remaining >= 1:
        overhead += 1 * 0.01
        remaining -= 1
    tier = min(remaining, 2)
    overhead += tier * 0.005
    remaining -= tier
    if remaining > 0:
        overhead += remaining * 0.0025

    return round(overhead, 4)


def calculate_memory_reserved_for_ocp(memory_gib):
    """
        Calculates the memory overhead reserved for OpenShift based
        on total memory (in GiB).

        OpenShift reserves memory on a tiered basis:
            - First 4 GiB: 25%
            - Next 4 GiB: 20%
            - Next 8 GiB: 10%
            - Next 112 GiB: 6%
            - Any memory above 128 GiB: 2%

        Args:
            memory_gib (int or float): Total available memory in GiB.

        Returns:
            float: Total memory reserved for OpenShift
            (rounded to 2 decimal places).
    """
    overhead = 0.0
    remaining = memory_gib

    tier1 = min(remaining, 4)
    overhead += tier1 * 0.25
    remaining -= tier1

    tier2 = min(remaining, 4)
    overhead += tier2 * 0.20
    remaining -= tier2

    tier3 = min(remaining, 8)
    overhead += tier3 * 0.10
    remaining -= tier3

    tier4 = min(remaining, 112)
    overhead += tier4 * 0.06
    remaining -= tier4

    if remaining > 0:
        overhead += remaining * 0.02

    return round(overhead, 2)


def fusion_base_system_and_fdf_consumption(num_drives):
    """
    Calculates base system BnR and FDF service overhead for CPU and Memory.

    Returns:
        tuple: (node_cpu_overhead, node_memory_overhead)
    """
    # Base system reservation including base overhead and BnR service
    base_cpu_overhead = 2 + 5
    base_mem_overhead = 7 + 17

    # FDF service overhead
    drive_cpu_overhead = 13 + (num_drives * 2)
    drive_mem_overhead = 26 + (num_drives * 5)

    node_cpu_overhead = base_cpu_overhead + drive_cpu_overhead
    node_memory_overhead = base_mem_overhead + drive_mem_overhead

    return node_cpu_overhead, node_memory_overhead


def calculate_vm_sizing(total_cpu, total_memory, storage, cpu_overhead,
                        memory_overhead, storage_overhead, overcommit_ratio,
                        vms,
                        custom_st, num_drives):
    """
        Calculates the maximum number of virtual machines (VMs) that can be
        scheduled on a system after accounting for OpenShift reservations,
        Fusion system overheads and overcommit ratios.

        Args:
            total_cpu (int): Total physical CPU cores available.
            total_memory (int): Total memory (in GiB) available.
            storage (int): Total storage (in GiB) available.
            cpu_overhead (int): Additional CPU overhead reserved per node.
            memory_overhead (int): Additional memory overhead reserved per
            node.
            storage_overhead (int): Reserved storage for system overhead.
            overcommit_ratio (float): CPU overcommit ratio
            vms (list of tuple): List containing VM specs in the format
            (vCPU, memory, storage).
            custom_st (int): Custom storage (in GiB) required per VM.
            num_drives (int): Number of drives in the system
            (used for FDF overhead calculation).

        Returns:
            str: Formatted string displaying available resources and max
            number of schedulable VMs, or a message indicating
            insufficient resources.
        """

    # OpenShift reservation for CPU and memory
    openshift_cpu_reservation = calculate_cpu_reserved_for_ocp(total_cpu)
    openshift_memory_reservation = calculate_memory_reserved_for_ocp(
        total_memory)

    # fusion overhead including base rack consumption, FDF and BnR services
    node_cpu_overhead, node_memory_overhead = (
        fusion_base_system_and_fdf_consumption(num_drives))

    # Total CPU and Memory overheads
    total_cpu_overhead = (
            (openshift_cpu_reservation + cpu_overhead) * 2 + node_cpu_overhead)
    total_memory_overhead = (
            openshift_memory_reservation + node_memory_overhead + memory_overhead)

    total_vcpu = total_cpu * 2

    # Resources after all overheads
    available_cpus = total_vcpu - total_cpu_overhead
    available_cpu = available_cpus * overcommit_ratio
    available_memory = total_memory - total_memory_overhead
    total_storage = storage - storage_overhead

    vm_cpu, vm_mem, _ = vms[0]
    total_vm_cpu = vm_cpu
    total_vm_mem = vm_mem
    total_vm_storage = custom_st

    if (total_vm_cpu <= available_cpu and total_vm_mem <= available_memory
            and total_vm_storage <= total_storage):
        max_vms_cpu = available_cpu // total_vm_cpu
        max_vms_mem = available_memory // total_vm_mem
        max_vms_storage = total_storage // total_vm_storage
        max_vms = min(max_vms_cpu, max_vms_mem, max_vms_storage)
        max_vms1 = int(max_vms)

        return (
            f"Total Available Resources (Excluding Overhead):\n CPU cores "
            f"[{total_cpu}]  Memory [{total_memory}]  "
            f"Storage [{storage}]\n\n"
            f"Selected T-Shirt Size: {vm_cpu} vCPU, {vm_mem} GiB, \n\n"
            f"Maximum VMs that can be Scheduled: {max_vms1}")
    else:
        additional_cpu = max(0, total_vm_cpu - total_cpu)
        additional_mem = max(0, total_vm_mem - total_memory)
        additional_storage = max(0, total_vm_storage - total_storage)
        return (f"Insufficient resources.\n"
                f"Additional CPU required: {additional_cpu}, "
                f"Additional Memory required: {additional_mem}, "
                f"Additional Storage required: {additional_storage}")


def perform_calculation(node_count, cpu_overhead, memory_overhead,
                        storage_overhead,
                        total_storage_capacity, ha_reserve_percent,
                        overcommit_ratio,
                        node_details, vm_inputs, num_drives):
    """
        Performs infrastructure capacity calculation to determine
        whether the available hardware resources are sufficient to
        host the desired number of VMs.

        Args:
            node_count (int): Total number of physical nodes in the cluster.
            cpu_overhead (int): Additional CPU reserved per node.
            memory_overhead (int): Additional memory reserved per node.
            storage_overhead (int): Storage reserved for system use.
            total_storage_capacity (int): Total usable storage across
            all nodes (GiB).
            ha_reserve_percent (float): HA reservation percentage.
            overcommit_ratio (float): CPU overcommit ratio
            node_details (list of dict): List containing per-node specs
            with 'cpu' and 'memory'.
            vm_inputs (dict): Dictionary where each key is a VM type,
            and value is a dict with:
                              - 'num_vms': Number of VMs
                              - 'cpu': vCPU per VM
                              - 'memory': Memory per VM (GiB)
                              - 'storage': Storage per VM (GiB)
            num_drives (int): Number of drives used in the system
            (affects Fusion overheads).

        Returns:
            str: Human-readable result summary showing available
            and required resources, and whether the infrastructure is
            sufficient.
        """
    try:
        total_cpu = 0
        total_memory = 0

        # Step 1: Sum total CPU and Memory from node details
        for node in node_details:
            total_cpu += node['cpu']
            total_memory += node['memory']

        # Step 2: Calculate OpenShift reservation overheads
        ocp_cpu_overhead = calculate_cpu_reserved_for_ocp(total_cpu)
        ocp_memory_overhead = calculate_memory_reserved_for_ocp(total_memory)

        # Step 3: Calculate Fusion base + FDF overheads
        fusion_cpu_overhead, fusion_memory_overhead = (
            fusion_base_system_and_fdf_consumption(num_drives))

        # Step 4: Combine all CPU and Memory overheads
        total_cpu_overhead = (
                (cpu_overhead + ocp_cpu_overhead) * 2 + fusion_cpu_overhead)
        total_memory_overhead = (
                memory_overhead + ocp_memory_overhead + fusion_memory_overhead)

        total_vcpus = total_cpu * 2

        # Step 5: Compute available resources (adjusted for HA reservation)
        available_vcpus = (total_vcpus - total_cpu_overhead) * (
                1 - ha_reserve_percent) * overcommit_ratio
        available_memory = (total_memory - total_memory_overhead) * (
                1 - ha_reserve_percent)
        available_storage = total_storage_capacity - storage_overhead

        # Step 6: Sum required resources from VMs
        required_vcpus = 0
        required_memory = 0
        required_storage = 0

        for vm_type, vm_info in vm_inputs.items():
            num_vms = vm_info['num_vms']
            cpu_value = vm_info['cpu']
            memory_value = vm_info['memory']
            storage_value = vm_info['storage']

            required_vcpus += num_vms * cpu_value
            required_memory += num_vms * memory_value
            required_storage += num_vms * storage_value

        # Step 7: Compare available vs required
        if (available_vcpus >= required_vcpus) and (
                available_memory >= required_memory) and (
                available_storage >= required_storage):
            result_text = (
                f"Available Infrastructure:\n"
                f"Total Available vCPU: {available_vcpus:.2f}\n"
                f"Total Available Memory (GiB): {available_memory:.2f}\n"
                f"Total Available Storage (GiB): {available_storage:.2f}\n\n"
                f"Required Infrastructure:\n"
                f"Total Required vCPU: {required_vcpus}\n"
                f"Total Required Memory (GiB): {required_memory}\n"
                f"Total Required Storage (GiB): {required_storage}\n"
                f"\nSufficient infrastructure to create VMs."
            )
        else:
            result_text = (
                f"Available infrastructure is not sufficient to create VMs."
                f"\n\n"
                f"Available Resources:\n"
                f"  vCPU: {available_vcpus:.2f}\n"
                f"  Memory: {available_memory:.2f} GiB\n"
                f"  Storage: {available_storage:.2f} GiB\n\n"
                f"Required Resources:\n"
                f"  vCPU: {required_vcpus}\n"
                f"  Memory: {required_memory} GiB\n"
                f"  Storage: {required_storage} GiB\n"
            )

        return result_text

    except Exception as e:
        return f"Error: {str(e)}"


def calculate_infrastructure(requested_specs, overhead_cpu, overhead_memory,
                             overhead_storage, ha, overcommit_cpu,
                             num_drives=2):
    """
    Perform calculations based on the requested specs and configuration
    details. Includes OCP reservation and FDF overheads.

    :param requested_specs: Dictionary containing total CPU, memory,
    and storage.
    :param overhead_cpu: Custom CPU overhead value.
    :param overhead_memory: Custom Memory overhead value.
    :param overhead_storage: Custom Storage overhead value.
    :param ha: High Availability percentage.
    :param overcommit_cpu: Overcommit ratio for CPU.
    :param num_drives: Number of drives for FDF overhead calculation.
    :return: A dictionary with results for required CPU, memory,
    and storage.
    """

    total_cpu = requested_specs.get('total_cpu', 0)
    total_memory = requested_specs.get('total_memory', 0)
    total_storage = requested_specs.get('total_storage', 0)

    # OCP reservation
    ocp_cpu_overhead = calculate_cpu_reserved_for_ocp(total_cpu)
    ocp_memory_overhead = calculate_memory_reserved_for_ocp(total_memory)

    # base cluster + BnR + FDF overhead
    fusion_cpu_overhead, fusion_memory_overhead = (
        fusion_base_system_and_fdf_consumption(
            num_drives))
    fusion_cpu_cores_overhead = fusion_cpu_overhead / 2

    # Combine all overheads
    total_cpu_overhead = (
            overhead_cpu + ocp_cpu_overhead + fusion_cpu_cores_overhead)
    total_memory_overhead = (
            overhead_memory + ocp_memory_overhead + fusion_memory_overhead)

    # Apply HA and Overcommit
    required_cpu = (total_cpu + total_cpu_overhead) * (1 + ha) * overcommit_cpu
    required_memory = (total_memory + total_memory_overhead) * (1 + ha)
    required_storage = total_storage + overhead_storage

    return {
        'total_cpu': total_cpu,
        'total_memory': total_memory,
        'total_storage': total_storage,
        'required_cpu': round(required_cpu, 2),
        'required_memory': round(required_memory, 2),
        'required_storage': round(required_storage, 2)
    }
