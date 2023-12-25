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