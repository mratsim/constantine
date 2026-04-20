---
title: Multiplying a Vector by a Toeplitz Matrix
source: https://alinush.github.io/2020/03/19/multiplying-a-vector-by-a-toeplitz-matrix.html
author: Alin Tomescu
date: 2020-03-19
---

These are some notes on how to efficiently multiply a *Toeplitz matrix* by a vector.
I was writing these for myself while implementing the new amortized KZG proofs by Feist and Khovratovich, but I thought they might be useful for you too.

## Preliminaries

We use column vector notation for all vectors. If $[a, b, c]$ is a row vector, then $[a,b,c]^T$ denotes its transpose: i.e., the column vector \(\begin{bmatrix}a \\\\\ b \\\\\ c\end{bmatrix}\).

## What’s a Toeplitz (and a circulant) matrix?

A *Toeplitz matrix* (e.g. of size $4\times 4$) looks like this:

\begin{bmatrix}
a_0 & a_{-1} & a_{-2} & a_{-3}\\

a_1 & a_0 & a_{-1} & a_{-2}\\

a_2 & a_1 & a_0 & a_{-1}\\

a_3 & a_2 & a_1 & a_0
\end{bmatrix}

Note the odd use of negative indices here, since typically we usually use positive numbers to index. It’s just convenient for notation to use negative indices.

In other words, it’s a square matrix where the entries “repeat diagonally.” A concrete example would be:

\begin{bmatrix}
7 & 11 & 5 & 6 \\

3 & 7 & 11 & 5 \\

8 & 3 & 7 & 11 \\

1 & 8 & 3 & 7
\end{bmatrix}

A *circulant matrix* $C$ is a special form of Toeplitz matrix:

\begin{bmatrix}
a_0 & a_3 & a_2 & a_1\\

a_1 & a_0 & a_3 & a_2\\

a_2 & a_1 & a_0 & a_3\\

a_3 & a_2 & a_1 & a_0
\end{bmatrix}

In other words, each row is shifted/rotated to the right by 1 entry. (Or, alternatively, each column is shifted/rotated down by 1 entry.)

In general, note that any circulant matrix $C_n$ of size $n\times n$ has a *vector representation*:

Also, note that a circulant matrix is a particular type of a Toeplitz matrix where $a_{-i} = a_{n-i}, \forall i \in[n-1]$.

Here are two examples of circulant matrices:

\[C_4=\begin{bmatrix} 7 & 11 & 5 & 6 \\\\\ 6 & 7 & 11 & 5 \\\\\ 5 & 6 & 7 & 11 \\\\\ 11 & 5 & 6 & 7 \end{bmatrix}, C_4'=\begin{bmatrix} 7 & 1 & 8 & 3 \\\\\ 3 & 7 & 1 & 8 \\\\\ 8 & 3 & 7 & 1 \\\\\ 1 & 8 & 3 & 7 \end{bmatrix}\]Importantly, a circulant matrix is *diagonalizable* by the DFT matrix (although we won’t explain why).

First, recall an example of a DFT matrix (e.g., of size $4 \times 4$):

\[F_4=\begin{bmatrix} 1 & 1 & 1 & 1 \\\\\ 1 & (w)^1 & (w)^2 & (w)^3 \\\\\ 1 & (w^2)^1 & (w^2)^2 & (w^2)^3 \\\\\ 1 & (w^3)^1 & (w^3)^2 & (w^3)^3 \end{bmatrix}\]What we’re saying is that a circulant matrix $C_n$ of size $n\times n$ can be written as:

\[C_n = (F_n)^{-1} \mathsf{diag}(F_n \vec{a_n}) F_n\]Here, \(\vec{a_n} = [a_0, \dots, a_{n-1}]\) is the vector representation of $C_n$ as discussed before (see above). Also, $\mathsf{diag}(F_n \vec{a})$ is the $n\times n$ diagonal matrix whose diagonal entries are the entries from $F_n\vec{a_n}$ (i.e., the entry at position $(i,i)$ is the $i$th entry in $F_n\vec{a_n}$) and all other entries are 0.

## Multiplying a circulant matrix by a vector

Let $y=\mathsf{DFT}(\vec{x}) = F_n \vec{x}$ denote the DFT of a vector $\vec{x}$ and let $\vec{x}=\mathsf{DFT}^{-1}(y)=F_n^{-1} \vec{y}$ denote the inverse DFT.

If $C_n$ is circulant with vector representation $\vec{a_n}$, then multiplying it by a size-$n$ vector $\vec{x}$ can be written as:

\begin{align}
C_n \vec{x} &= \left((F_n)^{-1} \mathsf{diag}(F_n\vec{a_n}) F_n\right)\vec{x}\\

&= (F_n)^{-1} (\mathsf{diag}(F_n\vec{a_n}) (F_n \vec{x}))\\

&= \mathsf{DFT}^{-1}(\mathsf{diag}(\mathsf{DFT}(\vec{a_n})) \mathsf{DFT}(\vec{x}))\\

&= \mathsf{DFT}^{-1}(\mathsf{diag}(\vec{v}) \vec{y})\\

&= \mathsf{DFT}^{-1}(\vec{v} \circ \vec{y})\\

&= \mathsf{DFT}^{-1}(\vec{u})
\end{align}

In other words, what we must do is:

- Compute $\vec{y}$ by doing a DFT on $\vec{x}$ (in $\Theta(n\log{n})$ time)
- Compute $\vec{v}$ by doing a DFT on $\vec{a_n}$ (in $\Theta(n\log{n})$ time)
- Compute the Hadamard product $\vec{u}=\vec{v} \circ \vec{y}$,
- (Since that’s what happens when you multiply a diagonal matrix by a vector.)

- Do an inverse DFT on $\vec{u}$ (in $\Theta(n\log{n})$ time).

Thus, we can compute $C_n \vec{x}$ in $\Theta(n\log{n})$ time.

## Multiplying a Toeplitz matrix by a vector

To multiply a Toeplitz matrix $T_n$ by a vector $\vec{x}$, we’ll embed the matrix in a circulant matrix $C_{2n}$ in such a manner that the first $n$ entries of $C_{2n}\vec{x}$ will equal exactly $T_n\vec{x}$.

We’ll use $T_4$ as an example:

\[T_4 = \begin{bmatrix} a_0 & a_{-1} & a_{-2} & a_{-3}\\\\\ a_1 & a_0 & a_{-1} & a_{-2}\\\\\ a_2 & a_1 & a_0 & a_{-1}\\\\\ a_3 & a_2 & a_1 & a_0 \end{bmatrix}\]We want to build a circulant matrix $C_8$ from $T_4$ such that:

\[C_8 \begin{bmatrix} \vec{x} \\\\\ \vec{0} \end{bmatrix} = \begin{bmatrix} T_4 \vec{x} \\\\\ ? \end{bmatrix}\]Note that we don’t care what we get in the last $n$ entries of the result, which we denote with a question mark. Also, $\vec{0}$ denotes the vector of $n=4$ zeros.

If we had such a $C_8$, then we could multiply it with \(\begin{bmatrix}\vec{x}\\\\\ \vec{0}\end{bmatrix}\) using the $\Theta(n\log{n})$ multiplication algorithm from the previous section and efficiently compute $T_4\vec{x}$.

We’ll build $C_8$ from $T_4$ and some other, to be determined matrix which we denote using $B_4$.

\[C_8 = \begin{bmatrix} T_4 & B_4 \\\\\ B_4 & T_4 \end{bmatrix}\]Note that this gives us what we want: \(C_8 \begin{bmatrix}\vec{x}\\\\\ \vec{0}\end{bmatrix} = \begin{bmatrix} T_4 & B_4 \\\\\ B_4 & T_4 \end{bmatrix} \begin{bmatrix}\vec{x}\\\\\ \vec{0}\end{bmatrix}= \begin{bmatrix}T_4\vec{x}\\\\\ B_4\vec{x}\end{bmatrix}\)

In other words, the first $n$ entries of the product are indeed equal to $T_4 \vec{x}$, independent of what we pick for $B_4$.

But for us to efficiently compute the product, we’ll need to pick a $B_4$ that makes $C_8$ circulant. So let’s look at what $C_8$ looks like with just the two $T_4$’s in it:

\[C_8 = \begin{bmatrix} a_0 & a_{-1} & a_{-2} & a_{-3} & ? & ? & ? & ? \\\\\ a_1 & a_0 & a_{-1} & a_{-2} & ? & ? & ? & ? \\\\\ a_2 & a_1 & a_0 & a_{-1} & ? & ? & ? & ? \\\\\ a_3 & a_2 & a_1 & a_0 & ? & ? & ? & ? \\\\ ? & ? & ? & ? & a_0 & a_{-1} & a_{-2} & a_{-3}\\\\\ ? & ? & ? & ? & a_1 & a_0 & a_{-1} & a_{-2}\\\\\ ? & ? & ? & ? & a_2 & a_1 & a_0 & a_{-1}\\\\\ ? & ? & ? & ? & a_3 & a_2 & a_1 & a_0 \end{bmatrix}\]We can fill in part of the puzzle to keep $C_8$ circulant:

\[C_8 = \begin{bmatrix} a_0 & a_{-1} & a_{-2} & a_{-3} & ? & ? & ? & ? \\\\\ a_1 & a_0 & a_{-1} & a_{-2} & \mathbf{a_{-3}} & ? & ? & ? \\\\\ a_2 & a_1 & a_0 & a_{-1} & \mathbf{a_{-2}} & \mathbf{a_{-3}} & ? & ? \\\\\ a_3 & a_2 & a_1 & a_0 & \mathbf{a_{-1}} & \mathbf{a_{-2}} & \mathbf{a_{-3}} & ? \\\\ ? & \mathbf{a_3} & \mathbf{a_2} & \mathbf{a_1} & a_0 & a_{-1} & a_{-2} & a_{-3}\\\\\ ? & ? & \mathbf{a_3} & \mathbf{a_2} & a_1 & a_0 & a_{-1} & a_{-2}\\\\\ ? & ? & ? & \mathbf{a_3} & a_2 & a_1 & a_0 & a_{-1}\\\\\ ? & ? & ? & ? & a_3 & a_2 & a_1 & a_0 \end{bmatrix}\]By now, you can tell that $B_4$ can be set to:

\[B_4 = \begin{bmatrix} ? & \mathbf{a_3} & \mathbf{a_2} & \mathbf{a_1} \\\\\ \mathbf{a_{-3}} & ? &\mathbf{a_3} & \mathbf{a_2} \\\\\ \mathbf{a_{-2}} &\mathbf{a_{-3}} & ? &\mathbf{a_3} \\\\\ \mathbf{a_{-1}} & \mathbf{a_{-2}} & \mathbf{a_{-3}} & ? \end{bmatrix}\]Since the only constraint for the diagonal elements is to be the same, we’ll set them to $a_0$. So, the final $C_8$ will be:

\[C_8 = \begin{bmatrix} a_0 & a_{-1} & a_{-2} & a_{-3} & \mathbf{a_0} & \mathbf{a_3} & \mathbf{a_2} & \mathbf{a_1} \\\\\ a_1 & a_0 & a_{-1} & a_{-2} & \mathbf{a_{-3}} & \mathbf{a_0} & \mathbf{a_3} & \mathbf{a_2} \\\\\ a_2 & a_1 & a_0 & a_{-1} & \mathbf{a_{-2}} & \mathbf{a_{-3}} & \mathbf{a_0} & \mathbf{a_3} \\\\\ a_3 & a_2 & a_1 & a_0 & \mathbf{a_{-1}} & \mathbf{a_{-2}} & \mathbf{a_{-3}} & \mathbf{a_0}\\\\ \mathbf{a_0} & \mathbf{a_3} & \mathbf{a_2} & \mathbf{a_1} & a_0 & a_{-1} & a_{-2} & a_{-3}\\\\\ \mathbf{a_{-3}} & \mathbf{a_0} & \mathbf{a_3} & \mathbf{a_2} & a_1 & a_0 & a_{-1} & a_{-2}\\\\\ \mathbf{a_{-2}} & \mathbf{a_{-3}} & \mathbf{a_0} & \mathbf{a_3} & a_2 & a_1 & a_0 & a_{-1}\\\\\ \mathbf{a_{-1}} & \mathbf{a_{-2}} & \mathbf{a_{-3}} & \mathbf{a_0} & a_3 & a_2 & a_1 & a_0 \end{bmatrix}\]The question that remains to be answered is what is the *vector representation* $\vec{a_8}$ of $C_8$, since that’s what we’ll need to efficiently evaluate $C_8\vec{x}$ and thus $T_4\vec{x}$.

The answer is, as before, the elements in the first columns of $C_8$, which are:

\[\vec{a_8}=[ a_0, a_1, a_2, a_3, a_0, a_{-3}, a_{-2}, a_{-1} ]^T\]Thus, applying the algorithm for circulant matrices from before, what we must do is:

- Build $\vec{a_{2n}}$ from the entries \(\{a_{n-1}, a_{n-2}, \dots, a_1, a_0, a_{-1}, \dots, a_{-(n-1)}\}\) of the Toeplitz matrix $T_n$
- Compute $\vec{y}$ by doing a DFT on $[\vec{x}, \vec{0}]^T$
- Compute $\vec{v}$ by doing a DFT on $\vec{a_{2n}}$ (e.g., on $\vec{a_8}$ from above)
- Compute the Hadamard product $\vec{u}=\vec{v} \circ \vec{y}$,
- Do an inverse DFT on $\vec{u}$
- The product $T_n \vec{x}$ consists of the first $n$ entries of the resulting vector
