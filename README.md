# Barracuda - A Microdriver Architecture for Error Correcting Codes inside the Linux Kernel

Linux is often used in conjunction with parallel file systems in high
performance cluster environments and the tremendous storage growth in these
environments leads to the requirement of multi-error correcting codes. This work
investigates the potential of GPUs for such coding applications in the Linux
kernel. For this purpose, a special micro driver concept (Barracuda) has been
designed that can be integrated into Linux without changing kernel APIs. For the
investigation of the performance of this concept, the Linux RAID 6-system and
the applied Reed-Solomon code have been exemplary extendedand. The resulting
measurements outline opportunities and limitations of our microdriver concept.
On the one hand, the concept achieves a speed-up of 72 for complex, 8-failure
correcting codes, while no additional speed-up can be generated for simpler,
2-error correcting codes. An example application for Barracuda could therefore
be the replacement of expensive RAID systems in cluster storage environments.
