---
title: Reed-Solomon Erasure Code Recovery with FFTs (Reply #12)
source: https://ethresear.ch/t/reed-solomon-erasure-code-recovery-in-n-log-2-n-time-with-ffts/3039/12
author: Qi Zhou
date: 2022-10-24
---

It seems that we could further optimize the recovery based on Danksharding encoding - especially based on reverse bit order and samples in a coset size 16. The main conclusion is that we could reduce the problem size from 8192 to 16 sub-problems of size 512 (=8192/16) and thus the cost of Z(x) and Q2(x) can be amortized over 16 sub-problems.

Consider the following danksharding encoding: the data are encoded in a polynomial with degree 4095 and are evaluated at the roots of unity of order n = 8192. The roots of unity are ordered by reverse bit order, i.e., \{ \omega_0, \omega_1, ..., \omega_{8191} \} = \{ 1, \omega^{4096}, \omega^{2048}, \omega^{6072}, …, \omega^{8191} \}. Therefore, we define \Omega = \{ \omega_0, \omega_1, … , \omega_{15} \} is a subgroup of order 16, and for each sample 0\leq i < m, we have a shifting factor h_i = \omega_{16i} so that the coset H_i = h_i \Omega.

For each sample \{ d^{(i)}_j \}, i = \{0, 1, ..., 255\}, where i is the index of the sample, we have the equations:

\begin{bmatrix} \omega^0_{16i+0} & \omega_{16i+0}^1 & ... & \omega^{4095}_{16i+0} \\ \omega_{16i+1}^0 & \omega_{16i+1}^1 & ... & \omega_{16i+1}^{4095} \\ ... \\ \omega_{{16i+15}}^0 & \omega_{16i+15}^1 & ... & \omega_{16i+15}^{4095} \end{bmatrix}_{16 \times 4096}\begin{bmatrix} a_0 \\ a_1 \\ ... \\ a_{4095} \end{bmatrix} = \begin{bmatrix} d^{(i)}_0 \\ d^{(i)}_1 \\ ... \\ d^{(i)}_{15} \end{bmatrix}

Given h_i \omega_j = \omega_{16i+j}, \forall 0 \leq j \leq 15 , we have

\begin{bmatrix} h_i^0 \omega^0_{0} & h_i^1 \omega_{0}^1 & ... & h_i^{4095} \omega^{4095}_{0} \\ h_i^0 \omega_{1}^0 & h_i^1 \omega_{1}^1 & ... & h_i^{4095} \omega_{1}^{4095} \\ ... \\ h_i^0 \omega_{{15}}^0 & h_i^1 \omega_{15}^1 & ... & h_i^{4095} \omega_{15}^{4095} \end{bmatrix}_{16 \times 4096}\begin{bmatrix} a_0 \\ a_1 \\ ... \\ a_{4095} \end{bmatrix} = \begin{bmatrix} d^{(i)}_0 \\ d^{(i)}_1 \\ ... \\ d^{(i)}_{15} \end{bmatrix}

\begin{bmatrix} \omega^0_{0} & \omega_{0}^1 & ... & \omega^{4095}_{0} \\ \omega_{1}^0 &\omega_{1}^1 & ... & \omega_{1}^{4095} \\ ... \\ \omega_{{15}}^0 & \omega_{15}^1 & ... & \omega_{15}^{4095} \end{bmatrix}_{16 \times 4096}\begin{bmatrix} h_i^0 a_0 \\ h_i^1 a_1 \\ ... \\ h_i^{4095} a_{4095} \end{bmatrix} = \begin{bmatrix} d^{(i)}_0 \\ d^{(i)}_1 \\ ... \\ d^{(i)}_{15} \end{bmatrix}

Note that \omega_i^{16 + j} = \omega_i^{j}, \forall 0 \leq i\leq15, then we have

\begin{bmatrix} \mathcal{F}_{16\times 16} & \mathcal{F}_{16\times 16} & ... & \mathcal{F}_{16\times 16} \end{bmatrix}_{16 \times 4096}\begin{bmatrix} h_i^0 a_0 \\ h_i^1 a_1 \\ ... \\ h_i^{4095} a_{4095} \end{bmatrix} = \begin{bmatrix} d^{(i)}_0 \\ d^{(i)}_1 \\ ... \\ d^{(i)}_{15} \end{bmatrix}

where \mathcal{F}_{16\times 16} is the Fourier matrix (with proper reverse bit order).

Combining the matrices, we finally reach at

\mathcal{F}^{-1}_{16 \times 16} \begin{bmatrix} d^{(i)}_{0} \\ d^{(i)}_{1} \\ ... \\ d^{(i)}_{15} \end{bmatrix} =\begin{bmatrix} h^0_i\sum_{j=0}^{255} h^{16j}_ia_{16j} \\ h^1_i\sum_{j=0}^{255} h^{16j}_ia_{16j+1}\\ ... \\ h^{15}_i\sum_{j=0}^{255} h^{16j}_i a_{16j+15} \end{bmatrix} = \begin{bmatrix} h^0_{i} y^{(i)}_0 \\ h^1_{i} y^{(i)}_1 \\ ... \\ h^{15}_{i} y^{(i)}_{15}\end{bmatrix}

This means that we can recover all missing samples by:

- Perform IFFT to all received samples (256 IFFTs of size 16x16)
- Recover y^{(i)}_j of missing samples by using Vitalik’s algorithm that solves 16 sub-problems of size 512. Note that Z(x) and Q2(x) (if k is the same) can be reused in solving each sub-problem.
- Recover the missing samples of index i by FFTing \{ h_i^j y^{(i)}_j \}, \forall 0 \leq j \leq 15.

The example code of the algorithm can be found Optimized Reed-Solomon code recovery based on danksharding by qizhou · Pull Request #132 · ethereum/research · GitHub

Some performance numbers on my MacBook (recovery of size 8192):

- Original: 1.07s
- Optimized zpoly: 0.500s
- Optimized RS: 0.4019s
