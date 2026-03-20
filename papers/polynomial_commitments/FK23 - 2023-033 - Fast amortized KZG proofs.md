---
title: Fast Amortized KZG Proofs
source: https://eprint.iacr.org/2023/033.pdf
author: Dankrad Feist, Dmitry Khovratovich
date: 2023-01-11
updated: 2025-05-18
---

# Fast amortized KZG proofs

Dankrad Feist $ ^{*1} $ and Dmitry Khovratovich $ ^{\dagger2} $

 $ ^{1,2} $Ethereum Foundation

May 15, 2025

## Abstract

In this note we explain how to compute n KZG proofs for a polynomial of degree d in time superlinear of  $ (n+d) $. Our technique is used in lookup arguments and vector commitment schemes.

## 1 Preliminaries

### 1.1 Setup

Let F be a field and let G be a group with a designated element g, called a generator. We denote  $ [a] = a \cdot g $ for integer a.

### 1.2 KZG Commitment Scheme

Setup. In a KZG commitment scheme [KZG10] for polynomials of degree up to d a Verifier or a trusted third party first selects a secret s and then constructs d elements of G:

 $$ [s],[s^{2}],\dots,[s^{m}]. $$ 

Commitment. Let  $ f(X) = \sum_{0 \leq i \leq d} f_i X^i \in \mathbb{F}[X] $ be a polynomial of degree  $ d $. Then a commitment  $ C_f \in \mathbb{G} $ is defined as

 $$ C_{f}=\sum_{0\leq i\leq d}f_{i}[s^{i}], $$ 

being effectively the evaluation of f at point s multiplied by g.

Single-point proof. Note that for any y we have that  $ (X-y) $ divides  $ f(X)-f(y) $. Then the proof that  $ f(y)=z $ is defined as

 $$ \pi[f(y)=z]=C_{T_{y}}, $$ 

where  $ T_{y}(X) = \frac{f(X) - z}{X - y} $ is a polynomial of degree  $ (d - 1) $. To verify the proof  $ \pi $ we check the equation

 $$ e(\pi,[s-y]_{2})=e(C_{f}-[z]_{1},[1]_{2}) $$ 

Note that a proof can be constructed using d scalar multiplications in the group. The coefficients of T are computed with one multiplication each:

 $$ T_{y}(X)=\sum_{0\leq i\leq d-1}t_{i}X^{i}; $$ 

 $$ t_{d-1}=f_{d}; $$ 

 $$ t_{j}=f_{j+1}+y\cdot t_{j+1}. $$ 

Expanding on the last equation, we get

 $$ \begin{align*}T_{y}(X)=f_{d}X^{d-1}+(f_{d-1}+yf_{d})X^{d-2}+(f_{d-2}+yf_{d-1}+y^{2}f_{d})X^{d-3}+\\+(f_{d-3}+yf_{d-2}+y^{2}f_{d-1}+y^{3})X^{d-4}+\cdots+(f_{1}+yf_{2}+y^{2}f_{3}+\cdots+y^{d-1}f_{d}).\end{align*} $$ 

Multi-point proof. Let  $ I = \{y_1, y_2, \ldots, y_l\} $ be a set of elements of  $ \mathbb{F} $. Let  $ Z_I(X) $ be its vanishing polynomial i.e.  $ Z_I = \prod_{y \in I}(X - y) $. We write

 $$ f(X)=T_{I}(X)Z_{I}(X)+R_{I}(X) $$ 

where  $ T_I $ has degree  $ (d - l) $ and  $ R_I $ has degree  $ l - 1 $. We see that  $ f $ and  $ R_I $ take the same values on  $ I $. Then the proof that  $ f(y_i) = z_i $ for all  $ i $ is defined as

 $$ \pi[\{f(y)=z\}_{y\in I}]=C_{T_{I}}, $$ 

To verify the proof  $ \pi $ we check the equation

 $$ e(\pi,[Z_{I}]_{2})=e(C_{f}-C_{R_{I}},[1]_{2}) $$ 

Let us consider the special case where  $ Z_I(X) $ has special form  $ X^l - \theta $ i.e. where  $ I $ is the set of  $ l $-roots of  $ \theta $. Then the coefficients of the quotient polynomial  $ T_I(X) $ can be computed by a compact formula of  $ \theta $ and the coefficients of  $ f(X) $. This is done as follows:

 $$ \begin{array}{r l}{T_{I}(X)=}&{{}\displaystyle\sum t_{k}X^{k};}\end{array} $$ 

 $$ 0\leq k\leq d-l $$ 

 $$ t_{d-l}=f_{d}; $$ 

\[\displaystyle\qquad\

 $$ t_{d-2l+1}=f_{d-l+1} $$ 

 $$ t_{k}=f_{k+l}+\theta\cdot t_{k+l},\quad0\leq k\leq d-2l. $$ 

Expanding on the last equation, we get

 $$ \begin{align*}T_{I}(X)=f_{d}X^{d-l}+f_{d-1}X^{d-l+1}+\cdots+f_{d-l+1}X^{d-2l+1}+\ $ f_{d-l}+\theta f_{d})X^{d-2l}+(f_{d-l-1}+\theta f_{d-1})X^{d-2l-1}+\cdots+(f_{d-2l+1}+\theta f_{d-l+1})X^{d-3l+1}+\ $ f_{d-2l}+\theta f_{d-l}+\theta^{2}f_{d})X^{d-3l}+(f_{d-2l-1}+\theta f_{d-l-1}+\theta^{2}f_{d-1})X^{d-3l-1}+\cdots+\ $ f_{d-3l+1}+\theta f_{d-2l+1}+\theta^{2}f_{d-l+1})X^{d-4l+1}+\cdots+(f_{l}+\theta f_{2l}+\theta^{2}f_{3l}+\cdots+\theta^{r-2}f_{(r-1)l})\cdot1.\end{align*} $$ 

### 1.3 Discrete Fourier Transform

Let n be a positive integer. Then ω ∈ ℝ is called n-th root of unity if ωn = 1 and ωi ≠ 1 for i < n.

Dicrete Fourier Transform for vectors in  $ F^{n} $ is defined as

 $$ \mathrm{DFT}_{n}(a_{0},a_{1},\cdots,a_{n-1})=(b_{0},b_{1},\cdots,b_{n-1}) $$ 

where

 $$ b_{i}=\sum_{0\leq j\leq n-1}a_{j}\omega^{i j}. $$ 

It is easy to see that $b_{i}$ are essentially evaluations of polynomial $a(X)=\sum_{j}a_{j}X^{j}$ in points $\omega^{0},\omega^{1},\ldots,\omega^{n-1}$. As a polynomial of degree $n-1$ is defined by its values in $n$ points, DFT is invertible. We denote its inverse by $\mathrm{iDFT}_{n}$.

In a vast majority of finite fields with characteristic bigger than n, the DFT can be computed in  $ O(n \log n) $ time with an algorithm called FFT (Fast Fourier Transform) [CT65]. An overview of such methods can be found in [DV90].

## 2 Multiple KZG proofs

In this section we derive our main result.

Theorem 1. Let $\{[s^i]\}$ be KZG setup of size at least $d$, and $f_i$ be the coefficients of polynomial $f(X)$ of degree $d$. Let $\{\xi_i\}_{1\leq i\leq n} \subset \mathbb{F}$ be field elements, and suppose that FFT with complexity $n\log n$ is available for $n$-sized vectors. Then KZG proofs for evaluating $f$ at $\{\xi_i\}$ can be obtained

• In  $ O((n+d)\log(n+d)) $ group operations (scalar multiplications) if  $ \{\xi_i\} $ are n-th roots of unity.

• In  $ O(n \log^2 n + d \log d) $ group operations in other cases $ ^{1} $.

### 2.1 Formula for multiple proofs

Let  $ \xi_1, \xi_2, \ldots, \xi_n $ be field elements and let  $ f(\xi_k) = z_k $. We show how to construct KZG proofs for all these  $ (\xi_k, z_k) $ pairs simultaneously.

Proposition 1. Let $\{|s'|\}$ be KZG setup of size at least $d$, and $f_i$ be the coefficients of polynomial $f(X)$ of degree $d$. Let $\Xi = \{\xi_i\} \subset \mathbb{F}$ be field elements. Then KZG proofs for evaluating $f$ at $\{ \xi_i \}$ are evaluations of polynomial $h(X) \in \mathbb{G}^{d-1}[X]$ at $\Xi$ with

 $$ h(X)=h_{1}+h_{2}X+\cdots+h_{d}X^{d-1}. $$ 

where

 $$ h_{i}=\left(f_{d}[s^{d-i}]+f_{d-1}[s^{d-i-1}]+f_{d-2}[s^{d-i-2}]+\cdots+f_{i+1}[s]+f_{i}\right). $$ 

Proof. Note that a proof for  $ \xi_{k} $

 $$ \begin{align*}\pi[f(\xi_{k})=z_{k}]=C_{T_{\xi_{k}}}=f_{d}[s^{d-1}]+(f_{d-1}+\xi_{k}f_{d})[s^{d-2}]+(f_{d-2}+\xi_{k}f_{d-1}+\xi_{k}^{2}f_{d})[s^{d-3}]+\\+(f_{d-3}+\xi_{k}f_{d-2}+\xi_{k}^{2}f_{d-1}+\xi_{k}^{3})[s^{d-4}]+\cdots+(f_{1}+\xi_{k}f_{2}+\xi_{k}^{2}f_{3}+\cdots+\xi_{k}^{(d-1)}f_{d}).\end{align*} $$ 

Regrouping the terms, we get:

 $$ C_{T_{\xi_{k}}}=\left(f_{d}[s^{d-1}]+f_{d-1}[s^{d-2}]+f_{d-2}[s^{d-3}]+\cdots+f_{2}[s]+f_{1}\right)+ $$ 

 $$ +\left(f_{d}[s^{d-2}]+f_{d-1}[s^{d-3}]+f_{d-2}[s^{d-4}]+\cdots+f_{3}[s]+f_{2}\right)\xi_{k}+ $$ 

 $$ +\left(f_{d}[s^{d-3}]+f_{d-1}[s^{d-4}]+f_{d-2}[s^{d-5}]+\cdots+f_{4}[s]+f_{3}\right)\xi_{k}^{2}+ $$ 

 $$ +\left(f_{d}[s^{d-4}]+f_{d-1}[s^{d-5}]+f_{d-2}[s^{d-6}]+\cdots+f_{5}[s]+f_{4}\right)\xi_{k}^{3}+ $$ 

 $$ +(f_{d}[s]+f_{d-1})\xi_{k}^{d-2}+f_{d}\xi_{k}^{d-1}. $$ 

Let for  $ 1 \leq i \leq d $ denote

 $$ h_{i}=\left(f_{d}[s^{d-i}]+f_{d-1}[s^{d-i-1}]+f_{d-2}[s^{d-i-2}]+\cdots+f_{i+1}[s]+f_{i}\right). $$ 

Then

 $$ C_{T_{\xi_{k}}}=h_{1}+h_{2}\xi_{k}+h_{3}\xi_{k}^{2}+\cdots+h_{d}\xi_{k}^{d-1}. $$ 

Let us denote

 $$ \mathbf{C}_{T}=[C_{T_{\xi_{1}}},C_{T_{\xi_{2}}},\ldots,C_{T_{\xi_{n}}}] $$ 

Therefore,  $ \mathbf{C}_T $ is the evaluation of  $ h(X) = \sum_{0 < i < d-1} h_{i+1} X^i $ at points  $ \xi_1, \xi_2, \ldots, \xi_n $.

### 2.2 Computing h

Now we demonstrate that h can be also computed efficiently from  $ \{f_{i}\} $.

Proposition 2. The coefficients  $ h_{i} $ can be computed in  $ O(d \log d) $ time if FFT is available for vectors of size d.

Proof. Indeed, by definition

 $$ \left[\begin{array}{c}h_{1}\\ h_{2}\\ h_{3}\\ \vdots\\ h_{d-1}\\ h_{d}\end{array}\right]=\left[\begin{array}{c c c c c c}f_{d}&f_{d-1}&f_{d-2}&f_{d-3}&\cdots&f_{1}\\ 0&f_{d}&f_{d-1}&f_{d-2}&\cdots&f_{2}\\ 0&0&f_{d}&f_{d-1}&\cdots&f_{3}\\ &\ddots&&&\\ 0&0&0&0&\cdots&f_{d-1}\\ 0&0&0&0&\cdots&f_{d}\end{array}\right]\cdot\left[\begin{bmatrix}s^{d-1}\\ [s^{d-2}]\\ [s^{d-3}]\\ \vdots\\ [s]\\ [1]\end{bmatrix}\right] $$ 

The matrix

 $$ \boldsymbol{A}=\begin{bmatrix}f_{d}&f_{d-1}&f_{d-2}&f_{d-3}&\cdots&f_{1}\\0&f_{d}&f_{d-1}&f_{d-2}&\cdots&f_{2}\\0&0&f_{d}&f_{d-1}&\cdots&f_{3}\\&&\cdots&&&\\0&0&0&0&\cdots&f_{d-1}\\0&0&0&0&\cdots&f_{d}\end{bmatrix} $$ 

is a Toeplitz matrix. It is known that a multiplication of a vector by a  $ d \times d $ Toeplitz matrix costs  $ O(d \log d) $ operations for FFT-friendly fields (see Section 4 for derivation). Let  $ \nu $ be the 2d-th root of unity. Then the algorithm is as follows:

1. Compute

 $$ \mathbf{y}=\mathrm{D F T}_{2d}(\widehat{\mathbf{s}})\quad\mathrm{w h e r e}\quad\widehat{\mathbf{s}}=([s^{d-1}],[s^{d-2}],[s^{d-3}],\cdots,[s],[1],\underbrace{[0],[0],\ldots,[0]}_{}) $$ 

2. Compute $ ^{2} $

 $$ \mathbf{v}=\mathrm{DFT}_{2d}(\widehat{\mathbf{c}})\quad where\quad\widehat{\mathbf{c}}=\left(f_{d},\underbrace{0,0,\ldots,0}_{d\text{ zeroes}},f_{1},f_{2},\ldots,f_{d-1}\right) $$ 

3. Compute

 $$ \mathbf{u}=\mathbf{y}\circ\mathbf{v}. $$ 

4. Compute

 $$ \mathbf{\hat{h}}=\mathrm{iDFT}_{2d}(\mathbf{u}) $$ 

5. Take first d elements of  $ \hat{h} $ as h.

Therefore, we can compute h from the KZG setup using  $ O(d \log d) $ scalar multiplications in G.

### 2.3 Proof of Theorem 1

Now we can prove the statement of Theorem 1. It remains to show the complexity of evaluating $h(X)$ in $\{\xi_i\}$.

 $ \{\xi_i\} $ are  $ n $-th roots of unity. When evaluation points are  $ n $-th roots of unity, the polynomial  $ h(X) $ can be evaluated in  $ n \log n $ time using FFT.

 $ \{\xi_i\} $ are arbitrary values. In this case we adapt the generic fast evaluation algorithm [vzGG13, Algorithm 10.4], which is known to have complexity  $ O(n \log^2 n) $ whenever FFT for  $ n $-sized vectors is available. For the sake of completeness we provide a full description of the algorithm in Section A.

## 3 Computing multiproofs

Proposition 3. Let $r, l$ be integers. Let $\{[s^k]\}$ be KZG setup of size at least $d = r l - 1$, and $f_k$ be the coefficients of polynomial $f(X)$ of degree $d$. Let $\theta \in \mathbb{F}$ be a $l$-power field element with $I$ denoting the set of $l$-roots of $\theta$. Then KZG multiproofs for evaluating $f$ at $I$ is the evaluation of polynomial $v(X) \in \mathbb{G}^{r-2}[X]$ at $\theta$ with

 $$ v(X)=v_{1}+v_{2}X+\ldots+v_{r-1}X^{r-2}. $$ 

where

 $$ v_{j}=\left(f_{d}[s^{d-j l}]+f_{d-1}[s^{d-j l-1}]+f_{d-2}[s^{d-j l-2}]+\cdots+f_{j l+1}[s]+f_{j l}\right). $$ 

Proof. The proof mostly follows the proof of Proposition 1. The only major difference is the computation of the multiproof  $ C_{T_{I}} $ for evaluating f at l-roots of  $ \theta $. Following the definition we obtain

 $$ \begin{aligned}C_{T_{l}}=&\left(f_{d}[s^{d-l}]+f_{d-1}[s^{d-l-1}]+f_{d-2}[s^{d-l-2}]+\cdots+f_{l+1}[s]+f_{l}\right)+\\&+\left(f_{d}[s^{d-2l}]+f_{d-1}[s^{d-2l-1}]+f_{d-2}[s^{d-2l-2}]+\cdots+f_{2l+1}[s]+f_{2l}\right)\theta+\\&+\left(f_{d}[s^{d-3l}]+f_{d-1}[s^{d-3l-1}]+f_{d-2}[s^{d-3l-2}]+\cdots+f_{3l+1}[s]+f_{3l}\right)\theta^{2}+\\&+\left(f_{d}[s^{d-4l}]+f_{d-1}[s^{d-4l-1}]+f_{d-2}[s^{d-4l-2}]+\cdots+f_{4l+1}[s]+f_{4l}\right)\theta^{3}+\\&\cdots\\&+\left(f_{d}[s^{d-(r-1)l}]+f_{d-1}[s^{d-(r-1)l-1}]+f_{d-2}[s^{d-(r-1)l-2}]+\cdots+f_{(r-1)l+1}[s]+f_{(r-1)l}\right)\theta^{r-2}.\\ \end{aligned} $$ 

Let for  $ 1 \leq j \leq r - 1 $ denote

 $$ v_{j}=\left(f_{d}[s^{d-j l}]+f_{d-1}[s^{d-j l-1}]+f_{d-2}[s^{d-j l-2}]+\cdots+f_{j l+1}[s]+f_{j l}\right). $$ 

Then

 $$ C_{T_{I}}=v_{1}+v_{2}\theta+v_{3}\theta^{2}+\cdots+v_{r-1}\theta^{r-2}. $$ 

Therefore,  $ C_{T_I} $ is the evaluation of  $ v(X) = \sum_{0 \leq j \leq r-2} v_{j+1} X^j $ at  $ \theta $.

Now we generalize Proposition 2.

Proposition 4. The coefficients  $ \mathbf{v} = \{v_1, v_2, \ldots, v_{r-1}\} $ can be computed using  $ 2r \log 2r $ scalar multiplications in  $ \mathbb{G}_1 $.

Proof. We note that the representation (22) does not work naively since the matrix representation of (13) is not Toeplitz. We, however, can represent the needed vector v as a sum of Toeplitz multiplications:

 $$ \left[\begin{array}{c}v_{1}\\ v_{2}\\ v_{3}\\ \vdots\\ v_{r-2}\\ v_{r-1}\end{array}\right]=\sum_{0\leq i<l}\left[\begin{array}{c c c c c c}f_{d-i}&f_{d-l-i}&f_{d-2l-i}&f_{d-3l-i}&\cdots&f_{d-(r-2)l-i}\\ 0&f_{d-i}&f_{d-l-i}&f_{d-2l-i}&\cdots&f_{d-(r-3)l-i}\\ 0&0&f_{d-i}&f_{d-l-i}&\cdots&f_{d-(r-4)l-i}\\ &&\ddots&&&\\ 0&0&0&0&\cdots&f_{d-l-i}\\ 0&0&0&0&\cdots&f_{d-i}\end{array}\right]\cdot\left[\begin{array}{c}\left[s^{d-l-i}\right]\\ \left[s^{d-2l-i}\right]\\ \left[s^{d-3l-i}\right]\\ \vdots\\ \left[s^{d-(r-2)l-i}\right]\\ \left[s^{d-(r-1)l-i}\right]\end{array}\right] $$ 

Following Proposition 2, we compute v as follows.

1. Compute for  $ 0 \leq i < l $

 $$ \widehat{\mathbf{s}}_{i}=([s^{d-l-i}],[s^{d-2l-i}],[s^{d-3l-i}],\ldots,[s^{d-(r-2)l-i}],[s^{d-(r-1)l-i}],\quad\underbrace{[0],[0],\ldots,[0]}_{} $$ 

 $$ (r-1)\;\mathrm{n e u t r a l~e l e m e n t s} $$ 

 $$ \mathbf{y}_{i}=\mathrm{D F T}_{2(r-1)}(\widehat{\mathbf{s}_{i}}) $$ 

2. Compute for  $ 0 \leq i < l $

 $$ \widehat{\mathbf{c}}_{i}=\left(f_{d-i},0,0,\cdots,0,f_{d-(r-2)l-i},f_{d-(r-3)l-i},\cdots,f_{d-l-i}\right) $$ 

 $$ (r-1)\;z e r o e s $$ 

 $$ \mathbf{w}_{i}=\mathrm{D F T}_{2(r-1)}(\widehat{\mathbf{c}_{i}}) $$ 

3. Compute

 $$ \mathbf{u}=\left(\sum_{0\leq i<l}\mathbf{w}_{i}\circ\mathbf{y}_{i}\right) $$ 

4. Compute

 $$ \hat{\mathbf{v}}=\mathrm{iDFT}_{2r-2}(\mathbf{u}) $$ 

5. Take first  $ r - 1 $ elements of  $ \hat{\mathbf{v}} $ as  $ \mathbf{v} $.

It is easy to see that steps 1 and 4 take  $ 2rl \log r $ scalar multiplications each, step 2 needs field operations only, and step 3 needs  $ 2rl $ scalar multiplications.

Combining two propositions, we arrive at the main theorem for the case when the multiproofs are constructed for the set of roots of unity.

Theorem 2. Let $r, l$ be integers. Let $\{[s^k]\}$ be KZG setup of size at least $d = r l - 1$, and $f_k$ be the coefficients of polynomial $f(X)$ of degree $d$. Let $\Theta = \{\theta_j\}_{1 \leq j \leq n} \subset \mathbb{F}$ be $n$-root of unity with $I_j$ denoting the set of $l$-roots of $\theta_j$. Then KZG multiproofs for evaluating $f$ at $I_j$ can be computed in $2r l \log 2r + n \log n$ scalar multiplications.

Proof. In order to compute the multiproofs for $\Theta$, we need to evaluate $v(X)$ at $r$ points. If $\Theta$ is the set of roots of unity, it takes additional $n\log n$ scalar multiplications.

## 4 Circulant and Toeplitz matrix-vector product computation

### 4.1 Circulant multiplication

A matrix-vector product with a circulant matrix B and vector

 $$ \boldsymbol{B}=\begin{bmatrix}b_{n-1}&b_{n-2}&b_{n-3}&b_{n-4}&\cdots&b_{0}\\ b_{0}&b_{n-1}&b_{n-2}&b_{n-3}&\cdots&b_{1}\\ b_{1}&b_{0}&b_{n-1}&b_{n-2}&\cdots&b_{2}\\ &\cdots&&&\\ b_{n-3}&b_{n-4}&b_{n-5}&b_{n-6}&\cdots&b_{n-2}\\ b_{n-2}&b_{n-3}&b_{n-4}&b_{n-5}&\cdots&b_{n-1}\end{bmatrix}\quad\mathbf{c}=\begin{bmatrix}c_{0}\\ c_{1}\\ c_{2}\\ \vdots\\ c_{n-2}\\ c_{n-1}\end{bmatrix}\quad\boldsymbol{B}\mathbf{c}=\mathbf{a}=\begin{bmatrix}a_{0}\\ a_{1}\\ a_{2}\\ \vdots\\ a_{n-2}\\ a_{n-1}\end{bmatrix} $$ 

is equivalent to polynomial multiplication. Concretely, let

 $$ b(X)=\sum_{i}b_{i}X^{i},\quad c(X)=\sum_{i}c_{i}X^{i},\quad a(X)=\sum_{i}a_{i}X^{i} $$ 

Then  $ a_{i}=\sum_{j+k=i-1\pmod{n}}b_{j}c_{k} $ and so

 $$ a(X)\equiv X\cdot b(X)\cdot c(X)\pmod{X^{n}-1} $$ 

Denote the $n$-th root of unity by $\omega$, then $a(\omega^{i}) = \omega^{i} \cdot b(\omega^{i}) \cdot c(\omega^{i})$ since $\omega^{n} = 1$. Therefore we have the following algorithm for a:

1. Compute  $ \widehat{\mathbf{b}} = \mathrm{DFT}_{n}(b_{n-1}, b_0, b_1, b_2, \ldots, b_{n-2}) $ where we apply the DFT to  $ b'(X) = Xb(X) $.

2. Compute  $ \widehat{\mathbf{c}} = \mathrm{DFT}_{n}(c_{0}, c_{1}, c_{2}, \ldots, c_{n-1}) $.

3. Compute  $ \hat{\mathbf{a}} = \hat{\mathbf{b}} \circ \hat{\mathbf{c}} $.

4. Compute  $ \mathbf{a} = \mathrm{iDFT}_n(\widehat{\mathbf{a}}) $.

If the FFT exists for n-th root of unity then the circulant matrix-vector multiplication can be done in  $ n(3\log n+1) $ time.

### 4.2 Toeplitz multiplication

A matrix-vector product with a Toeplitz matrix D and vector

 $$ \boldsymbol{F}=\begin{bmatrix}f_{n-1}&f_{n-2}&f_{n-3}&f_{n-4}&\cdots&f_{0}\\0&f_{n-1}&f_{n-2}&f_{n-3}&\cdots&f_{1}\\0&0&f_{n-1}&f_{n-2}&\cdots&f_{2}\\&&\cdots&&\\0&0&0&0&\cdots&f_{n-2}\\0&0&0&0&\cdots&f_{n-1}\end{bmatrix}\quad\mathbf{c}=\begin{bmatrix}c_{0}\\c_{1}\\c_{2}\\\vdots\\c_{n-2}\\c_{n-1}\end{bmatrix}\quad\boldsymbol{F}\mathbf{c}=\mathbf{a}=\begin{bmatrix}a_{0}\\a_{1}\\a_{2}\\\vdots\\a_{n-2}\\a_{n-1}\end{bmatrix} $$ 

is reduced to the circulant case by padding the matrix  $ F $ to size  $ 2n \times 2n $ and vector  $ \mathbf{c} $ accordingly:

 $$ F^{\prime}=\begin{bmatrix}{{{f_{n-1}}}}&{{{f_{n-2}}}}&{{{f_{n-3}}}}&{{{f_{n-4}}}}&{{{\cdots}}}&{{{f_{0}}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{0}}} \\{{{0}}}&{{{f_{n-1}}}}&{{{f_{n-2}}}}&{{{f_{n-3}}}}&{{{\cdots}}}&{{{f_{1}}}}&{{{f_{0}}}}&{{{0}}}&{{{\cdots}}}&{{{0}}} \\{{{0}}}&{{{0}}}&{{{f_{n-1}}}}&{{{f_{n-2}}}}&{{{\cdots}}}&{{{f_{2}}}}&{{{f_{1}}}}&{{{f_{0}}}}&{{{\cdots}}}&{{{0}}} \\{{{\vdots}}} \\{{{0}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{f_{n-2}}}}&{{{f_{n-3}}}}&{{{f_{n-4}}}}&{{{\cdots}}}&{{{0}}} \\{{{0}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{f_{n-1}}}}&{{{f_{n-2}}}}&{{{f_{n-3}}}}&{{{\cdots}}}&{{{0}}} \\{{{0}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{0}}}&{{{0}}}&{{{f_{n-1}}}}&{{{\cdots}}}&{{{f_{1}}}} \\{{{f_{0}}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{f_{2}}}} \\{{{f_{1}}}}&{{{f_{0}}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{f_{2}}}} \\{{{\vdots}}} \\{{{f_{n-2}}}}&{{{f_{n-3}}}}&{{{f_{n-4}}}}&{{{f_{n-5}}}}&{{{\cdots}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{f_{n-1}}}}\end{bmatrix}\quad\mathbf{c}^{\prime}=\begin{bmatrix}{{{c_{0}}}} \\{{{c_{1}}}} \\{{{c_{2}}}} \\{{{\vdots}}} \\{{{c_{n-1}}}} \\{{{0}}} \\{{{\vdots}}} \\{{{0}}}\end{bmatrix} $$ 

As a result the product of  $ F' $ and  $ \mathbf{c}' $ has all the elements of a:

 $$ \begin{aligned}&\boldsymbol{F}^{\prime}\cdot\mathbf{c}^{\prime}=\mathbf{a}^{\prime}=\begin{bmatrix}\\ &a_{0}\\&a_{1}\\&a_{2}\\&\vdots\\&a_{n-2}\\&a_{n-1}\\&a_{n}\\&\vdots\\&a_{2n-1}\\ &\end{bmatrix}\\ \end{aligned} $$ 

Therefore, to compute  $ F \cdot \mathbf{c} $ we compute  $ F' \cdot \mathbf{c}' $ using DFT and then select the top  $ n $ elements of the resulting vector. If the FFT exists for the size  $ 2n $, then the Toeplitz matrix-vector multiplication can be done in  $ \sim 6n \log n $ time.

If the FFT does not exist for 2n but exists for k > 2n then one can pad the matrix F to size  $ k \times k $ as follows, with every column and row having exactly n - k zeros:

 $$ F^{\prime\prime}=\left[\begin{array}{ccccc}{{{f_{n-1}}}}&{{{f_{n-2}}}}&{{{f_{n-3}}}}&{{{f_{n-4}}}}&{{{\cdots}}}&{{{f_{0}}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{0}}} \\{{{0}}}&{{{f_{n-1}}}}&{{{f_{n-2}}}}&{{{f_{n-3}}}}&{{{\cdots}}}&{{{f_{1}}}}&{{{f_{0}}}}&{{{0}}}&{{{\cdots}}}&{{{0}}} \\{{{0}}}&{{{0}}}&{{{f_{n-1}}}}&{{{f_{n-2}}}}&{{{\cdots}}}&{{{f_{2}}}}&{{{f_{1}}}}&{{{f_{0}}}}&{{{\cdots}}}&{{{0}}} \\{{{\vdots}}} \\{{{0}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{f_{n-2}}}}&{{{f_{n-3}}}}&{{{f_{n-4}}}}&{{{\cdots}}}&{{{0}}} \\{{{0}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{f_{n-1}}}}&{{{f_{n-2}}}}&{{{f_{n-3}}}}&{{{\cdots}}}&{{{0}}} \\{{{0}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{0}}}&{{{f_{n-1}}}}&{{{f_{n-2}}}}&{{{\cdots}}}&{{{0}}} \\{{{\vdots}}} \\{{{0}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{0}}}&{{{0}}}&{{{f_{n-1}}}}&{{{\cdots}}}&{{{0}}} \\{{{f_{0}}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{f_{0}}}} \\{{{f_{1}}}}&{{{f_{0}}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{f_{1}}}} \\{{{\vdots}}} \\{{{f_{n-2}}}}&{{{f_{n-3}}}}&{{{f_{n-4}}}}&{{{f_{n-5}}}}&{{{\cdots}}}&{{{0}}}&{{{0}}}&{{{0}}}&{{{\cdots}}}&{{{f_{n-1}}}} \\\end{array}\right] $$ 

## 5 Applications

Our technique is useful whenever a large number of KZG openings is required by a protocol. Examples are

- Lookup arguments. When a table is encoded as polynomial evaluations over roots of unity, the  $ O(n \log n) $ version of Theorem 1 applies  $ [ZBK^{+}22, ZGK^{+}22, EFG22] $. In contrast, when a table is encoded as the set of roots of a polynomial, then individual proofs are no longer at roots of unity. For this reason [GK22] proved the special case of the  $ O(n \log^2 n) $ case of Theorem 1 where the evaluations are all zero.

• Vector commitment schemes based on KZG. Preparing many (or all) proofs is done with our technique [WUP22, Tom20]. Another application is speeding up the trusted setup phase [TAB+20].

• Data availability sampling schemes based on KZG [HASW23].

## References

[CT65] James W Cooley and John W Tukey. An algorithm for the machine calculation of complex fourier series. Mathematics of computation, 19(90):297–301, 1965.

[DV90] Pierre Duhamel and Martin Vetterli. Fast fourier transforms: a tutorial review and a state of the art. Signal processing, 19(4):259–299, 1990.

[EFG22] Liam Eagen, Dario Fiore, and Ariel Gabizon. cq: Cached quotients for fast lookups. Cryptology ePrint Archive, Paper 2022/1763, 2022. https://eprint.iacr.org/2022/1763.

[GK22] Ariel Gabizon and Dmitry Khovratovich. lookup: Fractional decomposition-based lookups in quasi-linear time independent of table size. Cryptology ePrint Archive, Paper 2022/1447, 2022. https://eprint.iacr.org/2022/1447.

[HASW23] Mathias Hall-Andersen, Mark Simkin, and Benedikt Wagner. Foundations of data availability sampling. Cryptology ePrint Archive, 2023. available at https://eprint.iacr.org/2023/1079.pdf.

[KZG10] Aniket Kate, Gregory M. Zaverucha, and Ian Goldberg. Constant-size commitments to polynomials and their applications. In ASIACRYPT, volume 6477 of Lecture Notes in Computer Science, pages 177–194. Springer, 2010.

[TAB+20] Alin Tomescu, Ittai Abraham, Vitalik Buterin, Justin Drake, Dankrad Feist, and Dmitry Khovratovich. Aggregatable subvector commitments for stateless cryptocurrencies. In SCN, volume 12238 of Lecture Notes in Computer Science, pages 45–64. Springer, 2020.

[Tom20] Alin Tomescu. How to compute all pointproofs. Cryptology ePrint Archive, Paper 2020/1516, 2020. https://eprint.iacr.org/2020/1516.

[vzGG13] J. von zur Gathen and J. Gerhard. Modern Computer Algebra, Third edition. 2013.

[WUP22] Weijie Wang, Annie Ulichney, and Charalampos Papamanthou. Balanceproofs: Maintainable vector commitments with fast aggregation. Cryptology ePrint Archive, Paper 2022/864, 2022. https://eprint.iacr.org/2022/864.

[ZBK $ ^{+} $22] Arantxa Zapico, Vitalik Buterin, Dmitry Khovratovich, Mary Maller, Anca Nitulescu, and Mark Simkin. Caulk: Lookup arguments in sublinear time. In CCS, pages 3121–3134. ACM, 2022.

[ZGK $ ^{+} $22] Arantxa Zapico, Ariel Gabizon, Dmitry Khovratovich, Mary Maller, and Carla Ràfols. Baloo: Nearly optimal lookup arguments. Cryptology ePrint Archive, Paper 2022/1565, 2022. https://eprint.iacr.org/2022/1565.

### A Fast evaluation algorithm for group polynomials

This section is an adaptation of fast polynomial algorithms from [vzGG13] to the case when coefficients of one of polynomials are group elements. We first define what it to means to multiply polynomials from different domains.

Let  $  F = \sum_i F_i X^i \in \mathbb{G}^n[X]  $,  $  g = \sum_j g_j X^j \in \mathbb{F}^m[X]  $. Then  $  F \cdot g = H \in \mathbb{G}^{m+n}[X]  $ is defined as

 $$ H=\sum_{k}H_{k}X^{k}=\sum_{k}\left(\sum_{i\leq k}[g_{k-i}]F_{i}\right)X^{k} $$ 

### A.1 Fast evaluation algorithm

 $$ F\in\mathbb{G}^{d}[X] $$ 

 $$ A=\left(a_{1},a_{2},\ldots,a_{d}\right)\in\mathbb{F}. $$ 

Output:  $  C = (c_1, c_2, \ldots, c_d) \in \mathbb{G}^d  $ such that  $  f(a_i) = c_i  $ for all  $  i  $.

Construction.

• If  $ d = 1 $ compute  $ F(a_{1}) $ in constant time and return.

• Else split A into  $ A_{1} $ and  $ A_{2} $.

- Let  $ g_1(X) = \prod_{a \in A_1}(X - a) \in \mathbb{F}^{d/2}[X] $ be vanishing poly of degree  $ d/2 $ for  $ A_1 $, and  $ g_2(X) \in \mathbb{F}^{d/2}[X] $ be vanishing poly of degree  $ d/2 $ for  $ A_2 $.

- Compute  $ F_1(X) = F(X) \mod g_1(X) $ and  $ F_2(X) = F(X) \mod g_2(X) $ of degree  $ d/2 $ using fast division algorithm (Section A.2).

• Evaluate  $ F_{1} $ on  $ A_{1} $ and get  $ C_{1} $ recursively (go to step 1). Evaluate  $ F_{2} $ on  $ A_{2} $ and get  $ C_{2} $. Return  $ C_{1} \cup C_{2} $.

Complexity. The algorithm is divide-and-conquer. At the combination step we apply the fast division algorithm of complexity  $ O(d \log d) $. The cost of computing all vanishing polynomials is  $ d \log^2 d $ (see below). Thus for the complexity  $ C(d) $ of the evaluation algorithm without it we have an equation

 $$ C(d)=d\log d+2C(d/2) $$ 

Thus the total complexity is  $ O(d \log^2 d) $ group operations.

Constructing all vanishing polys We construct all vanishing polynomials in the monomial form from low degree to high degree. Recall that these polynomials belong to  $ \mathbb{F}[X] $ i.e. their coefficients are field elements. In order to compute a vanishing poly of degree  $ r $, we multiply two vanishing polys of degree  $ r/2 $ using fast multiplication algorithm. The complexity of the combination step is  $ r \log r $ so we have for the complexity  $ V(r) $ an equation:

 $$ V(r)=r\log r+2V(r/2) $$ 

This yields total complexity of  $ r \log^{2} r $.

### A.2 Fast division algorithm

Input: F ∈ Gn[X], g ∈ Fm[X].

Output:  $ Q \in \mathbb{G}^{n-m}[X] $,  $ R \in \mathbb{G}^{m-1}[X] $ such that

 $$ F(X)=Q(X)g(X)+R(X) $$ 

Idea For  $ F(X) = F_0 + F_1X + \cdots + F_nX^n $ define

 $$ \mathrm{rev}(F)=F_{n}+F_{n-1}X+\cdots+F_{0}X^{n} $$ 

Note that

 $$ X^{n}F(1/x)=X^{n-m}Q(1/X)X^{m}g(1/X)+X^{n-m+1}X^{m-1}R(1/X). $$ 

In terms of reverses:

 $$ \mathrm{rev}(F)=\mathrm{rev}(Q)\cdot\mathrm{rev}(g)+X^{n-m+1}\mathrm{rev}(R). $$ 

Then

 $$ \operatorname{rev}(F)\equiv\operatorname{rev}(Q)\cdot\operatorname{rev}(g)\pmod{X^{n-m+1}}. $$ 

where reduction modulo  $ X^{n-m+1} $ means dropping terms of degree  $ (n-m+1) $ and higher. This is consistent with regular modular reduction for polynomials.

Finally we obtain

 $$ \operatorname{rev}(Q)\equiv\operatorname{rev}(F)\cdot\operatorname{rev}(g)^{-1}\pmod{X^{n-m+1}}. $$ 

##### Construction

1. Compute  $ \operatorname{rev}(F) \in \mathbb{G}^n[X] $,  $ \operatorname{rev}(g) \in \mathbb{F}^m[X] $.

2. Compute  $ \mathrm{rev}(g)^{-1} \bmod X^{n-m+1} $ using fast inversion algorithm (section A.3).

3. Find rev(Q), then q and R using fast polynomial multiplication.

Complexity Both fast inversion algorithm and fast multiplication algorithm have complexity  $ O(d \log d) $ (see below) so the total complexity is  $ O(d \log d) $ group operations.

### A.3 Fast Inversion Algorithm

Input:  $ f \in \mathbb{F}[X] $,  $ l $.

Output:  $  g \in \mathbb{F}[X]  $ such that

 $$ f(X)g(X)\equiv1\pmod{X^{l}} $$ 

Idea We find a "root" of an equation  $ \frac{1}{a} - f = 0 $ using Newton iteration for  $ \phi(g) = 0 $:

 $$ g_{i+1}=g_{i}-\frac{\phi(g_{i})}{\phi^{\prime}(g_{i})} $$ 

which in our case is

 $$ g_{i+1}=g_{i}-\frac{1/g_{i}-f}{-1/g_{i}^{2}}=2g_{i}-f g_{i}^{2} $$ 

##### Construction

1. Initialize  $ g_{0} = \frac{1}{f(0)} $.

2. Compute for i up to  $ \log l $:

 $$ g_{i+1}=\left(2g_{i}-f g_{i}^{2}\right)\bmod x^{2^{i+1}} $$ 

3. Return  $ g_{\log l+1} $.

Complexity At each step we do 3 fast polynomial multiplications of degree  $ 2^{i} $. Using that

 $$ \sum_{1\leq i\leq r}c\cdot2^{i}\cdot i\leq2cr2^{r} $$ 

the total cost is still  $ O(d \log d) $ as reduction modulo  $ x^{2^{i+1}} $ is easy.

### A.4 Fast multiplication Algorithm for Group Polynomials

Input: F ∈ Gn[X], g ∈ Fm[X].

Output:  $ H \in \mathbb{G}^{n-m}[X] $ such that

 $$ H(X)=F(X)g(X) $$ 

The algorithm is as follows:

1. Evaluate $F$ on $2d$-roots of unity using FFT and obtain tuple $\bar{F} \in \mathbb{G}^{2d}$. We multiply group elements by field elements here.

2. Evaluate g on 2d-roots of unity using FFT and obtain tuple  $ \widetilde{g} \in \mathbb{F}^{2d} $.

3. Multiply  $ \tilde{F} $ by  $ \tilde{g} $ componentwise and obtain  $ \tilde{H} $.

4. Apply inverse FFT to  $ \bar{H} $ and obtain H.

The complexity is 2d log d group operations.

We multiply 2 polynomials of degree d in O(d log d) time using FFT:

1. Compute 2d-FFT of both polys. Note that we do not evaluate the polynomials at a group element here, but rather remain in the field F.

2. Multiply pairwise.

3. Compute inverse FFT.

