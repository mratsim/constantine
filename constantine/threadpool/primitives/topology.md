# CPU Topology

For multithreading, we want to expose the following functions:

1. Number of total physical cores `getNumCoresPhysical`:
    - without counting simultaneous multithreading (SMT / HyperThreading)
    siblings (x2 for Intel/AMD, x4 for Xeon Phi)
    - dealing with mixed HT / non-HT cores for hybrid architecture (Performance/Efficiency) like Alder Lake or Raptor Lake.
      Note: Technically ARM Big.Little arch and Apple ARM also have hybrid arch but they don't support SMT
    - dealing with NUMA arch
2. Number of total logical cores `getNumCoresLogical`:
    - while properly counting mixed HT / non-HT cores for hybrid processors
3. Number of OS available cores `getNumCoresAvailableForOS`:
    - some cores may be disabled at the OS-level, for example in a VM.
      in Linux, this is provided by sysconf(_SC_NPROCESSORS_ONLN)
      Note: This wouldn't detect restriction based on time quotas which are more common for Docker.
4. Number of cores available for this process `getNumCoresAvailableForCurrentProcess`:
    - A process can be restricted by taskset / schedaffinity
      Note: This wouldn't detect restriction based on time quotas which are more common for Docker.

References:
- x86
    - AMD
        - https://patchwork.kernel.org/project/kvm/patch/1523402169-113351-8-git-send-email-babu.moger@amd.com/
        - AMD64 Architecture Programmer's Manual Volume 3: General-Purpose and System Instructions
        June 2023
        https://www.amd.com/content/dam/amd/en/documents/processor-tech-docs/programmer-references/24594.pdf
        p645, section E.5 Multiple Procesor Calculation
- OS
    - https://github.com/llvm/llvm-project/blob/main/llvm/lib/Support/Unix/Threading.inc
    - https://github.com/llvm/llvm-project/blob/main/llvm/lib/Support/Windows/Threading.inc