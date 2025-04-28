def calculate_vm_sizing(total_cpu, total_memory, storage, cpu_overhead, memory_overhead, storage_overhead, vms,
                        custom_st):

    available_cpu = total_cpu - cpu_overhead
    available_memory = total_memory - memory_overhead
    total_storage = storage - storage_overhead

    vm_cpu, vm_mem, _ = vms[0]
    total_vm_cpu = vm_cpu
    total_vm_mem = vm_mem
    total_vm_storage = custom_st

    if total_vm_cpu <= available_cpu and total_vm_mem <= available_memory and  total_vm_storage <= total_storage:
        max_vms_cpu = total_cpu // total_vm_cpu
        max_vms_mem = total_memory // total_vm_mem
        max_vms_storage = total_storage // total_vm_storage
        max_vms = min(max_vms_cpu, max_vms_mem, max_vms_storage)

        return (
                f"Total Available Resources (Excluding Overhead):\n vCPU [{total_cpu}]  Memory [{total_memory}]  "
                f"Storage [{storage}]\n\n"
                f"Selected T-Shirt Size: {vm_cpu} vCPU, {vm_mem} GiB, \n\n"
                f"Maximum VMs that can be Scheduled: {max_vms}")
    else:
        additional_cpu = max(0, total_vm_cpu - total_cpu)
        additional_mem = max(0, total_vm_mem - total_memory)
        #additional_pod = max(0, total_vm_pod - total_pod)
        additional_storage = max(0, total_vm_storage - total_storage)
        return (f"Insufficient resources.\n"
                f"Additional CPU required: {additional_cpu}, Additional Memory required: {additional_mem}, "
                f"Additional Storage required: {additional_storage}")


def perform_calculation(node_count, cpu_overhead, memory_overhead, storage_overhead, total_storage_capacity, ha_reserve_percent, overcommit_ratio, node_details, vm_inputs):
    try:
        total_cpu = 0
        total_memory = 0

        for node in node_details:
            total_cpu += node['cpu']
            total_memory += node['memory']

        available_vcpus = (total_cpu - cpu_overhead) * (1 - ha_reserve_percent) * overcommit_ratio
        available_memory = (total_memory - memory_overhead) * (1 - ha_reserve_percent)
        available_storage = total_storage_capacity - storage_overhead

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

        if (available_vcpus >= required_vcpus) and (available_memory >= required_memory) and (available_storage >= required_storage):
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
                "\nAvailable infrastructure is not sufficient to create VMs.\n\n"
                f"Total Available vCPU: {available_vcpus:.2f}\n"
                f"Total Available Memory (GiB): {available_memory:.2f}\n"
                f"Total Available Storage (GiB): {available_storage:.2f}\n"
                f"Total Required vCPU: {required_vcpus}\n"
                f"Total Required Memory (GiB): {required_memory}\n"
                f"Total Required Storage (GiB): {required_storage}\n"
            )

        return result_text

    except Exception as e:
        return f"Error: {str(e)}"


def calculate_infrastructure(requested_specs, overhead_cpu, overhead_memory, overhead_storage, ha, overcommit_cpu):
    """
    Perform calculations based on the requested specs and configuration details.

    :param requested_specs: Dictionary containing total CPU, memory, and storage.
    :param overhead_cpu: CPU overhead value.
    :param overhead_memory: Memory overhead value.
    :param overhead_storage: Storage overhead value.
    :param ha: High Availability percentage (0 to 1).
    :param overcommit_cpu: Overcommit ratio for vCPU.
    :return: A dictionary with results for required CPU, memory, and storage.
    """
    total_cpu = requested_specs.get('total_cpu', 0)
    total_memory = requested_specs.get('total_memory', 0)
    total_storage = requested_specs.get('total_storage', 0)

    required_cpu = (total_cpu + overhead_cpu) * (1 + ha) * overcommit_cpu
    required_memory = (total_memory + overhead_memory) * (1 + ha)
    required_storage = total_storage + overhead_storage

    return {
        'total_cpu': total_cpu,
        'total_memory': total_memory,
        'total_storage': total_storage,
        'required_cpu': required_cpu,
        'required_memory': required_memory,
        'required_storage': required_storage
    }
