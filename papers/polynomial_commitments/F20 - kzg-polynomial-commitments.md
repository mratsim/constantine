# KZG polynomial commitments

## Introduction

I want to try and give an introduction to the commitment scheme introduced by Kate, Zaverucha and Goldberg 1. This post does not aim to be mathematically or cryptographically rigorous or complete – it is meant to be an introduction.

This scheme is often also called Kate polynomial commitment scheme (pronounced kah-tay). As a polynomial commitment scheme, it allows a *prover* to compute a *commitment* to a polynomial, with the properties that this commitment can later be opened at any position: The *prover* shows that the value of the polynomial at a certain position is equal to a claimed value.

It is called a *commitment*, because having sent the commitment value (an elliptic curve point) to someone (the *verifier*), the prover cannot change the polynomial they are working with. They will only be able to provide valid proofs for one polynomial, and if they are trying to cheat, they will either fail to produce a proof or the proof will be rejected by the verifier.

### Prerequisites

I highly recommend reading Vitalik Buterin’s post on elliptic curve pairings, if you aren’t familiar with finite fields, elliptic curves, and pairings.

### Comparison to Merkle trees

If you’re familiar with Merkle trees, I want to try to give a bit more of an intuition on the difference between those and Kate commitments. A Merkle tree is what cryptographers call a *vector commitment*: Using a Merkle tree of depth \(d\), you can compute a commitment to a vector (that is, a list of elements of fixed length) \(a_0, \ldots, a_{2^d-1}\). Using the familiar *Merkle proofs*, you can provide a proof that an element \(a_i\) is a member of this vector at position \(i\) using \(d\) hashes.

We can actually make a polynomial commitment out of Merkle trees: Recall that a polynomial \(p(X)\) of degree \(n\) is nothing other than a function \(p(X) = \sum_{i=0}^{n} p_i X^i\) where the \(p_i\) are the coefficient of the polynomial.

We can easily commit to a polynomial of degree \(n=2^{d}-1\) by setting \(a_i=p_i\) and computing the Merkle root of its coefficients. Proving an evaluation means that the prover wants to show to the verifier that \(p(z) = y\) for some \(z\). The prover can do this by sending the verifier all the \(p_i\) and the verifier computing that \(p(z)\) is indeed \(y\).

This is of course an extremely stupid polynomial commitment, but it will help us understand what the advantages of real polynomial commitments are. Let’s have a look at the properties:

- The commitment size is a single hash (the Merkle root). A cryptographic hash of sufficient security typically needs 256 bits, i.e. 32 bytes.
- To prove an evaluation, the prover needs to send all the \(p_i\), so the proof size is linear in the degree of the polynomial, and the verifier needs to do linear work (they need to evaluate the polynomial at the place \(z\) by computing \(p(z)=\sum_{i=0}^{n} p_i z^i\)).
- The scheme does not hide anything about the polynomial – the prover sends the whole polynomial in the clear, coefficient by coefficient.

Now let’s look at what the Kate scheme achieves on these metrics:

- The commitment size is one group element of an elliptic group that admits pairings. For example, with BLS12_381, that would be 48 bytes.
- The proof size,
*independent*from the size of the polynomial, is also always only one group element. Verification, also independent from the size of the polynomial, requires a two group multiplications and two pairings, no matter what the degree of the polynomial is. - The scheme
*mostly*hides the polynomial – indeed, an infinite number of polynomials will have exactly the same Kate commitment. However, it is not perfectly hiding: If you can guess the polynomial (for example because it is very simple or in a small set of possible polynomials) you can find out which polynomial was committed to.

Additionally, it is actually possible to combine the proof for any number evaluations in one group element. These properties make the Kate scheme very attractive for zero knowledge proof systems, such as PLONK and SONIC. But they also make it very interesting for a more mundane purpose and use it as a vector commitment, which we will come to below.

## On Elliptic curves and pairings

As mentioned in the prerequisites, I strongly recommend Vitalik Buterin’s post on elliptic curve pairings, it includes all the basics needed to understand this post – in particular finite fields, elliptic curves, and pairings.

Let \(\mathbb G_1\) and \(\mathbb G_2\) be two elliptic curves with a pairing \(e: \mathbb G_1 \times \mathbb G_2 \rightarrow \mathbb G_T\). Let \(p\) be the order of \(\mathbb G_1\) and \(\mathbb G_2\), and \(G\) and \(H\) be generators of \(\mathbb G_1\) and \(\mathbb G_2\). We will use a very useful shorthand notation

\[\displaystyle [x]_1 = x G \in \mathbb G_1 \text{ and } [x]_2 = x H \in \mathbb G_2\]for any \(x \in \mathbb F_p\).

### Trusted setup

Let’s assume we have a trusted setup, so that for some secret \(s\), the elements \([s^i]_1\) and \([s^i]_2\) are available to both prover and verifier for \(i=0, \ldots, n-1\).

One way to get this secret setup is to have an airgapped computer compute a random number \(s\), compute all the group elements \([s^i]_x\), and only send those elements (and not \(s\)) over a wire, and then burn that computer. Of course this is not a great solution because you would have to trust whoever operated that computer that they didn’t build a secret communication channel that tells them the secret \(s\).

In practice this is usually implemented via a secure multiparty computation (MPC), which allows creating these group elements by a group of computers in a way such that no single computer will know the secret \(s\), and all of them would have to collude (or be compromised) in order to reveal it.

Note one thing that is not possible: You can’t do this by just selecting a random group element \([s]_1\) (for which \(s\) is unknown) and compute the other group elements from it. It is impossible to compute \([s^2]_1\) without knowing \(s\).

Now, elliptic curve cryptography basically tells us that it’s impossible to find out what \(s\) actually is from the trusted setup group elements. It’s a number in \(\mathbb F_p\), but the prover cannot find the actual number. They can only do certain computations with the elements that they are given. So for example, they can easily compute things like \(c [s^i]_1 = c s^i G = [cs^i]_1\) by elliptic curve multiplication, and since they can add elliptic curve points, they can also compute something like \(c [s^i]_1 + d [s^j]_1 = (c s^i + d s^j) G = [cs^i + d s^j]_1\). In fact, if \(p(X) = \sum_{i=0}^{n} p_i X^i\) is a polynomial, the prover can compute

\[\displaystyle [p(s)]_1 = [\sum_{i=0}^{n} p_i s^i]_1 = \sum_{i=0}^{n} p_i [s^i]_1\]This is interesting – using this trusted setup, everyone can basically evaluate a polynomial at some secret point \(s\) that nobody knows. Except they don’t get the output as a natural number, they only get the elliptic curve point \([p(s)]_1 = p(s) G\), but it turns out that this is already really powerful.

## Kate commitment

In the Kate commitment scheme, the element \(C = [p(s)]_1\) is the commitment to the polynomial \(p(X)\).

Now you may ask the question: Could the prover (without knowing \(s\)) find another polynomial \(q(X) \neq p(X)\) that has the same commitment, i.e. such that \([p(s)]_1 = [q(s)]_1\)? Let’s assume that this were the case. Then it would mean that \([p(s) - q(s)]_1=[0]_1\), implying \(p(s)-q(s)=0\).

Now, \(r(X) = p(X)-q(X)\) is itself a polynomial. We know that it’s not constant because \(p(X) \neq q(X)\). It is a well-known fact that any non-constant polynomial of degree \(n\) can have at most \(n\) zeroes: This is because if \(r(z)=0\), then \(r(X)\) is divisible by the linear factor \(X-z\); since we can divide by one linear factor for each zero, and each division reduces the degree by one, so there can’t be more than \(n\).2

Since the prover doesn’t know \(s\), the only way they could achieve that \(p(s)-q(s)=0\) is by making \(p(X)-q(X)=0\) in as many places as possible. But since they can do that in at most \(n\) places, as we’ve just proved, they are very unlikely to succeed: since \(n\) is much smaller than the order of the curve \(p\), the probability that \(s\) will be one of the points they chose to make \(p(X)=q(X)\) will be vanishingly tiny. To get a feeling for this probability, suppose we use the largest trusted setups currently in existence, where \(n=2^{28}\), and compare it to the curve order \(p \approx 2^{256}\): The probability that any given polynomial \(q(X)\) that the attacker has crafted to agree with \(p(X)\) in as many points as possible – \(n=2^{28}\) points – results in the same commitment (\(p(s)=q(s)\)) will only be \(2^{28}/2^{256} = 2^{28-256} \approx 2 \cdot 10^{-69}\). That is an incredibly low probability and in practice means the attacker cannot pull this off.

### Multiplying polynomials

So far we have seen that we can evaluate a polynomial at a secret point \(s\), and that gives us a way to commit to one unique polynomial – in the sense that while there are many polynomials with the same commitment \(C=[p(s)]_1\), they are impossible to actually compute in practice (cryptographers call this *computationally binding*).

However, we are still missing the ability to “open” this commitment without actually sending the whole polynomial over to the verifier. In order to do this, we need to use the pairing. Above, we noticed that we can do some linear operations with the secret elements; for example, we can compute \([p(s)]_1\) as a commitment to \(p(X)\), and we could also add two commitments for \(p(X)\) and \(q(X)\) to make a combined commitment for \(p(X)+q(X)\): \([p(s)]_1+[q(s)]_1=[p(s)+q(s)]_1\).

What we’re missing is an ability to multiply two polynomials. If we can do that, we can use some cool properties of polynomials to achieve what we want. While elliptic curves themselves don’t allow this, luckily we can do it with pairings: We have that

\[\displaystyle e([a]_1, [b]_2) = e(G, H)^{(ab)} = [ab]_T\]where we introduce the new notation \([x]_T = e(G, H)^x\). So while we unfortunately can’t just multiply two field elements *inside* an elliptic curve and get their product as an elliptic curve element (this would be a property of so-called Fully Homomorphic Encryption or FHE; elliptic curves are only *additively homomorphic*), we can multiply two field elements if we commited to them in different curves (one in \(\mathbb G_1\) and one in \(\mathbb G_2\)), and the output is a \(\mathbb G_T\) element.

This gets us to the core of the Kate proof: Remember what we said about linear factors earlier: A polynomial is divisible by \(X-z\) if it has a zero at \(z\). It is easy to see that the converse is also true – if it is divisible by \(X-z\), then it clearly has a zero at \(z\): Being divisible by \(X-z\) means that we can write \(p(X)=(X-z) \cdot q(X)\) for some polynomial \(q(X)\), and this is clearly zero at \(X=z\).

Now let’s say we want to prove that \(p(z)=y\). We will use the polynomial \(p(X)-y\) – this polynomial is clearly zero at \(z\), so we can use the knowledge about linear factors. Let \(q(X)\) be the polynomial \(p(X)-y\) divided by the linear factor \(X-z\), i.e.

\[\displaystyle q(X) = \frac{p(X)-y}{X-z}\]which is equivalent to saying that \(q(X)(X-z) = p(X)-y\).

### Kate proofs

Now a Kate proof for the evaluation \(p(z)=y\) is defined as \(\pi=[q(s)]_1\). Remember the commitment to the polynomial \(p(X)\) is defined as \(C=[p(s)]_1\).

The verifier checks this proof using the following equation:

\[\displaystyle e(\pi,[s-z]_2) = e(C-[y]_1, H)\]Note that the verifier can compute \([s-z]_2\), because it is just a combination of the element \([s]_2\) from the trusted setup and \(z\) is the point at which the polynomial is evaluated. Equally they know \(y\) as the claimed value \(p(z)\), thus they can compute \([y]_1\) as well. Now why should this check convince the verifier that \(p(z)=y\), or more precisely, that the polynomial committed to by \(C\) evaluated at \(z\) is \(y\)?

We need to evaluate two properties: *Correctness* and *soundness*. *Correctness* means that, if the prover followed the steps as we defined, they can produce a proof that will check out. This is usually the easy part. *Soundness* is the property that they cannot produce an “incorrect” proof – they cannot trick the verifier into believing that \(p(z)=y'\) for some \(y'\neq y\).

Let’s start by writing out the equation in the pairing group:

\[\displaystyle [q(s) \cdot (s-z)]_T = [p(s) - y]_T\]*Correctness* should now be immediately apparent – this is just the equation \(q(X)(X-z) = p(X)-y\) evaluated at the random point \(s\) that nobody knows.

Now, how do we know it’s sound and the prover cannot create fake proofs? Let’s think of it in terms of polynomials. If the prover wants to follow the way we sketched out to construct a proof, they have to somehow divide \(p(X)-y'\) by \(X-z\). But \(p(z)-y'\) is not zero, so they cannot perform the polynomial division, as there will always be a remainder. So this clearly doesn’t work.

So then they can try to work directly in the elliptic group: What if, for some commitment \(C\), they could compute the elliptic group element

\[\displaystyle \pi_\text{Fake} =\frac{1}{s-z} (C-[y']_1)\]If they could do this, they could obviously just prove anything they want. Intuitively, this is hard because you have to multiply by something that involves \(s\), but you don’t know anything about \(s\). To prove it rigorously, you need a cryptographic assumption about proofs with pairings, the so-called \(q\)-strong SDH assumption 3.

### Multiproofs

So far we have shown how to prove an evaluation of a polynomial at a single point. Note that this is already pretty amazing: You can show that some polynomial that could be any degree – say \(2^{28}\) – at some point takes a certain value, by only sending a single group element (that could be \(48\) bytes, for example in BLS12_381). The toy example of using Merkle trees as polynomial commitments would have needed to send \(2^{28}\) elements – all the coefficients of the polynomial.

Now we will go one step further and show that you can evaluate a polynomial at *any* number of points and prove this, still using only one group element. In order to do this, we need to introduce another concept: The Interpolation polynomial. Let’s say we have a list of \(k\) points \((z_0, y_0), (z_1, y_1), \ldots, (z_{k-1}, y_{k-1})\): Then we can always find a polynomial of degree less than \(k\) that goes through all of these points. One way to see this is to use Lagrange interpolation, which give an explicit formula for this polynomial \(I(X)\):

Now let’s assume that we know \(p(X)\) goes through all these points. Then the polynomial \(p(X)-I(X)\) will clearly be zero at each \(z_0, z_1, \ldots, z_{k-1}\). This means that it is divisible by all the linear factors \((X-z_0), (X-z_1), \ldots (X-z_{k-1})\). We combine them all together in the so-called *zero polynomial*

Now, we can compute the quotient

\[\displaystyle q(X) = \frac{p(X) - I(X)}{Z(X)}\]Note that this is possible because \(p(X)-I(X)\) is divisible by all the linear factors in \(Z(X)\), so it is divisible by the whole of \(Z(X)\).

We can now define the Kate multiproof for the evaluations \((z_0, y_0), (z_1, y_1), \ldots, (z_{k-1}, y_{k-1})\): \(\pi=[q(s)]_1\) – note that this is still only one group element.

Now, to check this, the verifier will also have to compute the interpolation polynomial \(I(X)\) and the zero polynomial \(Z(X)\). Using this, they can compute \([Z(s)]_2\) and \([I(s)]_1\), and thus verify the pairing equation

\[\displaystyle e(\pi,[Z(s)]_2) = e(C-[I(s)]_1, H)\]By writing out the equation in the pairing group, we can easily verify it checks out the same way the single point Kate proof does:

\[\displaystyle [q(s)\cdot Z(s)]_T = [p(s)-I(s)]_T\]This is actually really cool: You can prove any number of evaluation – even a million – by providing just one group element! That’s only 48 bytes to prove all these evaluations!

## Kate as a vector commitment

While the Kate commitment scheme is designed as a polynomial commitment, it actually also makes a really nice vector commitment. Remember that a vector commitment commits to a vector \(a_0, \ldots, a_{n-1}\) and lets you prove that you committed to \(a_i\) for some \(i\). We can reproduce this using the Kate commitment scheme: Let \(p(X)\) be the polynomial that for all \(i\) evaluates as \(p(i)=a_i\). We know there is such a polynomial, and we can for example compute it using Lagrange interpolation: \(\displaystyle p(X) = \sum_{i=0}^{n-1} a_i \prod_{j=0 \atop j \neq i}^{n-1} \frac{X-j}{i-j}\)

Now using this polynomial, we can prove any number of elements in the vector using just a single group element! Note how much more efficient (in terms of proof size) this is compared to Merkle trees: A Merkle proof would cost \(\log n\) hashes to even just prove one element!

## Further reading

We are currently exploring the use of Kate commitments in order to achieve a stateless version of Ethereum. As such, I highly recommend searching for Kate in the ethresearch forums to find interesting topics of current research.

Another great read from here is Vitalik’s introduction to PLONK, which makes heavy use of polynomial commitments and the Kate scheme is the primary way this is instantiated.

-
https://www.iacr.org/archive/asiacrypt2010/6477178/6477178.pdf ↩

-
This result is often mis-quoted as fundamental theorem of algebra. But the fundamental theorem of algebra is actually the inverse result (only valid in algebraically closed fields), that over the complex numbers, every polynomial of degree \(n\) has \(n\) linear factors. The simpler result here unfortunately doesn’t come with a short catchy name, despite arguable being more fundamental to Algebra. ↩
