---
title: Foundations of Data Availability Sampling
source: https://eprint.iacr.org/2023/1079
author: Mathias Hall-Andersen, Mark Simkin, Benedict Wagner
date: 2023
---

# Foundations of Data Availability Sampling

Mathias Hall-Andersen $ ^{*1} $ Mark Simkin  $ ^{2} $ Benedict Wagner $ ^{\dagger 3,4} $

 $ ^{1} $ ZkSecurity

mathias@zksecurity.xyz

² Ethereum Foundation

mark.simkin@ethereum.org

³ CISPA Helmholtz Center for Information Security

benedikt.wagner@cispa.de

⁴ Saarland University

## Abstract

Towards building more scalable blockchains, an approach known as data availability sampling (DAS) has emerged over the past few years. Even large blockchains like Ethereum are planning to eventually deploy DAS to improve their scalability. In a nutshell, DAS allows the participants of a network to ensure the full availability of some data without any one participant downloading it entirely. Despite the significant practical interest that DAS has received, there are currently no formal definitions for this primitive, no security notions, and no security proofs for any candidate constructions. For a cryptographic primitive that may end up being widely deployed in large real-world systems, this is a rather unsatisfactory state of affairs.

In this work, we initiate a cryptographic study of data availability sampling. To this end, we define data availability sampling precisely as a clean cryptographic primitive. Then, we show how data availability sampling relates to erasure codes. We do so by defining a new type of commitment schemes which naturally generalizes vector commitments and polynomial commitments. Using our framework, we analyze existing constructions and prove them secure. In addition, we give new constructions which are based on weaker assumptions, computationally more efficient, and do not rely on a trusted setup, at the cost of slightly larger communication complexity. Finally, we evaluate the trade-offs of the different constructions.

Keywords: Data Availability Sampling, Commitments, Erasure Codes, Coupon Collector

## Part I Main Content

### Table of Contents

1 Introduction 3
1.1 Our Contributions 3
1.2 Related Work 5

2 Preliminaries 6

3 Definition of Data Availability Sampling 6
3.1 Basic Definition 6
3.2 Extensions 10

4 Overview of Constructions 11
4.1 From Codes and Commitments to Data Availability 11
4.2 Constructions of Erasure Code Commitments 12

5 Background on Coding Theory 12
5.1 Codes and Distance 13
5.2 Special Families of Codes 13

6 From Codes and Commitments to Data Availability Sampling 15
6.1 Erasure Code Commitments 15
6.2 Index Samplers 17
6.3 Construction of Data Availability Sampling Schemes 20

7 Commitments for Arbitrary Codes 23

8 Commitments for Tensor Codes 25

9 Commitments for Interleaved Codes 27
9.1 Construction from Hash Functions 27
9.2 Construction from Homomorphic Hash Functions 29

10 Evaluation and Comparison 31
10.1 Setting the Stage 31
10.2 Results 32

Appendix 38

## 1 Introduction

As cryptocurrencies continue to grow in popularity, their scalability is becoming more and more of an issue. While the VISA $ ^{1} $ payment system handles around 1700 transactions per second and claims to be able to handle up to 24000 transactions per second, the Ethereum blockchain can at most handle around 60 per second $ ^{2} $. Increasing the number of transactions that a blockchain can process is not an easy task. Transactions correspond to data that needs to be stored in a replicated fashion across a large number of independent validators. Thus, increasing the number of transactions means increasing the amount of data that needs to be stored and validated. At its core, blockchains aim to be distributed systems by the people for the people, which should not require any sort of trusted centralized authorities. As such, it is of crucial importance that regular individuals with reasonable amounts of computational power and memory are able to participate in the distributed systems that form the blockchain.

The data that comprises a blockchain can be seen as a sequence of blocks, where each block is composed of a small block header and a larger block content. To enable everyone to participate, clients can either join as so called full nodes that store and verify both block header and content or as light nodes that only store the headers. Light nodes can still use the functionalities that a blockchain provides as they can verify the information they receive is consistent with the corresponding block headers. However, they cannot verify whether all data associated with the block headers they store is valid. A block may, for instance, contain transactions that illegally attempt to spend the same coin twice. This would not be visible from inspecting the header alone. Therefore, light nodes rely on full nodes to inform them when an adversarial party tries to provide them with a header for malformed data. This is done via a mechanism known as fraud proofs.

Abstractly speaking, a fraud proof allows a full node to convince a light node that a block header and the corresponding block content do not form a valid block. To produce a fraud proof, the full node needs access to the malformed block's content, but the adversary may only publish a header and either partially or fully withhold the corresponding block content. While full nodes can convince light nodes that a block is malformed, they cannot convince them that a block's content is just not available on the network. For this reason, light nodes need a mechanism for determining whether the block content corresponding to some header is available or not. Naively, light nodes could attempt to download the full content in addition to the header, but this would completely defeat the whole point of being a light node in the first place. Thus, light nodes need some way of efficiently checking that block contents are fully available on the network without actually fully retrieving them.

Data availability sampling (DAS) schemes, first introduced by Al-Bassam et al. [ASBK21], aim to solve the problem outlined above. Informally speaking, such schemes allow a possibly malicious block proposer to encode a bit string data, such as a block's content, into a short commitment com and a codeword  $ \pi $. The commitment com is added to the block header and allows light nodes to verify the availability of the full encoded block content  $ \pi $ by randomly probing it in only a few positions. If enough light nodes successfully probed  $ \pi $, DAS ensures that the data is indeed fully available. Note that one light node alone cannot be convinced that the data is fully available, as it only queries a small part of the encoding and thus we need to talk about sufficiently large groups of light nodes.

Unfortunately, and despite its significant practical importance, there are no proper theoretical foundations for this new primitive. Existing works [ASBK21, YSL+20, SXKV21, NNT21] all discuss DAS schemes at an informal level without precise security definitions and without full proofs of security for the proposed constructions. For a cryptographic primitive that is planned to become a key component of major blockchains like Ethereum $ ^{3} $, this is a rather unsatisfactory state of affairs.

### 1.1 Our Contributions

In this work, we provide a comprehensive theoretical treatment of data availability sampling. We formally define what DAS schemes are, precisely state the security notions they should satisfy, prove existing constructions such as the one on the Ethereum roadmap secure, present new constructions, and finally compare all constructions in terms of concrete efficiency and discuss various trade-offs.

Formal Definitions. On an intuitive level, a DAS scheme should satisfy three main properties. First, it should be complete, meaning that verifiers $ ^{4} $ holding a valid commitment com and probing a valid encoding  $ \pi $, should successfully conclude that the encoded data is fully available. Second, it should be sound in the sense that enough successful probes to the encoding should allow for recovering some data bit string. Third, a DAS scheme should provide consistency, requiring that for a fixed but possibly malformed commitment com, one can recover at most one unique data bit string. We stress that DAS schemes ensure the full availability of some data, but they do not provide any guarantees about the structure or the contents thereof. A more detailed discussion and the main formal definitions themselves, along with several extensions are given in Section 3.

Constructions. We present multiple constructions, some being new, some being old but previously unproven. More concretely, we provide and analyze four constructions of DAS in this work:

• From Vector Commitments and SNARKs. This can be seen as the “trivial solution”.

• From Tensor Codes. This is the construction that is currently envisioned by Ethereum. It was previously lacking any kind of security proof. The fact that data is encoded via a tensor code and multiple polynomial commitments are combined makes the analysis non-trivial.

- in the Random Oracle Model. We present a new construction of DAS based solely on hash functions modeled as random oracles, and a new construction from homomorphic collision-resistant hash functions in the random oracle model. The analysis of these constructions turns out to be highly challenging. In particular the analysis of the latter one, requires a rather delicate rewinding argument.

In contrast to the Ethereum construction, our new constructions avoid a trusted setup and rely on arguably much simpler assumptions (e.g., no q-type assumption). In addition, our construction in the random oracle model is significantly more efficient as it requires no expensive public key operations. Moreover, we believe that constructing DAS from simple objects like hash functions is theoretically interesting.

As a building block that may be of independent interest, we introduce the notion of erasure code commitments. Roughly, these ensure that any set of openings belonging to the same commitment must be consistent with at least one codeword from the corresponding erasure code. Polynomial commitments, for example, can be seen as erasure code commitments for Reed-Solomon codes. We formalize the notion of erasure code commitments, study their properties, and explain how they are related to DAS.

Benchmarks. In addition to the theoretical parts of our work, we also investigate the concrete efficiency of all constructions presented in this work. We compare them with each other, but also with some “naive” approaches to DAS, with respect to metrics like commitment size, encoding size, number of probes needed per verifier, and number of probes needed for reconstruction of the data. Our experiments show that no one shoe fits all and that the choice of construction really depends on the context within which they are used. We provide a detailed analysis and do our best to elucidate the trade-off between the different constructions in Section 10.

On the Importance of This Work. The Ethereum blockchain currently has a market cap of 316 billion US dollars $ ^{5} $. This is an unbelievably large amount of money, with many everyday citizens having parts of their capital deposited in Ethereum's digital currency. Ensuring that these funds do not get lost or stolen, be it through a fault or an adversarial attack, is a prime example of what cryptography is ultimately for. A gold standard for modern applications involving cryptography is to have both formal definitions and proofs as well as security audits of corresponding protocol implementations. Ethereum is planning to deploy their first DAS techniques soon $ ^{6} $ and yet we barely have any formal foundations for this whole topic. We believe that our work fills an important gap in the literature just by formally defining the concept of DAS. In addition, we not only prove existing protocols secure, thereby making sure that Ethereum is not deploying a broken protocol, but we also provide new efficient protocols without requiring trusted setups. For this reason, we also believe that our work is of significant practical importance.

### 1.2 Related Work

DAS schemes are closely related to multiple already existing cryptographic primitives. In the following, we highlight some differences that make DAS a primitive of its own.

Proofs of Retrievability. The general concept of verifiers ensuring that some encoded data is fully available via a small number of probes is not new. Proofs of retrievability (PoR) [JK07, ABC+07, SW08, DVW09, CKW13, SSP13] consider a setting, where a trusted client encodes some data and then stores the encoding on an untrusted server. DAS schemes and PoRs are different in multiple ways. The most important difference is that in DAS, we do not assume the encodings to be generated in an honest manner. To deal with malicious encodings, we additionally require a consistency property as outlined above. While it is conceivable that some PoR constructions do achieve some form of consistency, they would only do so with very poor parameters as they are not designed to quickly detect malicious encodings. In PoR, a single server stores the encoding and may need to perform computations on it to respond to verifiers' queries. In our setting, the verifiers only need the ability to access arbitrary symbols of the encoding. In particular, this means that our codewords can be stored in a distributed fashion in a network and need not be fully stored on a single machine. Lastly, we consider retrieving back the data from the codeword as part of the functionality that DAS provides, whereas PoR consider it part of the security definition. As such, PoR schemes may use non-blackbox techniques to extract the original data, whereas our definitions require that the data is extractable from a sufficient number of independently performed probes.

Verifiable Information Dispersal. In the verifiable information dispersal setting [Rab89, CT05, NNT21] a potentially malicious party encodes a data bit string and stores the encoding in a distributed fashion among n servers of which at most t are corrupt. Upon receiving their share of the encoding, the servers interact with each other to determine whether the encoding they jointly store is valid or not. This setting inherently considers a non-adaptive adversary as the encoding needs to be fixed before the servers start interacting with each other. In our setting, we do not make any assumptions about how many servers there are, how many of them are corrupt, or how the encoding is stored in the network. We leave this up to the application that makes use of our DAS schemes, thus allowing for greater flexibility as the storage servers could for example change over time. Consequently, we also do not require any interaction between any servers, meaning that encoding is a non-interactive process. The security notions we formulate for DAS consider adaptive adversaries that are not bound to a specific malicious encoding, but that can instead just answer probe requests by the verifiers in an adaptive malicious fashion.

PCPP, IOPP and Proximity Testing. Intuitively, the concepts of (extractable) probabilistically checkable proofs of proximity (PCPP) [BGH+06] and its interactive generalization interactive oracle proofs of proximity (IOPP) [BCG+17] share features with our notion of erasure code commitments: namely a verifier which makes a small number of queries to the encoding. There are, however, some crucial differences. PCPPs and IOPPs require that openings are close to a valid codeword, but we require openings to be consistent with a valid codeword. Furthermore, our commitments rely on computational assumptions, whereas PCPPs and IOPPs are usually studied in the information-theoretic security setting and computational assumptions are only used to compile them into non-interactive arguments. We leave it up to future work to explore the connection between PCPP/IOPP literature [BGKS20] and erasure code commitments more closely.

Vector, Polynomial, and Functional Commitments. Our new notion of erasure code commitments is a generalization of both vector commitments  $ [CHL^{+}05, CFM08, LY10] $ and polynomial commitments  $ [KZG10, BDFG20, CHM^{+}20] $, but can (conceptually at least) be seen as a special case of functional commitments  $ [LRY16] $. Our constructions of erasure code commitments are simpler, computationally more efficient, and rely on weaker assumptions than the currently known constructions of functional commitments. In  $ [ADVZ21] $, the notion of erasure coding proof systems is introduced to construct verifiable information dispersal. Although their notion shares some similarities with our notion of erasure code commitments, the presentation in  $ [ADVZ21] $ is rather informal, especially when it comes to security definitions. We on the other hand provide precise security definitions and full proofs for all of our constructions.

Subsequent Work on DAS. Building on our framework, a subsequent work by Hall-Andersen, Simkin, and Wagner [HASW24] constructs a data availability sampling scheme without trusted setup from just hash functions (in the random oracle model). Their scheme improves upon our hash-based construction here in terms of both asymptotic and concrete efficiency. They establish a tight connection between

interactive oracle proofs of proximity [BCG $ ^{+} $17] and erasure code commitments. Using this connection, they construct an erasure code commitment from the FRI proof system [BBHR18]. Relying on the compiler provided in our work here, they obtain a data availability sampling scheme.

## 2 Preliminaries

In this section, we fix notation and preliminaries.

Notation. The set  $ [L] := \{1, \ldots, L\} \subseteq \mathbb{N} $ is the set of the first  $ L $ natural numbers. If  $ S $ is a finite set,  $ s \leftarrow s $  $ S $ means that  $ s $ is sampled uniformly at random from  $ S $. If  $ \mathcal{D} $ is a distribution,  $ x \leftarrow \mathcal{D} $ means that  $ x $ is sampled from  $ \mathcal{D} $. If  $ \mathcal{A} $ is a probabilistic algorithm, we write  $ s := \mathcal{A}(x; \rho) $ to indicate that  $ \mathcal{A} $ outputs  $ s $ on input  $ x $ with random coins  $ \rho $, and  $ s \leftarrow \mathcal{A}(x) $ means that  $ \rho $ is sampled uniformly at random. The notation  $ s \in \mathcal{A}(x) $ means that there are random coins  $ \rho $ such that  $ \mathcal{A} $ outputs  $ s $ on input  $ x $ with these coins  $ \rho $. For an algorithm  $ \mathcal{A} $, a string  $ s \in \Sigma^* $ over some alphabet  $ \Sigma $, and an integer  $ t \in \mathbb{N} $, the notation  $ y \leftarrow \mathcal{A}^{s,t}(x) $ indicates that  $ \mathcal{A} $ has  $ t $-time oracle access to  $ s $ on input  $ x $ and outputs  $ y $. That is,  $ \mathcal{A} $ can query  $ i $ and obtain the  $ i $th symbol  $ s_i \in \Sigma $ of  $ s $, for at most  $ t $ queries. Let  $ \mathcal{A} $ be an algorithm as above, and let  $ \mathcal{B} $ be a (potentially stateful) algorithm  $ \mathcal{B} $. We write  $ y \leftarrow \mathcal{A}^{\mathcal{B},t}(x) $ to indicate that the oracle queries of  $ \mathcal{A} $ are answered by  $ \mathcal{B} $. Further, we use the notation  $ (y_i)_{i=1}^{\ell} \leftarrow \text{Interact}[\mathcal{A}, \mathcal{B}]_{t,\ell}(x) $ to indicate that  $ \ell $ independent copies of  $ \mathcal{A} $ get  $ x $ as input, and have  $ t $-time oracle access to  $ \mathcal{B} $ (i.e., the oracle queries of  $ \mathcal{A} $ are answered by  $ \mathcal{B} $), and the  $ i $th copy outputs  $ y_i $ for each  $ i \in [\ell] $. Here,  $ \mathcal{B} $ can schedule the oracle queries of these  $ \ell $ copies in an arbitrary concurrently interleaved way. That is,  $ \mathcal{B} $ has access to an oracle  $ O_{\text{nextQ}} $, that on input  $ i \in [\ell] $ outputs the next query of the  $ i $th copy, given that  $ \mathcal{B} $ already submitted the response to the previous queries of that copy. All algorithms get the security parameter  $ \lambda $ in unary at least implicitly as input. An algorithm  $ \mathcal{A} $ is said to be PPT if its running time, denoted by  $ \mathbf{T}(\mathcal{A}) $, is bounded by a polynomial in its input. An algorithm  $ \mathcal{A} $ is said to be EPT if its expected running time, denoted by  $ \mathbf{ET}(\mathcal{A}) $, is bounded by a polynomial in its input. We write  $ \text{Pr}_{\mathbf{G}}[\mathbf{E}] \text{ or } \text{Pr}[\mathbf{E} \mid \mathbf{G}] \text{ to denote the probability that some event } E \text{ occurs in the experiment } \mathbf{G} $. Also, we denote the event that an experiment  $ \mathbf{G} $ outputs a bit  $ b $ by  $ \mathbf{G} \Rightarrow b $. A function  $ f $ is said to be negligible in its input  $ \lambda $, if  $ f \in \lambda^{-\omega(1)} $. Throughout,  $ \text{negl} $ always denotes a negligible function.

Cryptographic Building Blocks. For some constructions, we make use of common cryptographic building blocks, including vector commitments, non-interactive arguments, and homomorphic hash functions. We recall their formal definitions in Appendix A.

## 3 Definition of Data Availability Sampling

This section is dedicated to presenting our definition of data availability sampling. In Section 3.1, we define a data availability sampling scheme as a cryptographic primitive. Then, in Section 3.2, we introduce extensions for this basic definition.

### 3.1 Basic Definition

Here, we introduce our definition of a data availability sampling scheme.

Setting. We consider a scenario in which a proposer holds a large piece of data and wants to store this data within a network, possibly in a distributed way. This data could, for example, be a block that should be published in a peer-to-peer network running a blockchain. In addition, to the proposer and the network, there are parties with limited resources, called (light) clients or verifiers. They can only download small headers, containing information about the corresponding data, but are not capable of downloading the entire data itself. They want to verify that the data is available within the network. To do so, light clients can issue queries to the network. Our formal definition of data availability sampling models such as scenario.

Syntax. We give a schematic overview of our syntax in Figure 1. Suppose the proposer holds a piece of data data to be distributed. In our syntax, the proposer runs an algorithm Encode with input data to obtain a commitment com and an encoding  $ \pi $ of the data. We assume that every party downloads com. For example, we may think of com to be part of a block header. We do not explicitly model how  $ \pi $ is being stored. As our security notions treat  $ \pi $ as being fully controlled by the adversary. This means

<div style="text-align: center;"><img src="images/HAS23 - Fig 1 - Overview of the syntax of a data availability sampling scheme.jpg" alt="Image" width="74%" /></div>


<div style="text-align: center;"><div style="text-align: center;">Figure 1: Overview of the syntax of a data availability sampling scheme. All algorithms get system parameters par ← Setup(1^λ) as input. Algorithm Encode encodes data into an encoding π. Multiple clients (V₁, V₂) can then query this encoding. From enough transcripts, data can be reconstructed using algorithm Ext.</div> </div>


any way of storing  $ \pi $ is covered. For example, we may think of  $ \pi $ as being stored in a distributed way on nodes within a network. We model clients by two algorithms  $ V_1 $ and  $ V_2 $, where  $ V_1 $ can probabilistically query positions of the encoding  $ \pi $. The resulting transcript tran, which contains all queries and responses, is then input into  $ V_2 $, which deterministically outputs 0 (for reject) or 1 (for accept). We split the client into these two algorithms to talk about (accepting) transcripts explicitly. Finally, we define an algorithm Ext that extracts the original data from enough of these transcripts. The idea is that clients share their transcripts with others and, once a party has enough transcripts, it can run Ext to get data.

Properties. We now turn to the properties these algorithms should satisfy. Our completeness definition states that everything works as expected, given that all algorithms are executed honestly. In our concrete case, this means that if some data data is encoded honestly, then all clients will accept, and Ext outputs data when run on enough transcripts.

From a security perspective, we would like to ensure that, if clients accept, then data should be available. We capture this formally in our definition of soundness. To understand this definition, we need to make the concept of data being available more precise. We do this using the extraction algorithm Ext that we defined. We can think of data as being available if Ext can extract something, and it does not output ⊥. With this in mind, soundness means that if enough clients accept, then Ext can extract something from their transcripts. Notably, we have to define this in the presence of a malicious encoding π that is fully controlled by an adversary⁷. The adversary can schedule the queries that the clients issue and it can answer these queries adaptively. This also shows why we require that enough clients accept and not only that one client accepts. An adversary could, for example, answer the queries of one client honestly and not respond anything to any of the other clients. Clearly, there is no hope to extract anything from only one accepting transcript, as it is shorter than the data.

The definitions of completeness and soundness alone are not meaningful by themselves yet, since Ext could just output some default value when it fails to reconstruct. To be able to meaningfully say that some data is available, we need to ensure that we will always recover the same data, no matter where the transcripts come from. We capture this wish by defining consistency. This notion means that whenever Ext is run twice on two (possibly intersecting) sets of transcripts and the same commitment com, and it outputs data₁ ≠ ⊥ and data₂ ≠ ⊥, respectively, then data₁ = data₂, i.e., the extracted data is consistent. In other words, the data availability sampling scheme bootstraps consensus on the commitment com to consensus on data. Furthermore, it should be noted that for our consistency notion we let the adversary output the transcripts, which makes it very strong and flexible. We are now ready to present the complete formal definition.

Definition 1 (Data Availability Sampling Scheme). A data availability sampling scheme (DAS) with data alphabet  $ \Gamma $, encoding alphabet  $ \Sigma $, data length  $ K \in \mathbb{N} $, encoding length  $ N \in \mathbb{N} $, query complexity  $ Q \in \mathbb{N} $, and threshold  $ T \in \mathbb{N} $ is a tuple DAS = (Setup, Encode, V, Ext) of algorithms with the following syntax:

• Setup $ (1^{\lambda}) \rightarrow \text{par} $ is a PPT algorithm that takes as input the security parameter, and outputs system parameters par. All algorithms get par implicitly as input.

- Encode(data) → (π, com) is a deterministic polynomial time algorithm that takes as input data data ∈ Γ^K and outputs an encoding π ∈ Σ^N and a commitment com.

•  $  \mathbf{V} = (\mathbf{V}_1, \mathbf{V}_2)  $ is a pair of algorithms, where

- \mathrm{V}_{1}^{\pi,Q}(\mathrm{com}) \rightarrow \mathrm{tran} \text { is a PPT algorithm that has } Q\text {-time oracle access to an encoding } \pi \in \Sigma^{N},

gets as input a commitment  $ \mathrm{com} $, and outputs a transcript  $ \mathrm{tran} $, containing the  $ Q $ queries to  $ \pi $ and the respective responses.

− V₂(com, tran) → b is a deterministic polynomial time algorithm that takes as input a transcript tran, and outputs a bit  $ b \in \{0, 1\} $.

• Ext(com, tran₁, ..., tranₚ) → data/⊥ is a deterministic polynomial time algorithm that takes as input a commitment com, a list of transcripts tranₙ, and outputs data data ∈ Γᵣ or an abort symbol ⊥.

We require that the following properties are satisfied:

- Completeness. For any par ∈ Setup(1^λ) and any integer ℓ = poly(λ) with ℓ ≥ T, and all data ∈ Γ^K, we have

 $$ \begin{aligned}Pr\left[\forall i\in[\ell]:b_{i}=1\land data^{\prime}=data\left|\begin{array}{l}(\pi,com):=Encode(data),\\\forall i\in[\ell]:tran_{i}\leftarrow\mathsf{V}_{1}^{\pi,Q}(com),\\b_{i}:=\mathsf{V}_{2}(com,tran_{i}),\\data^{\prime}:=Ext(com,tran_{1},\ldots,tran_{\ell})\end{array}\right.\right]\geq1-negl(\lambda).\end{aligned} $$

• Soundness. For any stateful PPT algorithm  $ \mathcal{A} $ and any integer  $ \ell = \text{poly}(\lambda) $ with  $ \ell \geq T $, the following advantage is negligible:

 $$ \begin{aligned}Adv_{\mathcal{A},\ell,DAS}^{sound}(\lambda):=\Pr\left[\forall i\in[\ell]:b_{i}=1\wedge data^{\prime}=\perp\left|\begin{array}{l}\text{par}\leftarrow Setup(1^{\lambda}),\text{com}\leftarrow\mathcal{A}(\text{par}),\ $ \text{tran}_{i})_{i=1}^{\ell}\leftarrow Interact[V_{1},\mathcal{A}]_{Q,\ell}(\text{com}),\\\forall i\in[\ell]:b_{i}:=\mathsf{V}_{2}(\text{com},\text{tran}_{i}),\\\text{data}^{\prime}:=\text{Ext}(\text{com},\text{tran}_{1},\ldots,\text{tran}_{\ell})\end{array}\right.\right].\end{aligned} $$

• Consistency. For any PPT algorithm A and any  $ \ell_1, \ell_2 = \text{poly}(\lambda) $, the following advantage is negligible:

 $$ \begin{aligned}Adv_{\mathcal{A},\ell_{1},\ell_{2},\mathrm{D A S}}^{\mathrm{c o n s}}(\lambda):=\operatorname{P r}\left[\begin{array}{c}\text{data}_{1}\neq\perp\\\wedge\quad\text{data}_{2}\neq\perp\\\wedge\quad\text{data}_{1}\neq\text{data}_{2}\end{array}\right.\left|\begin{array}{l}\text{par}\leftarrow\operatorname{S e t u p}(1^{\lambda}),\ $ \operatorname{c o m},(\operatorname{t r a n}_{1,i})_{i=1}^{\ell_{1}},(\operatorname{t r a n}_{2,i})_{i=1}^{\ell_{2}})\leftarrow\mathcal{A}(\text{par}),\\\text{data}_{1}:=\operatorname{E x t}(\operatorname{c o m},\operatorname{t r a n}_{1,1},\ldots,\operatorname{t r a n}_{1,\ell_{1}}),\\\text{data}_{2}:=\operatorname{E x t}(\operatorname{c o m},\operatorname{t r a n}_{2,1},\ldots,\operatorname{t r a n}_{2,\ell_{2}})\end{array}\right].\end{aligned} $$

Discussion. We want to highlight a few aspects of our definition. First, note that we require Encode to be deterministic. At a first glance, this may seem to be too restrictive, as encoding could make use complex cryptographic tools, e.g., a (succinct) non-interactive argument [BFM88, Kil92, Gro16]. However, observe that in the context of data availability sampling, we do not require any privacy properties, e.g., zero-knowledge, from these tools. If any, we require their correctness and soundness properties, which hold even if the randomness is fixed, i.e., we make these schemes deterministic. Second, one could wonder why we do not require that re-encoding data leads to the same commitment com in our soundness definition. Here, we observe that this is not satisfied by natural constructions based on perfectly-hiding commitments in style of [Ped92, KZG10]. Namely, an adversary could run (\pi,\mathrm{com}) := \mathrm{Encode}(\mathrm{data}), rerandomize  $ \mathrm{com} $ (and adjust \pi if needed), and then behave honestly. Third, we emphasize that our definition of soundness and consistency allows the adversary to be fully adaptive. That is, the adversary can schedule the queries of clients and answer them in an adaptive way. This is much stronger than what is present in the informal security goals stated by previous works, where the adversary first decides which parts of the encoding should be available, and then clients start probing. We believe that such strong adaptive security notions

are more appropriate for real-world settings, where independent verifiers asynchronously query parts of an encoding that is stored in a distributed fashion among multiple possibly malicious nodes.

Efficiency Measures. When constructing data availability sampling schemes, there are several properties we aim to optimize. It is of primary interest to minimize the computational and communication complexity of clients. In particular, we would like to minimize the computational complexity of V, the communication complexity  $ \log N + \max_{s \in \Sigma} |s| $ per query $ ^8 $, and the size of commitments  $ \left|\text{com}\right| $. Additionally we would also like to minimize the encoding size  $ |\pi| $ and the computational complexity of  $ \text{Encode} $, i.e., the effort of the parties encoding the data and storing the encoding. Lastly, we want to minimize the number T of transcripts that are needed to reconstruct the data. The smaller the number T, the more “meaningful” is each verifier’s transcript, when it comes to establishing the availability of some data. Note that minimizing T and the query complexity per client Q at the same time also minimizes the total communication complexity that is needed to reconstruct the data.

Strawman Solutions. At first sight, it may seem easy to construct DAS schemes. Let us discuss a few natural, but failing attempts. Firstly, we can easily achieve query complexity  $ Q = 1 $ and threshold  $ T = 1 $ by setting  $ \Sigma := \Gamma^K $, i.e., by considering the full data as a single symbol and letting every client download it in full. Obviously, this solution has a terrible communication complexity per client query. Alternatively, one can also make this communication complexity small by storing the whole data as part of the commitment com, which would be equally undesirable. A slightly more intelligent approach may be to store the root of a Merkle tree [Mer88], computed over the data, as the commitment and let the verifiers query random leaves in the tree. This solution has a small commitment size and a small communication complexity per query, but the required number of transcripts  $ T $ for reconstructing the data with high probability would be very large (cf. Example 5). Intuitively,  $ T $ being very large corresponds to each client individually not really being very much convinced about the availability of the full data. Lastly, one could try and use ideas from the proofs of retrievability literature and first encode the data with an erasure code, before computing a Merkle tree over the symbols of the code. Note however, that the encoding may be done in a malicious way. For instance, the first half of the leaves could correspond to the first half of a valid codeword encoding data, whereas the second half of the leaves could correspond to the second half of a codeword encoding data' with data  $ \neq $ data', which would allow an adversary to violate the consistency requirement. To prevent this attack, one would need to pick a large value for  $ Q $, which would then render the solution inefficient.

Subset-Soundness. We imagine that clients send the transcripts of their interaction to the network. Then any node that collects enough of these transcripts should be able to reconstruct data from these transcripts, according to soundness. However, under the realistic assumption that an adversary controls parts of the network, it may adaptively drop some of the transcripts after seeing them. We extend our basic soundness definition to cover this attack scenario, and call the resulting notion subset-soundness. In this notion, we run the basic soundness experiment, but additionally let the adversary select a subset of the transcripts from which we try to reconstruct data. In other words, we let the adversary drop a limited number of transcripts of its choice. After defining subset-soundness, we show that it is implied by standard soundness for certain parameter ranges.

Definition 2 (Subset-Soundness). Let DAS = (Setup, Encode, V = (V₁, V₂), Ext) be a data availability sampling scheme. We say that DAS satisfies (L,  $ \ell $)-subset-soundness, if for any stateful PPT algorithm A, the following advantage is negligible:

 $$ \begin{aligned}&Adv_{\mathcal{A},L,\ell,\mathrm{D A S}}^{\mathrm{sub-sound}}(\lambda):=\operatorname{P r}\left[\begin{array}{l}\forall j\in[\ell]:b_{i_{j}}=1\wedge\mathrm{d a t a}^{\prime}=\perp\begin{array}{l}\left|\begin{array}{l}\operatorname{p a r}\leftarrow\operatorname{S e t u p}(1^{\lambda}),\operatorname{c o m}\leftarrow\mathcal{A}(\operatorname{p a r}),\ $ \operatorname{t r a n}_{i})_{i=1}^{L}\leftarrow\operatorname{I n t e r a c t}\left[\mathrm{V}_{1},\mathcal{A}\right]_{Q,L}(\operatorname{c o m})\end{array}\right.\\\left|\begin{array}{l}\forall i\in[L]:b_{i}:=\mathrm{V}_{2}(\operatorname{t r a n}_{i}),\ $ i_{j})_{j=1}^{\ell}\leftarrow\mathcal{A}(\operatorname{t r a n}_{1},\ldots,\operatorname{t r a n}_{L}),\\\mathrm{d a t a}^{\prime}:=\operatorname{E x t}(\operatorname{c o m},\operatorname{t r a n}_{i_{1}},\ldots,\operatorname{t r a n}_{i_{\ell}})\end{array}\right.\end{array}\right].\end{aligned} $$

Lemma 1. Let DAS = (Setup, Encode, V = (V₁, V₂), Ext) be a data availability sampling scheme with threshold T ∈ N, and let L, ℓ ∈ N be such that  $ L \leq \text{poly}(\lambda) $ and  $ \ell \geq T $. Then, DAS satisfies (L, ℓ)-subset-soundness. More specifically, for any stateful PPT algorithm A, there is a stateful PPT algorithm B with  $ \mathbf{T}(\mathcal{B}) \approx \mathbf{T}(\mathcal{A}) $ and

 $$ \mathrm{A d v}_{\mathcal{A},L,\ell,\mathrm{D A S}}^{\mathrm{s u b-s o u n d}}(\lambda)\leq\binom{L}{\ell}\cdot\mathrm{A d v}_{\mathcal{A},\ell,\mathrm{D A S}}^{\mathrm{s o u n d}}(\lambda). $$

Proof. The proof is trivial via a guessing argument, i.e. the reduction  $ \mathcal{B} $ simply guesses the subset that will be chosen by  $ \mathcal{A} $.

Necessity of Assumptions. Naturally, one can ask whether it is possible to construct a (non-trivial) data availability sampling scheme satisfying our notions. Throughout this work, we will show several constructions and therefore show that it is possible. However, all constructions rely on computational assumptions or idealized models, e.g., the random oracle model. Again, one can ask whether this is necessary, or whether one can construct data availability sampling schemes without any cryptographic assumption. The result is negative: we show that any non-trivial scheme, i.e. where the commitment is smaller than the data, implies a collision-resistant hash function. The hash function is induced by the mapping from data to com via algorithm Encode. We formally show this in Appendix C.1.

### 3.2 Extensions

Here, we informally introduce two extensions of our basic definition of data availability sampling schemes. We postpone a formal definition to Appendices C.2 and C.3.

Repairability. Ideally, a data availability sampling scheme allows to reconstruct data even if small parts of the encoding are broken or lost. In this case, it is natural to ask whether one can return from such a damaged state to a stable state by repairing the encoding. More precisely, we would like to have a way to recover an encoding from a set of transcripts with which we can continue as if it was the original encoding. Importantly, it should work with the original commitment. This enables a transparent repair on the fly without notifying every party about the change, and without updating the commitment. For example, one problem when changing the commitment is that we would have to convince every party that the new commitment commits to the same data as the old one. We define an extension of data availability with such a repairability feature by requiring the existence of an algorithm Repair. On input a commitment com and a set of transcripts, Repair outputs a new encoding  $ \bar{\pi} $. Informally, we expect  $ \bar{\pi} $ to be compatible with the commitment com, and function as the original encoding, assuming that Repair obtained enough accepting transcripts. We make this formal by introducing the notion of repair liveness. In this notion, we let an adversary output a com and interact with clients as in the subset-soundness notion, i.e., clients query an encoding provided adaptively by the adversary. Then, we repair from a subset of the resulting transcripts by running algorithm Repair. Finally, we expect that all clients accept when querying this repaired encoding with com as input. If this does not hold, the adversary breaks repair liveness.

Example 1 (Accountability for Trivial Repairability). If we were to naively implement repairability, we would extract the data from a sufficient number of transcripts and recompute an encoding. Note that this approach will not work in general, because there is no guarantee that the new encoding is compatible with the old commitment. Especially, an adversary might be able to compute a functioning pair of commitment and encoding different from an honestly computed pair for some data. However, when this trivial approach fails, it produces a certificate that the original commitment was computed incorrectly. Namely, by having the proposer sign the commitment, a set of transcripts from which reconstruction is possible but the re-encoding of the data does not yield the original commitment forms a publicly verifiable certificate that the original encoding and commitment was not computed honestly. This observation has possible applications in scenarios where fallback to the trivial data availability scheme is feasible. For example, in cryptocurrency applications, the full data can be posted on the chain to repair and the malicious encoders deposit can be forfeited to cover the cost of posting the full data.

Local Accessibility. A natural question to ask is whether one needs to reconstruct the entire data, even if one is only interested in small parts of it. Concretely, say a client is interested in learning the ith symbol of the encoded data. We enhance our basic definition of data availability sampling schemes with such a local accessibility feature by introducing an algorithm Access. Roughly, it recovers a specific symbol of the encoded data by querying the encoding. Namely, it gets as input a commitment com and an index  $ i \in [K] $, has oracle access to an encoding, and outputs a symbol d, which should be understood as being the ith symbol of the encoded data data. Crucially, we need to ensure that this new way of obtaining (parts of) the data does not introduce inconsistencies. Thus, we introduce the notion of local access consistency, which states that whatever Access outputs is consistent with data extracted using a

set of transcripts. More precisely, for any index  $ i \in [K] $, we let the adversary output a commitment com and a set of transcripts. Then, we run Access on input com, i to obtain a symbol d. The queries of Access are answered by the adversary. Further, we run the extractor Ext on input com and the set of transcripts to extract data data. We require that d is the ith symbol of data, given that both are not  $ \perp $.

Example 2 (Trivial Local Accessibility). There is a simple way to make every data availability sampling scheme locally accessible. Namely, every data availability sampling scheme with query complexity  $ Q \in \mathbb{N} $ and threshold  $ T \in \mathbb{N} $ is locally accessible with query complexity  $ L = QT $, i.e., Access makes QT queries to access one symbol of the data. This is because Access can simply run T clients internally and then extract from the resulting transcripts. The clear drawback of this trivial approach is that Access has a huge query complexity. Ideally, we aim for a way that lets us access any symbol with query complexity significantly smaller than QT, e.g., only with one query.

## 4 Overview of Constructions

In this section, we give an overview of our constructions of data availability sampling. We first introduce a generic framework of constructing data availability sampling from erasure codes and associated commitment schemes with suitable properties (Section 6). Equipped with this framework, we then focus on constructing such commitment schemes for several erasure codes (Sections 7 to 9). Finally, we compare instantiations of these constructions in terms of efficiency (Section 10). In this overview, we explain our framework and the constructions.

### 4.1 From Codes and Commitments to Data Availability

We construct data availability schemes by introducing the new notion we call  $ \underline{\text{erasure code commitments}} $. In the following, we first explain what erasure code commitments are. Then, we explain how to turn them into data availability sampling schemes.

Erasure Code Commitments. Erasure code commitments are binding vector commitments with the additional property that any set of openings produced by a computationally bounded adversary is consistent with at least one codeword from the erasure code. We call this additional notion code-binding. The existing notion of polynomial commitments is a special case for the Reed-Solomon code, although we do not require extraction of the commitment which is often required in applications of polynomial commitments, nor do we require hiding. Similarly vector commitments are erasure code commitments for the trivial erasure code, mapping every message to itself. In Section 6.1, we formally define erasure code commitments. Additionally, we also define a variety of additional security notions for these commitments and study their relations. We are confident in the usefulness of this natural generalization of polynomial commitments beyond data availability schemes.

Data Availability from Erasure Code Commitments. From erasure code commitments we follow an intuitive avenue to arrive at a data availability scheme:

• Encoding. The encoding algorithm Encode(data) first applies the erasure code to data obtaining a codeword, and then commits to the codeword using an erasure code commitment, which forms the data availability commitment com. The resulting encoding  $ \pi $ consists of the symbols of the codeword and their corresponding openings of com.

• Clients. The first part of the client  $ \mathbf{V}_1^{\pi,Q}(\text{com}) $ relies on a randomized index sampler which returns a set of indices in the codeword. The client  $ \mathbf{V}_1 $ then queries the provided indexes of  $ \pi $, the list of responses forms the tran. The second part of the client  $ \mathbf{V}_2(\text{com},\text{tran}) $ verifies all the erasure code commitment openings obtained by  $ \mathbf{V}_1 $ against com.

• Extraction. Given enough accepting transcripts, one can then extract the encoded data (i.e., run algorithm Ext), assuming the transcripts contain sufficiently many of the symbols of the codeword.

The details on our compiler from erasure code commitments to data availability sampling are given in Section 6.3. It is clear that the parameters of the data availability sampling scheme depend on the parameters of the erasure code. In addition, the choice of the index sampler (e.g., sampling uniformly with replacement or without replacement) influences how many transcripts we need to collect enough

distinct symbols of the codeword with high probability. To capture this, we define the quality of an index sampler. We study different index samplers and their quality in Section 6.2.

### 4.2 Constructions of Erasure Code Commitments

When constructing data availability sampling schemes, our framework introduced above allows us to concentrate on erasure codes, erasure code commitments, and index samplers. Here, we give a brief overview of our erasure code commitments.

Generic Construction. We snow that one can generically construct erasure code commitments for any erasure code from vector commitments and succinct arguments of knowledge. Namely, this is done by proving that a vector commitment contains a codeword using a succinct argument of knowledge. The code commitment consists of the vector commitment and the succinct proof, and the proof is verified by clients. While this construction is far from being practical in general, it serves as a template for other constructions. We formally define and analyze this generic construction in Section 7.

Tensor Construction (Ethereum Construction). Ethereum has proposed a data availability scheme which can be phrased as an erasure code commitment for the tensor code of two Reed-Solomon codes: The data is arranged into a square  $ k \times k $ matrix, then every row is encoded using a Reed-Solomon code, yielding a  $ k \times n $ matrix, finally every column is encoded using a Reed-Solomon code yielding a  $ n \times n $ matrix. A commitment is formed by committing to each column individually using a polynomial commitment (i.e., a code commitment for the Reed-Solomon code), then checking consistency of the rows by exploiting the linear homomorphism of the commitment similar to Feldman secret sharing [Fel87]. We provide a formal description and analysis of this scheme for the tensor code of arbitrary codes in Section 8.

Hash-Based Construction. We provide a new construction for interleaved linear codes from random oracles, which is partially inspired by the Ligero proximity test [AHIV17]. Encoding and committing is done as follows: The message is first interpreted as a  $ k \times k $ matrix  $ \mathbf{M} \in \mathbb{F}^{k \times k} $ over a finite field  $ \mathbb{F} $. Each row is encoded independently using a linear code  $ \mathcal{C} $, leading to a  $ k \times n $ matrix  $ \mathbf{X} \in \mathbb{F}^{k \times n} $. The columns are now treated as the symbols of the interleaved code. To commit to such a codeword, the encoder commits to each column individually by hashing it with a collision-resistant hash function, producing  $ n $ hashes  $ h_1, \ldots, h_n $. Including these hashes in the commitment already ensures position-binding. To ensure code-binding, i.e., that openings are always consistent with the code, the hashes are fed into a random oracle, which returns a challenge vector $ ^9 $  $ \mathbf{r} \in \mathbb{F}^k $. The encoder then computes the linear combination  $ \mathbf{w} = \mathbf{r}^\top \mathbf{X} $ of the rows and includes  $ \mathbf{w} $ in the commitment. Note that the resulting  $ \mathbf{w} $ always forms a codeword in the code  $ \mathcal{C} $, which is checked by the clients as we will describe below. For any fixed set  $ \mathcal{I} \subseteq [n] $ of positions that an adversary may now open inconsistently with the code, we could in principle argue that the verification only passes with negligible probability. However, in the notion of code-binding, the adversary is allowed to freely choose this set  $ \mathcal{I} \subseteq [n] $. It turns out that, if the committed  $ \mathbf{X} $ is far from the code, then we need a too wasteful union bound over the different choices of  $ \mathcal{I} $. To solve this issue, we need to add a proximity test: Using another random oracle, a random set of indices  $ J \subseteq [n] $ is determined, and the encoder has to add the columns  $ \{\mathbf{X}_j\}_{j \in J} $ to the commitment. The encoding  $ \pi $ is simply the codeword  $ \mathbf{X} $ of the interleaved code. To be explicit, a coordinate  $ \mathbf{X}_j $ of the encoding is verified by checking  $ \mathbf{w}_j = \mathbf{r}^\top \mathbf{X}_j $ and  $ h_j = \mathsf{H}(\mathbf{X}_j) $. In addition, the openings in  $ J $ are checked in a similar manner and it is verified that  $ \mathbf{w} $ is in the code  $ \mathcal{C} $. An advantage of this scheme is that we can implement it over small fields for computational efficiency, and the very small opening overhead. Namely, the opening proof of a position is simply the symbol itself. On the other hand, the commitment is large, both concretely and asymptotically. We present the construction in detail in Section 9.1.

Construction from Homomorphic Hashing. The hash-based construction for interleaved codes can be optimized by relying on linearly homomorphic hashes, which improves both the concrete and asymptotic size of the commitment. The description of this construction is provided in Section 9.2.

## 5 Background on Coding Theory

In this section, we discuss background about coding theory. We introduce notation, definitions, and basic facts about some specific codes. Looking ahead, we will show how codes relate to data availability

sampling in subsequent sections.

### 5.1 Codes and Distance

We will now introduce codes and their properties. Informally, a code allows to deterministically encode a message over some alphabet  $ \Gamma $ into a codeword over some alphabet  $ \Lambda $.

Erasure Codes. An erasure code has the additional property that any $t$ symbols of the codeword are sufficient to reconstruct the message, for some $t \in \mathbb{N}$. The parameter $t$ is called the reception efficiency of the code. In this work, we only consider erasure codes. Before we give the formal definition, we highlight that throughout the paper, we assume that the encoding and the reconstruction algorithm are efficiently computable. To make this assumption formal, we would have to talk about families of codes. We opt for a concise and readable notation instead of doing this.

Definition 3 (Erasure Code). Let  $ k, n, t \in \mathbb{N} $ be natural numbers and  $ \Gamma $,  $ \Lambda $ be sets. A function  $ \mathcal{C} $:  $ \Gamma^k \to \Lambda^n $ is an erasure code with alphabets  $ \Gamma $,  $ \Lambda $, message length  $ k $, code length  $ n $, and reception efficiency  $ t $, if there is a deterministic algorithm  $ \text{Reconst} $, such that for any  $ m \in \Gamma^k $, and any  $ I \subseteq [n] $ with  $ |I| \geq t $ we have  $ \text{Reconst}((\hat{m}_i)_{i \in I}) = m $ for  $ \hat{m} := \mathcal{C}(m) $. We say that  $ \text{Reconst} $ is the reconstruction algorithm of  $ \mathcal{C} $, and assume that  $ \text{Reconst} $ outputs  $ \perp $ if its input is not consistent with any codeword in  $ \mathcal{C} $ or if it gets less than  $ t $ symbols as input. For convenience, we sometimes treat an erasure code  $ \mathcal{C} $ as a subset  $ \mathcal{C} \subseteq \Lambda^n $, where we implicitly mean the image of  $ \mathcal{C} $, i.e.,  $ \mathcal{C}(\Gamma^k) $. We may then write  $ x \in \mathcal{C} $ to indicate that  $ x $ is a codeword.

Distance. In coding theory, we are often interested in the distance between words. Naturally, the metric we consider is the Hamming metric. Concretely, for two strings $x,y$ over the same alphabet and with the same length $L$, we define $d(x,y)$ to be the number of positions $i\in[L]$ for which $x_{i}\neq y_{i}$. An important attribute of a code is its minimum distance, which we define next.

Definition 4 (Minimum Distance). Let $\mathcal{C}:\Gamma^k \to \Lambda^n$ be an erasure code. The (absolute) minimum distance $d$ of $\mathcal{C}$ is defined as

 $$ d:=\min_{m_{1}\neq m_{2}\in\Gamma^{k}}d\left(\mathcal{C}(m_{1}),\mathcal{C}(m_{2})\right). $$

Further, we introduce the notion of column-wise distance of matrices in  $ \Lambda^{\ell \times n} $ for some  $ \ell \in \mathbb{N} $. This is just the hamming distance when the matrices are treated as strings over  $ \Lambda^\ell $, i.e., every column is interpreted as a symbol. To make this explicit when needed, we write  $ d_{col}(\mathbf{X}, \mathbf{X}^\ell) $ for two such matrices  $ \mathbf{X}, \mathbf{X}^\ell $. Moreover, we extend the notion of distance to sets. Concretely, for a set of strings  $ S \subseteq \Lambda^\ell $ over some alphabet  $ \Lambda $ and a string  $ x \in \Lambda^\ell $, we define  $ d(S, x) = d(x, S) := \min_{s \in S} d(s, x) $. The same can be done for the column-wise distance. Finally, we highlight an important property of the minimum distance  $ d $. Namely, if  $ \mathcal{C} $ is an erasure code with minimum distance  $ d $ and  $ d(\mathcal{C}, x) \leq \lfloor (d - 1)/2 \rfloor $ for some string  $ x $, then there is a unique codeword  $ c \in \mathcal{C} $ which is closest to  $ x $. We may say that  $ x $ is within unique decoding distance of  $ \mathcal{C} $.

### 5.2 Special Families of Codes

In this section, we introduce some families of codes that will be of interest for this work.

Systematic Encoding. We say that a code C has a systematic encoding, if the message m is contained in the codeword  $ \mathcal{C}(m) $. Such a systematic encoding makes it easy to retrieve (parts of) the message from the codeword. In our context, we will use this property to extend the basic functionality of data availability sampling with local accessibility. We slightly generalize the standard definition of a systematic encoding. One reason for this generalization is that messages and codewords are over different alphabets.

Definition 5 (Generalized Systematic Encoding). Let $\mathcal{C}:\Gamma^k \to \Lambda^n$ be an erasure code with alphabets $\Gamma, \Lambda$, message length $k$, code length $n$, and reception efficiency $t$, with reconstruction algorithm Reconst. We say that $\mathcal{C}$ has a generalized systematic encoding, if the following hold:

- There are two deterministic polynomial time algorithms Find and Proj, such that for any  $ m \in \Gamma^k $ and  $ \hat{m} := \mathcal{C}(m) $, and for any  $ i \in [k] $ and  $ \hat{i} := \text{Find}(i) $, we have  $ \text{Proj}(i, \hat{m}_i) = m_i $.

- Let  $ I \subseteq [n] $ be arbitrary with  $ |I| \geq t $, and let  $ (\hat{m}_i)_{i \in I} \in \Lambda^{[I]} $ be any sequence of symbols in  $ \Lambda $. Let  $ m := \text{Reconst}((\hat{m}_i)_{i \in I}) $, and let  $ I^* := \{i \in [k] \mid \text{Find}(i) \in I\} $. Then, for all  $ i \in I^* $ and  $ \hat{i} := \text{Find}(i) $ it should hold that  $ \text{Proj}(i, \hat{m}_i) = m_i $.

We say that Proj is the symbol projection algorithm and Find is the symbol finding algorithm of C.

Linear Erasure Codes. If C is a code that is a subspace of some vector space, we call it a linear erasure code. Alternatively, when viewing the code as an encoding function, it corresponds to an injective homomorphism of vector spaces. We restrict ourselves to vector spaces of finite size in this work.

Definition 6 (Linear Erasure Codes). Let $\mathbb{F}$ be a finite field, possibly implicitly parameterized by the security parameter. A linear erasure code over $\mathbb{F}$ is an erasure code $\mathcal{C}:\mathbb{F}^k \to \mathbb{F}^n$, such that $\mathcal{C}$ is an injective homomorphism from the vector spaces $\mathbb{F}^k$ to the vector space $\mathbb{F}^n$ over $\mathbb{F}$.

Let us discuss some important properties of linear erasure codes. Linear erasure codes can be specified by one of two matrices. Namely, if $\mathcal{C}:\mathbb{F}^k \to \mathbb{F}^n$ is a linear erasure code, then there is a generator matrix $\mathbf{G} \in \mathbb{F}^{n \times k}$ with full rank such that for all $\mathbf{m} \in \mathbb{F}^k$ we have $\mathcal{C}(\mathbf{m}) = \mathbf{G}\mathbf{m}$. Additionally, there is a parity-check matrix $\mathbf{H} \in \mathbb{F}^{(n-k) \times n}$ such that $\mathcal{C}$ is exactly the kernel of $\mathbf{H}$. We also have $\mathbf{H}\mathbf{G} = \mathbf{0}$.

MDS Codes. The well-known singleton bound states that for linear $ ^{10} $ erasure codes  $ \mathcal{C}\colon\mathbb{F}^k\to\mathbb{F}^n $ with minimum distance  $ d $ we have  $ d\leq n-k+1 $. An MDS (maximum distance separable) code is a linear erasure code that satisfies the singleton bound with equality.

Definition 7 (MDS Code). Let $\mathcal{C}:\mathbb{F}^k \to \mathbb{F}^n$ be a linear erasure code over field $\mathbb{F}$, and let $d$ denote its minimum distance. Then, $\mathcal{C}$ is called an MDS code, if $d = n - k + 1$.

MDS codes have several interesting properties. Most importantly for us, every set of $n-k$ columns of the parity-check matrix forms an invertible matrix. Further, one can show that for any $k$ symbols $x_{i_1},\ldots,x_{i_k}$ there is a unique codeword $\mathbf{x}\in\mathcal{C}$ such that the $i_j$th symbol of $\mathbf{x}$ is $x_{i_j}$ for all $j\in[n]$. That is, every $k$ symbols are consistent with the code. To see this, note that the function that maps messages to the symbols of the codeword at positions $i_1,\ldots,i_k$ is injective and thus surjective.

Reed-Solomon Codes. One of the most widely used MDS codes is the Reed-Solomon code. Roughly, it corresponds to evaluations of polynomials. More precisely, given an (ordered) set  $ E = \{e_1, \ldots, e_n\} \subseteq \mathbb{F} $ of size  $ n $, the Reed-Solomon code for message length  $ k $ works as follows. To encode a given message  $ \mathbf{m} \in \mathbb{F}^k $, interpret  $ \mathbf{m} $ as a degree  $ k - 1 $ polynomial  $ f $ over  $ \mathbb{F} $. This can be done in various ways. For example, if a systematic encoding is needed, one can interpolate  $ f $ such that it satisfies  $ f(e_i) = \mathbf{m}_i $ for all  $ i \in [k] $. Next,  $ f $ is evaluated at all points in  $ E $, leading to the codeword  $ \mathbf{c} = (f(e_1), \ldots, f(e_n))^\top $. As said, Reed-Solomon codes are MDS codes, meaning that their minimum distance is  $ n - k + 1 $. Throughout this work, we will denote the Reed-Solomon code as defined above by  $ \mathcal{RS}[k, n, \mathbb{F}] $, where we leave the set  $ E $ implicit.

Interleaved Codes. Let $\mathcal{C} : \Gamma^k \to \Lambda^n$ be an erasure code with alphabets $\Gamma$, $\Lambda$, message length $k$, code length $n$, and reception efficiency $t$. Given $\mathcal{C}$, we construct a new code $\mathcal{C} \equiv \ell : \Gamma^{\ell k} \to \Lambda^m$ as follows, where $\Lambda^\ell := \Lambda^\ell$. To encode a message $m \in \Gamma^{\ell k}$, write it as $m = (m^{(1)}, \ldots, m^{(\ell)})$, where $m^{(i)} \in \Gamma^k$ for each $i \in [\ell]$. Then, for each $i \in [\ell]$, compute $\hat{m}^{(i)} := \mathcal{C}(m^{(i)})$. Now, for each $j \in [n]$, the $j$th symbol of the codeword $\hat{m}$ is $\hat{m}_j := (\hat{m}_j^{(1)}, \ldots, \hat{m}_j^{(\ell)})$. It is easy to see that if $\mathcal{C}$ has reception efficiency $t$ and minimum distance $d$, then $\mathcal{C} \equiv \ell$ also has reception efficiency $t$ and minimum distance $d$. The code $\mathcal{C} \equiv \ell$ that we just constructed is sometimes called interleaved code. We note that sometimes the interleaved code is defined with codewords of length $\ell n$ over alphabet $\Lambda$. For us, it will be better to treat the codeword as a string of length $n$ over alphabet $\Lambda^\ell$. This is also done in [CDD+16].

Linear Interleaved Codes. Starting with a linear erasure code  $ C: \mathbb{F}^k \to \mathbb{F}^n $, the interleaved code  $ C = \ell: \mathbb{F}^{\ellk} \to (\mathbb{F}^{\ell})^n $ can be written in a more concise way. For that, let  $ \mathbf{G} \in \mathbb{F}^{n \times k} $ be the generator matrix of  $ C $. To encode a message  $ \mathbf{m} \in \mathbb{F}^{\ell k} $ using  $ C = \ell $,  $ \mathbf{m} $ is first written as a matrix  $ \mathbf{M} \in \mathbb{F}^{\ell \times k} $ in an arbitrary canonical way. Then, each row is encoded with  $ \mathbf{G} $. That is, we compute  $ \mathbf{X} := \mathbf{M}\mathbf{G}^\top \in \mathbb{F}^{\ell \times n} $. Finally, the columns of  $ \mathbf{X} $ are interpreted as the symbols of the resulting codeword.

Tensor Codes. Given two codes  $ C_r $ and  $ C_c $, with message lengths  $ k_r $,  $ k_c $, respectively, one can write the message as a  $ k_c \times k_r $ matrix. Then, one can encode the message by encoding rows with  $ C_r $ and columns

with  $ C_c $. This is called the tensor code $ ^{11} $ of  $ C_r $ and  $ C_c $. More concretely, assume two linear erasure codes  $ C_r $:  $ \mathbb{F}^{k_r} \to \mathbb{F}^{n_r} $ and  $ C_c $:  $ \mathbb{F}^{k_c} \to \mathbb{F}^{n_c} $ over the same field  $ \mathbb{F} $. Let  $ t_r, t_c $ denote their respective reception efficiencies, and  $ \mathbf{G}_r \in \mathbb{F}^{n_r \times k_r} $ and  $ \mathbf{G}_c \in \mathbb{F}^{n_c \times k_c} $ denote their respective generator matrices. The tensor code of  $ C_r $ and  $ C_c $ is  $ \mathcal{C}_r \otimes \mathcal{C}_c $:  $ \mathbb{F}^{k_r \cdot k_c} \to \mathbb{F}^{n_r \cdot n_c} $, which works as follows. To encode a message  $ \mathbf{m} \in \mathbb{F}^{k_r \cdot k_c} $, write  $ \mathbf{m} $ as a matrix  $ \mathbf{M} \in \mathbb{F}^{k_c \times k_r} $ in some fixed canonical way. Then, compute  $ \mathbf{X} := \mathbf{G}_c \mathbf{M} \mathbf{G}_r^\top \in \mathbb{F}^{n_c \times n_r} $. Finally, flatten  $ \mathbf{X} $ into a vector  $ \mathbf{x} \in \mathbb{F}^{n_c \cdot n_r} $, which is the codeword. To ease notation, for each  $ j' \in [n_c n_r] $, we will write  $ (i, j) := \text{ToMatIdx}(j') $ to indicate the unique pair of indices  $ i \in [n_c], j \in [n_r] $ such that  $ \mathbf{x}_{j'} = \mathbf{X}_{i,j} $. One can show that the tensor code is also a linear code. Next, we give a bound on the reception efficiency of the tensor code. In Appendix D, we show that the reception efficiency of  $ \mathcal{C}_r \otimes \mathcal{C}_c $ as above is  $ n_c n_r - (n_c - t_c + 1)(n_r - t_r + 1) + 1 $. For instance, consider a code  $ \mathcal{C} $:  $ \mathbb{F}^k \to \mathbb{F}^{2k} $ with reception efficiency  $ k $. Then, the reception efficiency of  $ \mathcal{C} \otimes \mathcal{C} $ is  $ 3k^2 - 2k $.

## 6 From Codes and Commitments to Data Availability Sampling

In this section, we show how to generically construct a data availability sampling scheme from a special class of commitments for codes. Namely, we abstract existing constructions that use vector commitments, and polynomial commitments, or similar structured commitments. First, we formally define the commitments that we consider. In a second step, we introduce and analyze index samplers as the combinatorial core component of the final data availability sampling scheme. Third, we present and analyze our generic construction of data availability sampling from any such commitment and any such index sampler.

### 6.1 Erasure Code Commitments

We introduce erasure code commitments as a generalization of vector commitments and polynomial commitments. Roughly, we can use such a commitment to commit to a codeword of an erasure code. One can view a vector commitment as an erasure code commitment for the identity code, and polynomial commitment as an erasure code commitment for the Reed-Solomon code.

Syntax. The next definition introduces the syntax of erasure code commitments.

Definition 8 (Erasure Code Commitment Scheme). Consider an erasure code $\mathcal{C}:\Gamma^k \to \Lambda^n$ with alphabets $\Gamma, \Lambda$, message length $k$, code length $n$, reception efficiency $t$, and reconstruction algorithm Reconst. An erasure code commitment scheme for $\mathcal{C}$ with opening alphabet $\Xi$ is a tuple $\mathsf{CC} = (\mathsf{Setup}, \mathsf{Com}, \mathsf{Open}, \mathsf{Ver})$ of PPT algorithms, with the following syntax:

• Setup(1λ) → ck takes as input the security parameter and outputs a commitment key ck.

-  $ \text{Com}(ck,m) \to (\text{com}, St) $ takes as input a commitment key  $ ck $ and a string  $ m \in \Gamma^k $, and outputs a commitment  $ \text{com} $ and a state  $ St $.

- Open(ck, St, i) → τ takes as input a commitment key ck, a state St, and an index i ∈ [n], and outputs an opening τ ∈ ∃.

- Ver(ck, com, i,  $ \hat{m}_i $,  $ \tau $)  $ \rightarrow $ b is deterministic, takes as input a commitment key ck, a commitment com, and index  $ i \in [n] $, a symbol  $ \hat{m}_i \in \Lambda $, and an opening  $ \tau \in \Xi $, and outputs a bit  $ b \in \{0,1\} $.

Further, we require that the following completeness property holds: For every  $ ck \in \text{Setup}(1^\lambda) $, every  $ m \in \Gamma^k $, and every  $ i \in [n] $, we have

 $$ \begin{array}{l l}{\operatorname{P r}\left[\operatorname{V e r}(\mathbf{c}\mathbf{k},\mathbf{c o m},i,\hat{m}_{i},\tau)=1\left|\begin{array}{l}{\left(\mathbf{c o m},S t\right)\leftarrow\mathbf{C o m}(\mathbf{c}\mathbf{k},m),}\\ {\hat{m}:=\mathcal{C}(m),}\\ {\tau\leftarrow\operatorname{O p e n}(\mathbf{c}\mathbf{k},S t,i)}\end{array}\right.\right]\geq1-\operatorname{n e g l}(\lambda).}\end{array} $$

Now that we have specified the syntax of erasure code commitment schemes, we turn to the security properties they should have. We define a variety of such properties, most importantly position-binding and code-binding. Later, we will see how these properties imply the security of the resulting data availability sampling scheme. We summarize the relations between these properties in Figure 2.

<div style="text-align: center;"><img src="images/HAS23 - Fig 2 - Erasure code commitments.jpg" alt="Image" width="69%" /></div>


<div style="text-align: center;"><div style="text-align: center;">Figure 2: Overview of the different security properties we define for erasure code commitments, how they relate to each other, and how they relate to the security of the resulting data availability sampling scheme. An arrow denotes an implication. A dashed arrow denotes an implication that holds if additionally position-binding is assumed. For the implication from computational uniqueness to code-binding (double dashed), we additionally assume position-binding and that the code is an MDS code.</div> </div>


Binding Notions. The first notion we define is position-binding, which is analogous to the position-binding notion for vector commitments. The intuition of position-binding is that no efficient adversary can open a commitment to two different values at the same position.

Definition 9 (Position-Binding of CC). Let CC = (Setup, Com, Open, Ver) be an erasure code commitment scheme for an erasure code C. We say that CC is position-binding, if for every PPT algorithm A, the following advantage is negligible:

 $$ \begin{aligned}Adv_{\mathcal{A},\mathrm{CC}}^{\mathrm{pos-bind}}(\lambda):=\Pr\left[\begin{array}{cc}\hat{m}\neq\hat{m}^{\prime}\\\wedge\quad\mathrm{Ver}(\mathrm{ck},\mathrm{com},i,\hat{m},\tau)=1\\\wedge\quad\mathrm{Ver}(\mathrm{ck},\mathrm{com},i,\hat{m}^{\prime},\tau^{\prime})=1\end{array}\right|\begin{array}{c}\mathrm{ck}\leftarrow\mathrm{Setup}(1^{\lambda}),\ $ \mathrm{com},i,\hat{m},\tau,\hat{m}^{\prime},\tau^{\prime})\leftarrow\mathcal{A}(\mathrm{ck})\end{array}\right].\end{aligned} $$

Requiring only position-binding, we could easily implement an erasure code commitment by committing to a codeword using a standard vector commitment. However, one should only be able to commit to codewords. For that, we define code-binding. Roughly, it requires that an adversary can not open a commitment on a set of positions in a way that is inconsistent with the code.

Definition 10 (Code-Binding of CC). Let CC = (Setup, Com, Open, Ver) be an erasure code commitment scheme for an erasure code C. We say that CC is code-binding, if for every PPT algorithm A, the following advantage is negligible:

 $$ \begin{array}{r}{\mathrm{A d v}_{\mathcal{A},\mathsf{C C}}^{\mathrm{c o d e-b i n d}}(\lambda):=\operatorname*{P r}\left[\begin{array}{c}{\neg\left(\exists c\in\mathcal{C}(\Gamma^{k}):\forall i\in I:c_{i}=\hat{m}_{i}\right)}\\ {\wedge\forall i\in I:\mathsf{V e r}(\mathsf{c k},\mathsf{c o m},i,\hat{m}_{i},\tau_{i})=1}\end{array}\right|\begin{array}{l}{\mathsf{c k}\leftarrow\mathsf{S e t u p}(1^{\lambda}),}\\ {(\mathsf{c o m},(\hat{m}_{i},\tau_{i})_{i\in I})\leftarrow\mathcal{A}(\mathsf{c k})}\end{array}\right].}\end{array} $$

We introduce a third binding notion called reconstruction-binding. When we want to use erasure code commitments in the context of data availability sampling schemes, reconstruction-binding, as defined next, is a natural requirement. Namely, it will ensure that extracting from two sets of transcripts leads to consistent results. In other words, reconstruction-binding states that one can not provide two sets of openings for the same commitment, such that reconstructing from these sets leads to inconsistent messages. After giving the formal definition of reconstruction-binding, we show that it is implied by position-binding and code-binding. Later, we show that it implies the consistency property of our data availability sampling scheme.

Definition 11 (Reconstruction-Binding of CC). Let CC = (Setup, Com, Open, Ver) be an erasure code commitment scheme for an erasure code C with reception efficiency t and reconstruction algorithm Reconst. We say that CC is reconstruction-binding, if for every PPT algorithm A, the following advantage is negligible:

 $$ \begin{aligned}Adv_{\mathcal{A},\mathsf{CC}}^{rec-bind}(\lambda):=\Pr\left[\begin{array}{c}|I|\geq t\wedge|I^{\prime}|\geq t\wedge\bot\notin\{m,m^{\prime}\}\\\wedge\forall i\in I:\mathsf{Ver}(\mathsf{ck},\mathsf{com},i,\hat{m}_{i},\tau_{i})=1\\\wedge\forall i\in I^{\prime}:\mathsf{Ver}(\mathsf{ck},\mathsf{com},i,\hat{m}_{i}^{\prime},\tau_{i}^{\prime})=1\\\wedge\ m\neq m^{\prime}\end{array}\right|\begin{array}{c}\mathsf{ck}\leftarrow\mathsf{Setup}(1^{\lambda}),\ $ \mathsf{com},(\hat{m}_{i},\tau_{i})_{i\in I},(\hat{m}_{i}^{\prime},\tau_{i}^{\prime})_{i\in I^{\prime}})\\\leftarrow\mathcal{A}(\mathsf{ck}),\\m:=\mathsf{Reconst}((\hat{m}_{i})_{i\in I}),\\m^{\prime}:=\mathsf{Reconst}((\hat{m}_{i}^{\prime})_{i\in I^{\prime}})\end{array}\right].\end{aligned} $$

Lemma 2. Let CC = (Setup, Com, Open, Ver) be an erasure code commitment scheme for an erasure code C. If CC is position-binding and code-binding, then CC is reconstruction-binding. Precisely, for any PPT algorithm A, there are PPT algorithms  $ B_1, B_2 $ with  $ \mathbf{T}(\mathcal{B}_1) \approx \mathbf{T}(\mathcal{A}) $,  $ \mathbf{T}(\mathcal{B}_2) \approx \mathbf{T}(\mathcal{A}) $, and

 $$ \mathsf{A d v}_{\mathcal{A},\mathsf{C C}}^{\mathsf{r e c-b i n d}}(\lambda)\leq\mathsf{A d v}_{\mathcal{B}_{1},\mathsf{C C}}^{\mathsf{p o s-b i n d}}(\lambda)+\mathsf{A d v}_{\mathcal{B}_{2},\mathsf{C C}}^{\mathsf{c o d e-b i n d}}(\lambda). $$

The proof of Lemma 2 is given in Appendix F.1.

Other Notions. We introduce further security notions for erasure code commitments. As indicated by Figure 2, these notions are not directly necessary if we want to construct data availability sampling schemes satisfying our basic definition in Section 3.1. However, they turn out to be useful for two reasons. First, these notions are necessary if we want to construct repairable data availability sampling schemes. Second, some of these notions are stronger than others and help us to avoid repeating parts of our analysis.

The first of these additional notions is a strong notion called extractability. Intuitively, a (deterministic) erasure code commitment is extractable, if there is an efficient algorithm Ext that can extract a message m from any commitment com output by an adversary, as long as the adversary provides at least one opening. When committing to the extracted message m, one obtains com. This typically requires the use of the algebraic group model. We formally define the notion of extractability and study it in Appendix E.3.

A second property we consider is called message-bound openings. This property turns out to be useful for repairability. Intuitively, we want to repair an encoding from a set of transcripts by first reconstructing the data, and then re-encoding this data. The challenge is that the new encoding has to be compatible with the old commitment that an adversary made up. Our notion of message-bound openings ensures this. Namely, it requires that it is hard for an adversary to come up with two commitments for the same message and enough valid openings that can not be arbitrarily “mixed-and-matched”. We postpone the formal definition to Appendix E.1.

A final notion we introduce and study is computational uniqueness. The notion is almost as the notion of message-bound openings, but just requires the adversary to output two distinct commitments. In other words, if a scheme is computationally unique, it means that whenever an adversary can open two commitments to codewords that reconstruct to the same message, then the commitments are the same. In Appendix E.2, we give the formal definition and show that this notion is strong enough to imply both code-binding and message-bound openings.

Simple Examples. Before finishing this section, we mention simple examples of erasure code commitments. These examples also shed light on how erasure code commitments relate to other commitment schemes.

Example 3 (Vector Commitments). We can view any vector commitment [Mer88, CF13] for vectors in  $ \Gamma^k $ as being an erasure code commitment for the code  $ \mathcal{C}\colon\Gamma^k\to\Gamma^k $ with  $ \mathbf{x}\mapsto\mathbf{x} $ for all  $ \mathbf{x}\in\Gamma^k $. In this case, code-binding holds trivially and position-binding is equivalent to the definition of position-binding for vector commitments.

Example 4 (Polynomial Commitments). Polynomial commitments [KZG10] are a special case of erasure code commitments for the Reed-Solomon code. Our notion of position-binding matches the definition of position-binding for polynomial commitment schemes in [KZG10]. Interestingly, [KZG10] does not define a notion matching code-binding. That is, there is no notion in [KZG10] stating that an adversary can not open a commitment to points which are not on a polynomial of appropriate degree. It is easy to see that the KZG polynomial commitment scheme [KZG10] satisfies this notion. For that, it is sufficient to observe that it is extractable in the algebraic group model [FKL18], see Appendix E.3.

### 6.2 Index Samplers

Our goal is to construct a data availability sampling scheme from any erasure code commitment scheme. The high level idea is that clients query and verify some positions of the encoding. Every such position contains a symbol of a codeword and its corresponding opening for the erasure code commitment. Now, a natural question is how clients sample the indices that they query. We abstract the strategy that the

clients use by defining so called index samplers. An index sampler is just an algorithm that outputs Q indices in some range [N]. An example of an index sampler is given by sampling uniformly with replacement, i.e., the index sampler outputs Q indices sampled uniformly at random from [N]. Intuitively, different index samplers may lead to different guarantees for the resulting data availability sampling scheme. For example, an index sampler is a good choice if only a few clients with a few samples are needed to guarantee that at least a certain number of distinct indices (i.e., symbols of the codeword) from [N] are touched, and thus data can be reconstructed. We make this intuition formal by defining the quality of an index sampler. This measure will translate to the soundness and completeness error of the resulting data availability sampling scheme.

Definition 12 (Index Sampler). An index sampler with quality  $ \nu $:  $ \mathbb{N}^4 \to \mathbb{R} $ is a PPT algorithm Sample with the following syntax and properties:

• Sample $ (1^Q, 1^N) \to (i_j)_{j \in [Q]} $ takes as input integers  $ Q, N \in \mathbb{N} $ and outputs  $ Q $ indices  $ i_j \in [N] $.

• For any  $ N, \Delta \in \mathbb{N} $ with  $ \Delta < N $, and any  $ Q, \ell \in \mathbb{N} $, we have

 $$ \operatorname{Pr}_{\mathcal{G}}\left[\left|\bigcup_{l\in[\ell]}\{i_{l,j}\mid j\in[Q]\}\right|\leq\Delta\right]\leq\nu(\Delta,N,Q,\ell), $$

where experiment  $ \mathcal{G} $ is given by running  $ (i_{l,j})_{j\in[Q]}\leftarrow\text{Sample}(1^{Q},1^{N}) $ for each  $ l\in[\ell] $.

In the context of data availability sampling schemes, the encoding may be distributed over many physical nodes. Ideally, indices are sampled in a way that minimizes the number of nodes a client has to query. For that reason, we define a locality measure for index samplers. It is defined as the number of physical nodes that the index sampler touches.

Definition 13 (Locality of Index Samplers). Let Sample be an index sampler,  $ Q, N, D \in \mathbb{N}, \epsilon \in [0, 1] $ with  $ D \leq Q $, and  $ \mathcal{S}: [N] \to \mathbb{N} $ be a function. We say that Sample is  $ (Q, N, \mathcal{S}, D, \epsilon) $-local, if

 $$ \operatorname*{P r}_{\mathcal{G}}\left[\left|\left\{\mathcal{S}(i_{j})\mid j\in[Q]\right\}\right|>D\right]\leq\epsilon, $$

where G is given by running (i,j)j∈[Q] ← Sample(1Q,1N).

Of course, every index sampler has optimal locality (i.e.  $ \epsilon = 0, \Sigma = 1 $) if the function  $ \mathcal{S} $ is constant, i.e., the entire encoding is stored on one physical node. A more natural function  $ \mathcal{S} $ would be  $ \mathcal{S}(x) = \lfloor (x - 1)/Q \rfloor $, i.e., each node stores a contiguous part of the encoding of equal size.

Next, we discuss three examples of index samplers. Namely, we consider natural index samplers that sample all indices uniformly at random, either with replacement or without replacement. Finally, we also introduce an index sampler that is optimized in terms of locality.

Sampling With Replacement. Sampling with replacement is given via the following algorithm.

• Sample $ _{wr}(1^Q, 1^N) $: For each  $ j \in [Q] $, sample  $ i_j \leftarrow s $ [N]. Return  $ (i_j)_{j \in [Q]} $.

We analyze the quality of algorithm Sample $ _{wr} $ that samples indices uniformly at random with replacement.

Lemma 3. Algorithm Sample $ _{wr} $ is an index sampler with quality  $ \nu_{wr} : \mathbb{N}^4 \to \mathbb{R} $, where

 $$ \nu_{\mathsf{w r}}(\Delta,N,Q,\ell)=\binom{N}{\Delta}\left(\frac{\Delta}{N}\right)^{Q\ell}. $$

In particular, Sample $ _{wr} $ is an index sampler with quality  $ \nu_{wr}^{\prime} : \mathbb{N}^{4} \to \mathbb{R} $, where

 $$ \nu_{\mathrm{w r}}^{\prime}(\Delta,N,Q,\ell)=c^{Q\ell-(1-\log_{c}(e))\Delta}{~f o r~}c:=\Delta/N. $$

The proof of Lemma 3 is given in Appendix F.2. In Section 6.3, we will see that the quality  $ \nu(\Delta, N, Q, \ell) $ of an index sampler corresponds to the advantage of an adversary against soundness of the resulting data availability sampling scheme. Namely, if our data consists of  $ K $ symbols, and our encoding consists of  $ N $ symbols, such that any  $ \Delta + 1 $ are sufficient to reconstruct the data, then we need to choose  $ Q $ and  $ \ell $ such that  $ \nu(\Delta, N, Q, \ell) $ is negligible in the security parameter  $ \lambda $. To get an intuition for the bound that Lemma 3 provides, let us consider two examples.

Example 5 (Trivial Encoding). Assume that we do not use any erasure code at all, or in other words, we use the identity function as an erasure code. In this case, we have  $ K = N $ and  $ \Delta = K - 1 $, because we need all symbols to reconstruct the data. Using the first bound in Lemma 3, we can upper bound the advantage against soundness by

 $$ \binom{N}{N-1}\left(1-\frac{1}{N}\right)^{Q\ell}=N\left(1-\frac{1}{N}\right)^{N\frac{Q\ell}{N}}\leq2^{\log N}e^{-\frac{Q\ell}{N}}=2^{\log N-\log e\frac{Q\ell}{N}}. $$

This bound is negligible once we set

 $$ Q\ell\geq\Omega(N\lambda+N\log N)=\Omega(K\lambda+K\log K). $$

Example 6 (Using Erasure Codes). Assume that we encode the $K$ symbols of data with an erasure code into $N = 2K$ symbols, such that any $K$ of these are sufficient to reconstruct the data. For example, we could use a Reed-Solomon code and a polynomial commitment to realize this. We can now use the second bound in Lemma 3 with $c = \Delta/N < 1/2$. This yields an upper bound on the advantage against soundness of $2^{-Q\ell+(1-\log_{1/2}e)(K-1)} \leq 2^{-Q\ell+3K}$. The bound is negligible once we set

 $$ Q\ell\geq\Omega(K+\lambda). $$

Now, let us consider the notion of subset-soundness instead. In Lemma 1, we showed that soundness implies  $ (L, \ell) $-subset-soundness, with a security loss of at most  $ (Le/\ell)^\ell $. Assuming  $ L = C \cdot \ell $ for some constant  $ C > 1 $, we get an upper bound on the advantage against  $ (L, \ell) $-subset-soundness of  $ 2^\ell(\log C + \log e) - Q^\ell + 3K $. If  $ Q \geq \log C + \log e + 1 $, this bound is also negligible once we set  $ Q\ell \geq \Omega(K + \lambda) $.

The two examples demonstrate that using an erasure code results in a significant improvement in terms of the number of samples we need to reconstruct the data with overwhelming probability. Additionally, the second example demonstrates a significant difference between soundness and subset-soundness. Namely, while having  $ \ell $ clients with Q queries per client is equivalent to having 1 client with  $ \ell Q $ queries and to having  $ \ell Q $ clients with 1 query in terms of soundness, these three settings are not equivalent in terms of subset-soundness. Especially, to get subset-soundness, we have to set Q large enough. Intuitively, this is because the number of transcripts from which the adversary can choose differs in the three settings.

Next, we want to understand the locality of algorithm Sample_{wr}. Intuitively, sampling indices uniformly at random should lead to a bad locality. The next lemma states exactly that, especially when N or Q - D is large.

Lemma 4. Let  $ Q, N, D \in \mathbb{N}, \epsilon \in [0, 1] $ with  $ D \leq Q $, and  $ \mathcal{S}\colon [N] \to \mathbb{N} $ be a Q-to-1 function mapping onto a set of size  $ N/Q $. Then, if Sample $ _{wr} $ is  $ (Q, N, \mathcal{S}, D, \epsilon) $-local, then

 $$ \epsilon>1-e^{D}\cdot\left(\frac{D}{N/Q}\right)^{Q-D}. $$

The proof of Lemma 4 is given in Appendix F.2.

Sampling Without Replacement. Sampling without replacement is given by the following algorithm.

• Sample_{wor}(1^Q, 1^N) : For each j ∈ [Q], sample i_j ← s [N] \ {i_1, ... , i_{j-1}. Return (i_j)_j ∈ [Q].

We analyze the quality of algorithm Sample_{wor} in the following lemma.

Lemma 5. Algorithm Sample_{wor} is an index sampler with quality  $ \nu_{wor} : \mathbb{N}^4 \to \mathbb{R} $, where

 $$ \nu_{\mathrm{w o r}}(\Delta,N,Q,\ell)=\binom{N}{\Delta}\left(\binom{\Delta}{Q}\bigg/\binom{N}{Q}\right)^{\ell}. $$

The proof of Lemma 5 is given in Appendix F.2.

Segment Sampling. We introduce a third index sampler. The idea is to partition the set [N] into N/Q segments of size Q. Then, the sampler picks one of the segments at random and queries this entire segment. The advantage is minimal randomness complexity and the locality of the sampled indices. We define algorithm Sample $ _{seg} $ as follows:

- Sample $ _{\text{seg}}(1^Q, 1^N) $: If  $ N \mod Q \neq 0 $, return  $ (i_j)_{j \in [Q]} \leftarrow \text{Sample}_{wr}(1^Q, 1^N) $. Otherwise, sample $ \text{seg} \leftarrow \text{s}[N/Q] $. For each  $ j \in [Q] $, set  $ i_j := (\text{seq} - 1)Q + j $. Return  $ (i_j)_{j \in [Q]} $.

Next, we analyze the quality and locality of Sample $ _{seg} $. Intuitively, the analysis of Sample $ _{seg} $ reduces to an analysis of Sample $ _{wr} $ over the segments.

Lemma 6. Assuming algorithm Sample $ _{wr} $ is an index sampler with quality  $ \nu_{wr} : \mathbb{N}^4 \to \mathbb{R} $, the algorithm Sample $ _{seg} $ is an index sampler with quality  $ \nu_{seg} : \mathbb{N}^4 \to \mathbb{R} $, where

 $$ \nu_{\mathrm{s e g}}(\Delta,N,Q,\ell)=\begin{cases}{\nu_{\mathrm{w r}}(\Delta,N,Q,\ell)}&{{i f~N~\bmod~Q\neq0~}}\\ {\nu_{\mathrm{w r}}(\Delta/Q,N/Q,1,\ell)}&{{i f~N~\bmod~Q=0~}.}\\ \end{cases} $$

In particular, Sample $ _{seg} $ is an index sampler with quality  $ \nu'_{seg} $:  $ N^{4} \rightarrow R $, where

 $$ \nu_{\mathrm{s e g}}^{\prime}(\Delta,N,Q,\ell)=\begin{cases}{c^{Q\ell-(1-\operatorname{l o g}_{c}(e))\Delta}}&{{i f~}N\mod Q\neq0}\\ {c^{\ell-(1-\operatorname{l o g}_{c}(e))\Delta/Q}}&{{i f~}N\mod Q=0}\\ \end{cases} $$

for  $ c := \Delta / N $.

The proof of Lemma 6 is given in Appendix F.2.

Lemma 7. Let  $ Q, N \in \mathbb{N} $ be such that  $ Q $ divides  $ N $. Consider  $ \mathcal{S}\colon [N] \to \mathbb{N} $ with  $ \mathcal{S}(x) = \lfloor (x - 1)/Q \rfloor $. Then, Sample $ _{\text{seg}} $ is  $ (Q, N, \mathcal{S}, 1, 0) $-local.

Lemma 7 follows trivially by inspection.

Simulation. The analytical results in this section heavily rely on the use of probabilistic bounds, e.g., the union bound or the Chernoff bound. One may ask whether more precise results can be obtained by other means. To this end, we simulated the three index samplers discussed in this section and compared their quality. We present and discuss our results in Appendix J.

Now that we have introduced erasure code commitments and index samplers, we come to the main construction of this section. Namely, we show how to construct a data availability sampling scheme from any erasure code commitment scheme and any index sampler. If the erasure code has a generalized systematic encoding, the resulting data availability sampling scheme is locally accessible with optimal query complexity L = 1.

Overview. We start with an erasure code  $ \mathcal{C} $ with reception efficiency  $ t $ and an erasure code commitment scheme CC for it. In the data availability sampling scheme, a proposer encodes the data data by first applying the code  $ \mathcal{C} $ to it to get a codeword data =  $ \mathcal{C}(\text{data}) $. For consistency, the proposer commits to this codeword using CC. The resulting commitment  $ \text{com} $ will be given to the clients. In addition to that, the proposer computes openings  $ \tau_i $ for all positions  $ i $ of the codeword. Then, each symbol  $ \widehat{\text{data}}_i $ together with its opening  $ \tau_i $ forms a symbol  $ \pi_i $ of the encoding  $ \pi $. Clients are defined in the following way: First, they determine some set of indices  $ i_1, \ldots, i_Q $ using an index sampler and query these indices, getting  $ \widehat{\text{data}}_{i_j}, \tau_{i_j} $ as responses. Then, they verify all openings with respect to  $ \text{com} $, and accept if and only if they are all valid. To extract data from a given set of transcripts, we first check that all transcripts are accepting, and that they contain at least  $ t $ distinct positions of  $ \pi $. If this holds, then we have at least  $ t $ distinct positions of the codeword  $ \widehat{\text{data}} $ and can reconstruct the data.

Construction. Let  $ \mathcal{C} : \Gamma^k \to \Lambda^n $ be an erasure code with alphabets  $ \Gamma, \Lambda $, message length  $ k $, code length  $ n $, and reception efficiency  $ t $, with reconstruction algorithm Reconst. Let  $ \operatorname{CC} = (\text{Setup}, \operatorname{Com}, \operatorname{Open}, \operatorname{Ver}) $

be an erasure code commitment scheme for $\mathcal{C}$ with opening alphabet $\Xi$. Further, let Sample be an index sampler with quality $\nu$. We construct a data availability sampling scheme DAS[CC, Sample] = (Setup, Encode, V, Ext) with data length $K := k$, encoding length $N := n$, data alphabet $\Gamma$, encoding alphabet $\Sigma = \Lambda \times \Xi$, query complexity $Q \in \mathbb{N}$, and threshold $T \in \mathbb{N}$. We emphasize that $T$ and $Q$ have to be chosen appropriately and depend on $n, t$, and the quality $\nu$ of Sample. We refer to our analysis for a concrete bound. The construction is as follows.

• Setup(1^λ) → par: Run ck ← Setup(1^λ) and set par := ck.

• Encode(data) → (π, com):

1. Run (com, St) := Com(ck, data;  $ \rho $) for some hardcoded coins  $ \rho $.

2. Compute data := C(data).

3. For each  $ i \in [N] $, run  $ \tau_i \leftarrow \text{Open(ck, St, } i) $, and set  $ \pi_i := (\widehat{\text{data}}_i, \tau_i) $.

-  $ \mathbf{V}_1^{\pi,Q}(\text{com}) \to \text{tran}: \text{Run}(i_j)_{j \in [Q]} \leftarrow \text{Sample}(1^Q, 1^N) $ and query  $ (\widehat{\text{data}}_{i_j}, \tau_{i_j}) := \pi_{i_j} $ for each  $ j \in [Q] $.

Set  $ \text{tran} := (i_j, \widehat{\text{data}}_{i_j}, \tau_{i_j})_{j \in [Q]} $.

-  $ \mathrm{V}_2(\mathrm{com}, \mathrm{tran}) \to b $: If there is a  $ j \in [Q] $ with  $ \mathrm{Ver}(\mathrm{ck}, \mathrm{com}, i_j, \widehat{\mathrm{data}}_{i_j}, \tau_{i_j}) = 0 $, then return  $ b := 0 $. Otherwise, return  $ b := 1 $.

• Ext(com, tran₁, ..., tranₗ) → data/⊥:

1. Write  $ \text{tran}_l := (i_{l,j}, \widehat{\text{data}}_{l,i_{l,j}}, \tau_{l,i_{l,j}})_{j \in [Q]} $ for each  $ l \in [L] $.

2. If there is an  $ l \in [L] $ such that  $ \mathrm{V}_2(\mathrm{com}, \mathrm{tran}_l) = 0 $, return  $ \perp $.

3. Let  $ I \subseteq [N] $ be the set of indices  $ i \in [N] $ such that there is a  $ (l, j) \in [L] \times [Q] $ with  $ i_{l,j} = i $. If  $ |I| < t $, then return  $ \perp $.

4. Otherwise, for each  $ i \in I $, pick an arbitrary such  $ (l,j) \in [L] \times [Q] $ with  $ i_{l,j} = i $ and set  $ \widehat{\text{data}_i} := \widehat{\text{data}_{l,i_{l,j}}} $.

 $$ \text{Return data}:=\operatorname{Reconst}((\widehat{\operatorname{data}}_{i})_{i\in I}). $$

Analysis. Next, we analyze the construction given above. Namely, we show completeness, soundness, and consistency. For analyzing completeness and soundness, we rely on the quality of the index sampler in combination with the reception efficiency of C. Namely, reception efficiency tells us how many of the N indices we need to recover the data. Then, the quality of the index sampler gives a bound on the probability that we did not collect enough indices when we have a certain number of clients with a certain number of queries. This determines the threshold of the scheme, i.e., the number of clients needed to make the completeness and soundness error negligible. For soundness, we additionally need to rule out the case that we collected enough indices, but the responses of the adversary at these indices are not consistent with the code. For that, we can use code-binding of the commitment scheme. To show consistency, we rely on reconstruction-binding of the commitment scheme.

Lemma 8. The scheme DAS[CC, Sample] satisfies completeness, if

 $$ \nu(\Delta,N,Q,T)\leq\mathsf{n e g l}(\lambda),{~w h e r e~}\Delta:=t-1. $$

Proof. Let $\ell = \text{poly}(\lambda)$, $\ell \geq T$ and data $\in \Gamma^K$ as in the definition of completeness. First, by the completeness of $\text{CC}$, we know that the $\ell$ copies of $\mathbf{V}_2$ output 1 in the completeness experiment, except with negligible probability. Thus, it remains to bound the probability of the bad event that $\text{Ext}$ outputs $\perp$ because not enough indices are covered, i.e. the set $I \subseteq [N]$ of indices $i \in [N]$ such that there is a $(l,j) \in [L] \times [Q]$ with $i_{l,j} = i$ has size strictly less than $t$. This is equivalent to saying it has size at most $\Delta$. Clearly, if we only consider the first $T$ instead of all $\ell \geq T$ transcripts, the size of this set can not increase. As the indices are sampled using $\text{Sample}$, one can easily verify that the probability of the bad event is at most the probability that

 $$ \left|\bigcup_{l\in[T]}\{i_{l,j}\mid j\in[Q]\}\right|\leq\Delta, $$

where  $ (i_{l,j})_{j\in[Q]}\leftarrow\mathsf{Sample}(1^{Q},1^{N}) $ for all  $ l\in[T] $. By definition of the quality of  $ \mathsf{Sample} $, this is at most  $ \nu(\Delta,N,Q,T) $.

Lemma 9. Assume that CC is code-binding and  $ \nu(\Delta, N, Q, T) $ is negligible for  $ \Delta := t - 1 $. Then, the scheme DAS[CC, Sample] satisfies soundness. Concretely, for any PPT algorithm A there is a PPT algorithm B with  $ \mathbf{T}(\mathcal{B}) \approx \mathbf{T}(\mathcal{A}) $ such that for any  $ \ell \geq T $ we have

 $$ \begin{array}{r}{\mathrm{A d v}_{\mathcal{A},\ell,\mathrm{D A S}[\mathrm{C C},\mathrm{S a m p l e}]}^{\mathrm{s o u n d}}(\lambda)\leq\nu(\Delta,N,Q,T)+\mathrm{A d v}_{\mathcal{B},\mathrm{C C}}^{\mathrm{c o d e-b i n d}}(\lambda).}\end{array} $$

Proof. Consider an adversary $\mathcal{A}$ against soundness of DAS[CC, Sample]. We first recall the soundness game and introduce some notation. First, parameters par := ck ← Setup($1^\lambda$) are sampled and given to $\mathcal{A}$. Then, $\mathcal{A}$ outputs a commitment $\text{com}$. Then, $\ell$ copies of $V_1$ are run and their oracle queries are answered by $\mathcal{A}$. Let $\text{tran}_l = (i_{l,j}, \widehat{\text{data}}_{i,i_j}, \tau_{l,i_{j}})_{j \in i_l}$ for $l \in [\ell]$ be the respective transcripts. The adversary $\mathcal{A}$ breaks soundness if all of these verify, i.e., for all $l \in [\ell]$ and all $j \in [Q]$ we have $\text{Ver}(\text{ck}, \text{com}, i_{l,j}, \widehat{\text{data}}_{i,i_j}, \tau_{l,i_{l,j}}) = 1$, and $\text{Ext}(\text{com}, \text{tran}_1, \ldots, \text{tran}_\ell)$ outputs $\bot$. Recall that $\text{Ext}$ outputs $\bot$ either because a transcript does not verify, or the set $I \subseteq [N]$ of covered indices is not large enough, i.e., $|I| < t$, or if algorithm $\text{Reconst}$ outputs $\bot$. We analyze the game by considering these cases separately. Namely, we define the following events.

- Event InvalidTrans: This event occurs, if A breaks soundness and Ext outputs ⊥ because a transcript does not verify.

• Event NotEnough: This event occurs, if A breaks soundness and Ext outputs ⊥ because  $ |I| < t $.

- Event Inconsistent: This event occurs, if A breaks soundness and Ext outputs ⊥ because algorithm Reconst outputs ⊥.

It is clear that

 $$  Adv_{\mathcal{A},\ell,D A S[C C,S a m p l e]}^{s o u n d}(\lambda)\leq\operatorname{P r}\left[In v a l i d T r a n s\right]+\operatorname{P r}\left[N o t E n o u g h\right]+\operatorname{P r}\left[I n c o n s i s t e n t\right]. $$

We bound these three terms separately. First, it is clear that event  $ \text{InvalidTrans} $ can not occur. This is because if one transcript does not verify,  $ \mathcal{A} $ never wins by definition. Second, if all copies of  $ V_2 $ output 1, i.e. all transcripts are accepting, we can argue exactly as in the analysis of completeness. That is, using the quality of Sample, we rule out that not enough indices are covered and  $ \text{Ext outputs} \perp $. We get that the probability of  $ \text{NotEnough} $ is at most  $ \nu(\Delta, N, Q, T) $. Finally, we have to bound the probability of  $ \text{Inconsistent} $. Recall that algorithm  $ \text{Reconst outputs} \perp $ if either not enough symbols are input, or if its input is not consistent with any codeword. The first case can not happen, as in this case  $ \text{Ext} $ would have output  $ \perp $ because of  $ |I| < t $ and  $ \text{Reconst} $ would not have been run. The second case easily reduces to code-binding. Namely, a reduction  $ \mathcal{B} $ can run  $ \mathcal{A} $ in the soundness game while forwarding its input  $ c_k $ to  $ \mathcal{A} $. Then, if  $ \text{Inconsistent} $ occurs,  $ \mathcal{B} $ knows valid openings that are not consistent with a codeword, and can output these openings to break codebinding. We get that

 $$ \operatorname*{P r}\left[\mathsf{I n c o n s i s t e n t}\right]\leq\mathsf{A d v}_{\mathcal{B},\mathsf{C C}}^{\mathsf{c o d e-b i n d}}(\lambda). $$

Lemma 10. If CC is reconstruction-binding, then DAS[CC, Sample] satisfies consistency. Concretely, for any PPT algorithm A there is a PPT algorithm B with  $ \mathbf{T}(\mathcal{B}) \approx \mathbf{T}(\mathcal{A}) $ such that for any  $ \ell_1, \ell_2 = \mathsf{poly}(\lambda) $, we have

 $$ \mathsf{A d v}_{\mathcal{A},\ell_{1},\ell_{2},\mathsf{D A S}[\mathsf{C C},\mathsf{S a m p l e}]}^{\mathsf{c o n s}}\leq\mathsf{A d v}_{\mathcal{B},\mathsf{C C}}^{\mathsf{r e c-b i n d}}(\lambda). $$

Proof. Let $\mathcal{A}$ be an algorithm running in the consistency game of DAS[CC, Sample]. We construct a reduction $\mathcal{B}$ that simulates the consistency game for $\mathcal{A}$ and breaks reconstruction-binding of CC if $\mathcal{A}$ breaks consistency. Namely, the reduction $\mathcal{B}$ gets as input a commitment key ck, sets par := ck, and runs $\mathcal{A}$ on input par as in the consistency game. Then, $\mathcal{A}$ outputs (com, (tran$_{1,i})_{i=1}^{\ell_{1}}, (\operatorname{tran}_{2,i})_{i=1}^{\ell_{2}})$. We use the notation

$I_j$, $\widehat{\text{data}}_{j,i}$ for the variables $I$, $\text{data}_i$ as in Ext for the $j$th extraction, $j \in \{1,2\}$. The reduction $\mathcal{B}$ outputs $\text{com}$, $\left(\widehat{\text{data}}_{1,i}, \tau_{1,i}\right)_{i \in I_1}$, $\left(\widehat{\text{data}}_{2,i}, \tau_{2,i}\right)_{i \in I_2}$. It remains to argue that $\mathcal{B}$ breaks reconstruction-binding, assuming that $\mathcal{A}$ breaks consistency. For that, assume both extractions $\text{Ext}(\text{com}, \text{tran}_{1,1}, \ldots, \text{tran}_{1,\ell_1})$ and $\text{Ext}(\text{com}, \text{tran}_{2,1}, \ldots, \text{tran}_{2,\ell_2})$ do not output $\bot$, and they output data$_1 \neq \text{data}_2$. As both extractions did not output $\bot$, the transcripts must contain valid openings $\tau_{1,i}$ such that $\text{Ver}(\text{ck}, \text{com}, i, \widehat{\text{data}}_{1,i}, \tau_{1,i}) = 1$ for all $i \in I_1$, and $\tau_{2,i}$ such that $\text{Ver}(\text{ck}, \text{com}, i, \widehat{\text{data}}_{2,i}, \tau_{2,i}) = 1$ for all $i \in I_2$. Also, it must hold that $|I_1| \geq t$ and $|I_2| \geq t$. This is by definition of algorithm Ext. In combination with data$_1 \neq \text{data}_2$, this implies that $\mathcal{B}$ breaks reconstruction-binding.

Local Accessibility. Now, assume that C has a generalized systematic encoding with symbol projection algorithm Proj and symbol finding algorithm Find. Then, we show that our generic construction DAS[CC, Sample] is locally accessible with optimal query complexity L = 1. For that, we define algorithm Access as follows.

 $$ \bullet \quad \mathsf{A c c e s s}^{\pi,L}(\mathsf{c o m},i)\to d/\perp: $$

1. Compute  $ \hat{i} := \text{Find}(i) $ and query  $ (\widehat{\text{data}}_{\hat{i}}, \tau_{\hat{i}}) := \pi_{\hat{i}} $.

2. If  $ \mathrm{Ver}(\mathrm{ck}, \mathrm{com}, \hat{i}, \widehat{\mathrm{data}}_{\hat{i}}, \tau_{\hat{i}}) = 0 $, return  $ \perp $. Otherwise, return  $ \mathrm{Proj}(i, \widehat{\mathrm{data}}_{\hat{i}}) $.

By the first part of the definition of a generalized systematic encoding and the completeness of CC, it is easy to see that local access completeness holds. We show that local access consistency holds.

Lemma 11. Assume that CC is reconstruction-binding and C has a generalized systematic encoding. Then, DAS[CC, Sample] with algorithm Access satisfies local access consistency. Concretely, for any PPT algorithm A there is a PPT algorithm B with  $ \mathbf{T}(\mathcal{B}) \approx \mathbf{T}(\mathcal{A}) $ such that for any  $ i_0 \in [K] $, and any  $ \ell = \text{poly}(\lambda) $, we have

 $$ \mathrm{A d v}_{\mathcal{A},i_{0},\ell,\mathrm{D A S},\mathrm{A c c e s s}}^{\mathrm{a c c-c o n s}}(\lambda)\leq\mathrm{A d v}_{\mathcal{B},\mathrm{C C}}^{\mathrm{r e c-b i n d}}(\lambda). $$

The proof of Lemma 11 is given in Appendix F.3.

Repairability. Now, assume that CC has message-bound openings. Then, we show that our generic construction DAS[CC, Sample] is  $ (L, \ell) $-repairable, provided that it satisfies  $ (L, \ell) $-subset-soundness. For that, we define algorithm Repair as follows.

• Repair(com, tran₁, ..., tranₚ) → π/⊥:

1. Run  $ \overline{\text{data}} := \text{Ext}(\text{com}, \text{tran}_1, \ldots, \text{tran}_\ell) $. If  $ \overline{\text{data}} := \bot $, return  $ \bot $.

2. Compute  $ (\bar{\pi}, \overline{\text{com}}) := \text{Encode}(\overline{\text{data}}) $ and return  $ \bar{\pi} $.

Lemma 12. If CC has message-bound openings and DAS[CC, Sample] satisfies $(L,\ell)$-subset-soundness, then DAS[CC, Sample] is $(L,\ell)$-repairable. Concretely, for any PPT algorithm $\mathcal{A}$ there are PPT algorithms $\mathcal{B}_1, \mathcal{B}_2$ with $\mathbf{T}(\mathcal{B}_1) \approx \mathbf{T}(\mathcal{B}_2) \approx \mathbf{T}(\mathcal{A})$ such that

 $$ \begin{array}{r}{\mathrm{A d v}_{\mathcal{A},L,\ell,\mathrm{D A S}[\mathrm{C C},\mathrm{S a m p l e}],\mathrm{R e p a i r}}^{\mathrm{r e p a i r l i v e}}(\lambda)\leq\mathrm{A d v}_{\mathcal{B}_{1},L,\ell,\mathrm{D A S}}^{\mathrm{s u b-s o u n d}}(\lambda)+\mathrm{A d v}_{\mathcal{B}_{2},\mathrm{C C}}^{\mathrm{m b-o p e n}}(\lambda).}\end{array} $$

The proof of Lemma 12 is given in Appendix F.3.

## 7 Commitments for Arbitrary Codes

In this section, we show how to construct an erasure code commitment scheme for any erasure code from a vector commitment and a non-interactive argument of knowledge. The idea is simple. We encode the message and commit to the encoding using a vector commitment. Then, we prove that we committed to a valid codeword. The vector commitment and the proof will form our erasure code commitment, and openings will correspond to openings of the vector commitment.

Supported Erasure Code. The scheme presented in this section works generically for an arbitrary erasure code. Throughout the section, we let $\mathcal{C}:\Gamma^k \to \Lambda^n$ be an erasure code with alphabets $\Gamma$, $\Lambda$, message length $k$, code length $n$, and reception efficiency $t$, with reconstruction algorithm Reconst.

Commitment Construction. Let VC = (Setup, Com, Open, Ver) be a vector commitment scheme over alphabet  $ \Lambda $ with length n and opening alphabet  $ \Xi $, and let PS = (Setup, PProve, PVer) be a non-interactive argument of knowledge for relation

 $$ \mathcal{R}:=\left\{(stmt,witn)\middle|\begin{array}{c}witn=m,stmt=(ck_{VC},com_{VC},\rho),\\\exists St_{VC}:(com_{VC},St_{VC})=VC.Com(ck_{VC},\mathcal{C}(m);\rho)\end{array}\right\}. $$

We construct an erasure code commitment scheme CC[C, VC, PS] = (Setup, Com, Open, Ver) for C with opening alphabet  $ \Xi $ as follows.

 $$ \bullet \quad \mathsf{S e t u p}(1^{\lambda})\to\mathsf{c k}\colon $$

1. Compute  $  \text{ck}_{VC} \leftarrow \text{VC.Setup}(1^\lambda)  $ and  $  \text{crs} \leftarrow \text{PS.Setup}(1^\lambda)  $.

2. Sample coins  $ \rho $ for algorithm VC.Com.

3. Set and return  $  \text{ck} := (\text{ck}_{VC}, \text{crs}, \rho)  $.

• Com(ck, m) → (com, St):

1. Compute  $ \hat{m} := \mathcal{C}(m) $.

 $$ 2.\ \mathrm{Run}\ (\mathrm{com}_{\mathrm{VC}},\mathrm{St}_{\mathrm{VC}}):=\mathrm{VC}.\mathrm{Com}(\mathrm{ck}_{\mathrm{VC}},\hat{m};\rho). $$

3. Compute  $ \pi \leftarrow \text{PProve(crs, stmt, witn)} $ for witn := m and stmt := (ckvc, comvc,  $ \rho $).

4. Set and return  $ \text{com} := (\text{com}_{\text{VC}}, \pi) $ and  $ St := St_{\text{VC}} $.

• Open(ck, St, i) → τ: Return τ ← VC.Open(ck_VC, St_VC, i).

• Ver(ck, com, i,  $ \hat{m}_i $,  $ \tau $)  $ \rightarrow $ b

1. Parse com = (comvc,  $ \pi $)

2. If PVer(crs, stmt,  $ \pi $) = 0 for stmt := (ckvc, comvc,  $ \rho $), then return b := 0.

3. If VC.Ver(ckvc, comvc, i,  $ \hat{m}_i $,  $ \tau $) = 0, then return b := 0.

4. Return b := 1.

Completeness follows directly from the completeness of VC and PS.

Security. We show that the construction CC[C, VC, PS] above is position-binding and code-binding. In addition, we show that it has message-bound openings. To recall, the notion of message-bound openings (cf. Definition 22) implies repairability for the resulting data availability sampling scheme. In the following, let PS.Ext be the knowledge extractor of PS.

Lemma 13. If VC is position-binding, then CC[C, VC, PS] is position-binding. Concretely, for any PPT algorithm A, there is a PPT algorithm B with  $ \mathbf{T}(\mathcal{B}) \approx \mathbf{T}(\mathcal{A}) $ and

 $$ \begin{array}{r}{\mathrm{A d v}_{\mathcal{A},\mathrm{C C}[\mathcal{C},\mathrm{V C},\mathrm{P S}]}^{\mathrm{p o s-b i n d}}(\lambda)\leq\mathrm{A d v}_{\mathcal{B},\mathrm{V C}}^{\mathrm{p o s-b i n d}}(\lambda).}\end{array} $$

Proof. Let $\mathcal{A}$ be an algorithm breaking position-binding of $\mathsf{CC}[\mathcal{C},\mathsf{VC},\mathsf{PS}]$. We construct an algorithm $\mathcal{B}$ breaking position-binding of $\mathsf{VC}$. It gets as input a commitment key $\mathsf{ck}_{\mathsf{VC}}$ for $\mathsf{VC}$. It computes $\mathsf{crs} \leftarrow \mathsf{PS}.\mathsf{Setup}(1^\lambda)$ and samples coins $\rho$ for algorithm $\mathsf{VC}.\mathsf{Com}$. Then, it defines $\mathsf{ck} := (\mathsf{ck}_{\mathsf{VC}},\mathsf{crs},\rho)$ and runs $\mathcal{A}$ on input $\mathsf{ck}$. Finally, $\mathcal{A}$ outputs $(\mathsf{com} = (\mathsf{com}_{\mathsf{VC}},\pi), i, \hat{m}, \tau, \hat{m}', \tau')$ and the reduction $\mathcal{B}$ outputs $(\mathsf{com}_{\mathsf{VC}}, i, \hat{m}, \tau, \hat{m}', \tau')$. As $\mathsf{Ver}$ internally runs $\mathsf{VC}.\mathsf{Ver}$, it is clear that $\mathcal{B}$ breaks position-binding of $\mathsf{VC}$ if $\mathcal{A}$ breaks position-binding of $\mathsf{CC}[\mathcal{C},\mathsf{VC},\mathsf{PS}]$.

Lemma 14. If VC is position-binding and PS satisfies knowledge soundness, then CC[C, VC, PS] is code-binding. Concretely, for any PPT algorithm A, there are PPT algorithms  $ B_1, B_2 $ with  $ \mathbf{T}(\mathcal{B}_1) \approx \mathbf{T}(\mathcal{A}) $.  $ \mathbf{T}(\mathcal{B}_2) \approx \mathbf{T}(\mathcal{A}) + \mathbf{T}(\text{PS.Ext}) + \mathbf{T}(C) $, and

 $$ \begin{array}{r}{\mathrm{A d v}_{\mathcal{A},\mathrm{C C}[\mathcal{C},\mathrm{V C},\mathrm{P S}]}^{\mathrm{c o d e-b i n d}}(\lambda)\leq\mathrm{A d v}_{\mathcal{B}_{1},\mathrm{P S},\mathrm{P S}.\mathrm{E x t}}^{\mathrm{k n-s o u n d}}(\lambda)+\mathrm{A d v}_{\mathcal{B}_{2},\mathrm{V C}}^{\mathrm{p o s-b i n d}}(\lambda).}\end{array} $$

We postpone a formal proof to Appendix G. The intuition is as follows. Assume an adversary breaks code-binding of the scheme. This means the adversary outputs a commitment  $ \text{com} $ and some openings, such that these openings are valid, but they are not consistent with the code. In the first step, we extract a witness from the proof contained in  $ \text{com} $. This witness is a message  $ m $ such that the vector commitment part of  $ \text{com} $ is a commitment of  $ \mathcal{C}(m) $. Because the openings are not consistent with the code, we know that at least one of these openings is not consistent with the symbol of  $ \mathcal{C}(m) $ at this position, which allows us to break position-binding.

Lemma 15. If VC is position-binding and PS satisfies knowledge soundness, then CC[C, VC, PS] has message-bound openings. Concretely, for any PPT algorithm A, there are PPT algorithms  $ B_1, B_2 $ with  $ \mathbf{T}(\mathcal{B}_1) \approx \mathbf{T}(\mathcal{A}) $,  $ \mathbf{T}(\mathcal{B}_2) \approx \mathbf{T}(\mathcal{B}_3) \approx \mathbf{T}(\mathcal{A}) + 2 \cdot \mathbf{T}(\text{PS.Ext}) + 2 \cdot \mathbf{T}(C) $, and

 $$ \begin{array}{r}{\mathrm{A d v}_{\mathcal{A},\mathrm{C C}}^{\mathrm{m b-o p e n}}(\lambda)\leq2\cdot\mathrm{A d v}_{\mathcal{B}_{1},\mathrm{P S},\mathrm{P S.E x t}}^{\mathrm{k n-s o u n d}}(\lambda)+\mathrm{A d v}_{\mathcal{B}_{2},\mathrm{V C}}^{\mathrm{p o s-b i n d}}(\lambda).}\end{array} $$

We postpone a formal proof to Appendix G.

Instantiation and Discussion. On the positive side, the construction presented in this section is generic. That is, we can construct an erasure code commitment for arbitrary codes from it. Also, the construction serves as a high level recipe for other constructions that we will present. While these other constructions are tailored to more specific families of codes, they will also contain parts that mimic the role of the vector commitment, and parts that take the role of the proof. On the negative side the construction presented in this section is hard to instantiate efficiently. For example, if we use a hash-based vector commitment, e.g., a Merkle Tree [Mer88], then the relation for which we need a non-interactive argument is also defined a hash function, and thus it is too unstructured for an efficient argument. Additionally, computing the non-interactive argument is computationally expensive. Finally, well-known impossibility results [GW11, CGKS22] show the need of non-falsifiable assumptions when we rely on succinct non-interactive arguments.

## 8 Commitments for Tensor Codes

In this section, we give a construction of an erasure code commitment scheme for the tensor code of two given linear codes.

Supported Erasure Code. For our construction, we assume two linear erasure codes  $ \mathcal{C}_r: \mathbb{F}^{k_r} \to \mathbb{F}^{n_r} $ and  $ \mathcal{C}_c: \mathbb{F}^{k_c} \to \mathbb{F}^{n_c} $ over the same field  $ \mathbb{F} $. Let  $ t_r, t_c $ denote their respective reception efficiencies, and  $ \mathbf{G}_r \in \mathbb{F}^{n_r \times k_r} $ and  $ \mathbf{G}_c \in \mathbb{F}^{n_c \times k_c} $ denote their respective generator matrices. We consider the tensor code  $ \mathcal{C}_r \otimes \mathcal{C}_c $:  $ \mathbb{F}^{k_r \cdot k_c} \to \mathbb{F}^{n_r \cdot n_c} $.

Commitment Construction. We present an erasure code commitment scheme  $ CC^{\otimes} $ for the code  $ C_r \otimes C_c $:  $ \mathbb{F}^{k_r \cdot k_c} \to \mathbb{F}^{n_r \cdot n_c} $ as above. In the construction, we assume that we already have an erasure code commitment scheme  $ CC_c $ for the code  $ C_c $. Further, we have to assume that  $ CC_c $ is linear and extractable, in a sense we define next.

Definition 14 (Linear Erasure Code Commitment Scheme). Let $\mathcal{C}:\mathbb{F}^k \to \mathbb{F}^n$ be a linear erasure code, where $\mathbb{F}$ is a finite field. Let $\mathbb{C} = (\text{Setup}, \text{Com}, \text{Open}, \text{Ver})$ be an erasure code commitment scheme for $\mathcal{C}$. We say that $\mathbb{C}$ is linear if the following properties hold:

• Com is deterministic. We use the notation  $ \text{com} = \text{Com}(\text{ck}, \mathbf{m}) $ for  $ (\text{com}, St) = \text{Com}(\text{ck}, \mathbf{m}) $.

- The commitment space is a vector space over F with efficiently computable vector addition and scalar multiplication. We use the usual symbols + and · to denote these operations.

• For any fixed key  $ c_k \in \text{Setup}(1^\lambda) $, the function  $ \text{Com}(c_k, \cdot) $ is a vector space homomorphism over  $ \mathbb{F} $ from the vector space  $ \mathbb{F}^k $ to the commitment space.

From now on, assume that  $ CC_c = (\text{Setup}_c, \text{Com}_c, \text{Open}_c, \text{Ver}_c) $ is linear and extractable. The new erasure code commitment scheme  $ CC^\otimes = (\text{Setup}^\otimes, \text{Com}^\otimes, \text{Open}^\otimes, \text{Ver}^\otimes) $ for code  $ C_r \otimes C_c: \mathbb{F}^{k_r \cdot k_c} \to \mathbb{F}^{n_r \cdot n_c} $ is as follows.

• Setup $ ^{\otimes}(1^{\lambda}) \rightarrow ck $: Return  $ c k \leftarrow Setup_c(1^{\lambda}) $.

•  $  \text{Com}^\otimes(\text{ck}, \mathbf{m}) \to (\text{com}, St)  $:

1. Write  $ \mathbf{m} $ as a matrix  $ \mathbf{M} \in \mathbb{F}^{k_c \times k_r} $ and compute  $ \mathbf{Y} := \mathbf{M}\mathbf{G}_r^\top \in \mathbb{F}^{k_c \times n_r} $. Let  $ \mathbf{Y}_j \in \mathbb{F}^{k_c} $ denote the  $ i $th column of  $ \mathbf{Y} $, for each  $ j \in [n_r] $.

2. For each  $ j \in [n_r] $, compute  $ (\text{com}_j, St_j) := \text{Com}_c(\text{ck}, \mathbf{Y}_j) $.

3. Set and return  $ \text{com} := (\text{com}_1, \ldots, \text{com}_{n_r}) $ and  $ St := (St_1, \ldots, St_{n_r}) $.

• Open $ ^{\otimes} $(ck, St, j)  $ \rightarrow $  $ \tau $: Let  $ (i^{*}, j^{*}) := \text{ToMatIdx}(j) $ and return  $ \tau \leftarrow \text{Open}_c(\text{ck}, St_j^{*}, i^{*}) $.

• Ver $ ^{\otimes} $(ck, com, j,  $ \hat{m}_{j} $,  $ \tau $)  $ \rightarrow $ b:

1. Let  $ \text{com} = (\text{com}_1, \ldots, \text{com}_{n_r}) $.

2. Let  $ \mathbf{H} \in \mathbb{F}^{(n_r - k_r) \times n_r} $ be the parity-check matrix of  $ C_r $.

3. Sample  $ \mathbf{a} \leftarrow \mathbf{s} \mathbb{F}^{n_r - k_r} $ and set  $ \mathbf{h} := \mathbf{H}^\top \mathbf{a} $.

4. If  $ \widehat{\text{Com}_c(\text{ck}, \mathbf{0})} \neq \sum_{i=1}^{n_r} \mathbf{h}_j \cdot \text{com}_j $, return 0.

5. Let  $ (i^{*}, j^{*}) := \text{ToMatIdx}(j) $.

6. If  $ \text{Ver}_c(\text{ck}, \text{com}_j*, i*, \hat{m}_j, \tau) = 0 $, return 0.

Completeness follows directly from the completeness and linearity of CC.

Security. We first show that the scheme CC $ ^{\otimes} $ satisfies position-binding. Second, we show that it is computationally unique (cf. Definition 23). By Lemma 27, this implies that it has message-bound openings, and thus the resulting data availability sampling scheme is repairable. Note that the tensor code is not an MDS code, and so Lemma 28, which lifts computational uniqueness to code-binding, does not apply. Thus, we show code-binding from scratch.

Lemma 16. If  $ CC_c $ is position-binding, then  $ CC^\otimes $ is position-binding. Concretely, for every PPT algorithm  $ \mathcal{A} $, there is a PPT algorithm  $ \mathcal{B} $ with  $ \mathbf{T}(\mathcal{B}) \approx \mathbf{T}(\mathcal{A}) $, such that

 $$ \mathrm{A d v}_{\mathcal{A},\mathsf{C C}^{\otimes}}^{\mathsf{p o s-b i n d}}(\lambda)\leq\mathrm{A d v}_{\mathcal{B},\mathsf{C C}_{c}}^{\mathsf{p o s-b i n d}}(\lambda). $$

Lemma 16 is proven by giving a simple reduction. We postpone the formal details to Appendix H.

Lemma 17. Assume that $\mathcal{C}_c$ is an MDS code. If $\mathsf{CC}_c$ is linear, extractable, and satisfies position-binding, then $\mathsf{CC}^\otimes$ is computationally unique. Concretely, for every PPT algorithm $\mathcal{A}$, there are PPT algorithms $\mathcal{B}$, $\mathcal{B}'$ with $\mathbf{T}(\mathcal{B}) \approx \mathbf{T}(\mathcal{B}') \approx \mathbf{T}(\mathcal{B}'') \approx \mathbf{T}(\mathcal{A})$, such that

 $$ \mathsf{A d v}_{\mathcal{A},\mathsf{C C}^{\otimes}}^{\mathsf{c-uniq}}(\lambda)\leq2\left(\mathsf{A d v}_{\mathcal{B},\mathsf{E x t},\mathsf{C C}_{c}}^{\mathsf{e x t r}}(\lambda)+\mathsf{A d v}_{\mathcal{B}^{\prime},\mathsf{C C}_{c}}^{\mathsf{p o s-b i n d}}(\lambda)+\frac{1}{|\mathbb{F}|}\right). $$

The formal proof of Lemma 17 is given in Appendix H. We provide an intuition for the proof. To prove that the scheme is computationally unique, we prove a simpler yet stronger statement. Namely, we show that whenever an adversary outputs a commitment  $ \text{com} = (\text{com}_1, \ldots, \text{com}_{n_r}) $ and enough valid openings  $ \mathbf{X}_{i,j} \in \mathbb{F}, \tau_{i,j} $ for  $ (i,j) \in I \subseteq [n_c] \times [n_r] $ that define a message  $ \mathbf{M} \in \mathbb{F}^{k_c \times k_r} $ via reconstruction, then committing to  $ \mathbf{M} $ yields  $ \text{com} $. To prove this, we first consider every column  $ j \in [n_r] $ for which the adversary outputs an opening. In the first  $ k_r $ of these columns, we leverage the extractability of  $ \mathbf{C}\mathbf{C}_c $ to extract a preimage of the corresponding column commitment  $ \text{com}_j $. Now, we can extend these columns into a matrix  $ \mathbf{Y} $ with rows in  $ \mathcal{C}_r $. Our next step is to show that the columns of  $ \mathbf{Y} $ commit to the  $ \text{com}_j $. For that, we rely on the homomorphic check and the fact that multiplying by a random element in the span of the parity-check matrix of  $ \mathcal{C}_r $ is as good as multiplying by the entire parity-check matrix. Next, we use position-binding to argue that the  $ \mathbf{G}_c\mathbf{Y} $ has to be consistent with the openings  $ \mathbf{X}_{i,j} $ that the adversary outputs. Finally, we use this to argue that  $ \mathbf{Y} = \mathbf{M}\mathbf{G}_r^\top $. In combination, this implies that committing to  $ \mathbf{M} $ yields  $ \text{com} $, as desired.

Lemma 18. Assume that $\mathcal{C}_c$ is an MDS code. If $\mathsf{CC}_c$ is linear, extractable, and satisfies code-binding and position-binding, then $\mathsf{CC}^\otimes$ satisfies code-binding. Concretely, for every PPT algorithm $\mathcal{A}$, there are PPT algorithms $\mathcal{B}, \mathcal{B}'$ with $\mathbf{T}(\mathcal{B}) \approx \mathbf{T}(\mathcal{B}') \approx \mathbf{T}(\mathcal{B}'') \approx \mathbf{T}(\mathcal{A})$, such that

 $$ \begin{array}{r}{\mathsf{A d v}_{\mathcal{A},\mathsf{C C}^{\otimes}}^{\mathrm{c o d e-b i n d}}(\lambda)\leq\mathsf{A d v}_{\mathcal{B},\mathsf{C C}_{c}}^{\mathrm{c o d e-b i n d}}(\lambda)+\mathsf{A d v}_{\mathcal{B}^{\prime},\mathsf{E x t},\mathsf{C C}_{c}}^{\mathrm{e x t r}}(\lambda)+\mathsf{A d v}_{\mathcal{B}^{\prime\prime},\mathsf{C C}_{c}}^{\mathrm{p o s-b i n d}}(\lambda)+\frac{1}{|\mathbb{F}|}.}\end{array} $$

We provide an intuition for proof of Lemma 18. The formal analysis is given in Appendix H. Assume that an adversary breaks code-binding. By definition, this means that it outputs a commitment  $ com = (com_1, \ldots, com_{n_r}) $ and some openings, such that all of the openings verify, and no codeword in  $ C_r \otimes C_c $ is consistent with these openings. In particular, there is at least one row or one column for which the openings are not consistent with any codeword in  $ C_r $ or  $ C_c $, respectively. Consider the case that there is such a column. As  $ com $ contains a commitment to that column for scheme  $ CC_c $, this means that the adversary breaks code-binding of  $ CC_c $, which we assume is not possible. In the other case, the adversary outputs openings in a row that are not consistent with  $ C_r $. This case is more involved, because there are no commitments for rows in  $ com $. It turns out that we can handle this case in a way almost identical to the proof of Lemma 17. Roughly, we can combine the strong statement that we showed there with the assumption that  $ C_r $ is an MDS code and binding of  $ CC_c $.

Instantiation and Discussion. As an example, we can instantiate the construction in this section using Reed-Solomon codes for both  $ C_r $ and  $ C_c $. In this case, we need an extractable linear polynomial commitment scheme for the construction. Here, we can use the KZG commitment scheme [KZG10]. One can easily see that KZG is extractable and linear, see Appendix E.3. An instantiation like this is used by Ethereum [Fei23]. One advantage of this construction is that the size of openings is constant, i.e., it does not depend on the data length. The main drawback in this case is that we rely on a trusted setup.

## 9 Commitments for Interleaved Codes

In this section, we show two constructions of erasure code commitments for linear interleaved codes. These construction are partially inspired by Ligero [AHIV17, AHIV22] and mostly make use of hash functions.

### 9.1 Construction from Hash Functions

In this section, we present a construction of erasure code commitments for linear interleaved codes. The main benefit of this construction is that we can purely rely on hash functions.

Supported Erasure Code. Let $\mathcal{C}:\mathbb{F}^k \to \mathbb{F}^n$ be a linear erasure code with generator matrix $\mathbf{G} \in \mathbb{F}^{n \times k}$ and minimum distance $d^* \in \mathbb{N}$. We construct an erasure code commitment for the interleaved code $\mathcal{C}^{\equiv k}:\mathbb{F}^{k^2} \to (\mathbb{F}^k)^n$. To recall, this code consists of all sets of columns of matrices that have the form $\mathbf{M}\mathbf{G}^\top$ for some $\mathbf{M} \in \mathbb{F}^{k \times k}$.

Commitment Construction. Let H: $\{0,1\}^* \to \{0,1\}^\lambda$ be a random oracle. Let $P, L \in \mathbb{N}$ be parameters, and $H_1: \{0,1\}^* \to \mathbb{F}^{P \times k}$ be a random oracle. Also, let $H_2: \{0,1\}^* \to \binom{[n]}{L}$ be a random oracle. We construct an erasure code commitment scheme $\mathsf{CC} = (\mathsf{Setup}, \mathsf{Com}, \mathsf{Open}, \mathsf{Ver})$ for $\mathcal{C}^{\equiv k}$. The construction is as follows, making use of subroutines VerCol and VerCom.

• Setup( $ 1^\lambda $) → ck: Return ck := ⊥.

• Com(ck, m) → (com, St):

1. Write  $ \mathbf{m} $ as a matrix  $ \mathbf{M} \in \mathbb{F}^{k \times k} $, and compute  $ \mathbf{X} := \mathbf{M}\mathbf{G}^\top \in \mathbb{F}^{k \times n} $. Let  $ \mathbf{X}_j \in \mathbb{F}^k $ for  $ j \in [n] $ be the  $ j $th column of  $ \mathbf{X} $.

2. For each  $ j \in [n] $, compute  $ h_j := \mathsf{H}(\mathbf{X}_j) $.

3. Compute  $ \mathbf{R} := \mathbf{H}_1(h_1, \ldots, h_n) $. We have  $ \mathbf{R} \in \mathbb{F}^{P \times k} $

4. Compute linear combinations of rows, i.e.,  $ \mathbf{W} := \mathbf{R}\mathbf{X} \in \mathbb{F}^{P \times n} $. Observe that each row of  $ \mathbf{W} $ is in the code  $ \mathcal{C} $.

5. Compute  $ J := H_2(h_1, \ldots, h_n, \mathbf{W}) $. We have  $ J \subseteq [n] $ and  $ |J| = L $.

6. Set  $ \complement = \left((h_j)_{j \in [n]}, \mathbf{W}, (\mathbf{X}_j)_{j \in J}\right) $ and  $ St := \perp $.

• Open(ck, St, j) → τ: Return τ := ⊥.

• Ver(ck, com,  $ j^* $,  $ \hat{m}_j^* = \mathbf{X}_{j^*}, \tau = \perp $)  $ \rightarrow $ b:

1. If  $ \text{VerCol}(\text{ck}, \text{com}, j^{*}, \mathbf{X}_{j^{*}}) = 0 $, return 0, where subroutine  $ \text{VerCol}(\text{ck}, \text{com}, j^{*}, \mathbf{X}_{j^{*}}) $ is as follows:

(a) Let  $ \complement = \big((h_j)_{j \in [n]},\mathbf{W},(\mathbf{X}_j)_{j \in J}\big) $.

(b) If  $ h_{j^{*}} \neq H(\mathbf{X}_{j^{*}}) $, return 0.

(c) Compute  $ \mathbf{R} := \mathbf{H}_1(h_1, \ldots, h_n) $.

(d) Let  $ W_j^* $ be the  $ j^* $th column of W. If  $ W_j^* \neq RX_j^* $, return 0. Otherwise, return 1.

2. If VerCom(ck, com) = 0, return 0, where subroutine VerCom(ck, com) is as follows:

 $$ \begin{array}{r}{(\mathrm{a})\mathrm{~L e t~}\mathrm{c o m}=\big((h_{j})_{j\in[n]},\mathbf{W},(\mathbf{X}_{j})_{j\in J}\big).}\end{array} $$

(b) If there is a row  $ \mathbf{w}^\top \in \mathbb{F}^{1 \times n} $ of  $ \mathbf{W} $ such that  $ \mathbf{w} \notin \mathcal{C} $, then return 0.

(c) If  $ J \neq H_2(h_1, \ldots, h_n, \mathbf{W}) $, return 0.

(d) Return 1, if for all  $ j \in J $, we have  $ \text{VerCol}(ck, \text{com}, j, \mathbf{X}_j) = 1 $. Otherwise, return 0.

3. Return 1.

Completeness can easily be checked.

Security. We show position-binding and code-binding of our construction.

Lemma 19. Let H: {0,1}^* → {0,1}^λ be a random oracle. Then, the scheme CC is position-binding. Concretely, for every algorithm A that makes at most Q_H queries to random oracle H, we have

 $$ \mathrm{A d v}_{\mathcal{A},\mathrm{C C}}^{\mathrm{p o s-b i n d}}(\lambda)\leq\frac{Q_{\mathrm{H}}^{2}}{2^{\lambda}}. $$

Proof. If we have an adversary that breaks position-binding of CC, then it must provide two distinct preimages of one of the hash values contained in the commitment. Formally, let $\mathcal{A}$ be an algorithm in the position-binding game of CC making at most $Q_{\mathsf{H}}$ queries to random oracle $\mathsf{H}$. This includes the queries that algorithm $\mathsf{Ver}$ issues when it checks the validity of openings in $\mathcal{A}$'s final output. The probability that there are two queries $x$ and $x'$ of $\mathcal{A}$ with $x \neq x'$ but $\mathsf{H}(x) = \mathsf{H}(x')$ is at most $Q_{\mathsf{H}}^2/2^\lambda$. Assuming this event does not occur, $\mathcal{A}$ can not break position-binding, and the claim follows.

Lemma 20. Let H: {0,1}^ * → {0,1}^λ, H₁: {0,1}^ * → ℝ^P×k, and H₂: {0,1}^ * → (ₙ)⁽ₙ⁾ be a random oracle. Then, the scheme CC is code-binding. Concretely, for any Δ₁, Δ₂ ∈ [n] with Δ₁ + Δ₂ < d* and Δ₁ ≤ d*/4, and every algorithm A that makes at most Qₕ, Qₕ₁, Qₕ₂ queries to random oracles H, H₁, H₂, respectively, we have

 $$ \begin{align*}\mathrm{Adv}_{\mathcal{A},\mathrm{CC}}^{\mathrm{code-bind}}(\lambda)\leq&\quad\frac{\bar{Q}_{\mathrm{H}}\bar{Q}_{\mathrm{H}_{1}}n+\bar{Q}_{\mathrm{H}}^{2}}{2^{\lambda}}\\&+\bar{Q}_{\mathrm{H}_{1}}\bar{Q}_{\mathrm{H}_{2}}\cdot\left(\left(\frac{\Delta_{1}+1}{|\mathbb{F}|}\right)^{P}+\left(1-\frac{\Delta_{1}+1}{n}\right)^{L}+\left(1-\frac{\Delta_{2}}{n}\right)^{L}+\frac{1}{|\mathbb{F}|^{P}}\right),\end{align*} $$

where  $ \bar{Q}_{\mathrm{H}} := Q_{\mathrm{H}} + n $,  $ \bar{Q}_{\mathrm{H}_1} := Q_{\mathrm{H}_1} + Q_{\mathrm{H}_2} + 1 $,  $ \bar{Q}_{\mathrm{H}_2} := Q_{\mathrm{H}_2} + 1 $.

Code-binding is proven via a sequence of lemmas. The goal is to show Lemma 20, which states that CC satisfies code-binding. To do that, we first abstract the interactions of the adversary with the random oracles away. In the resulting game, the adversary essentially runs an interactive five round protocol with the challenger. Namely, it sends a matrix  $ \mathbf{X} $ and receives a random challenge matrix  $ \mathbf{R} $. Then, it sends a matrix  $ \mathbf{W} $ and receives a challenge  $ J \subseteq [n] $. Finally, it submits a set  $ J' \subseteq [n] $. The adversary wins the game if these matrices suffice to break code-binding, namely, if (1) there is no  $ \mathbf{X}' $ in the interleaved code  $ \mathcal{C} \equiv k $ that is consistent with  $ \mathbf{X} $ on all columns in  $ J' $, and (2) each row of  $ \mathbf{W} $ is in the code  $ \mathcal{C} $, and (3) for all  $ j \in J \cup J' $, we have  $ \mathbf{W}_j = \mathbf{R}\mathbf{X}_j $. The central lemma of our analysis (Lemma 35) shows that the adversary can not win this game. We split the proof of it into three main steps (Lemmata 32 to 34):

1. Lemma 32: X has to be close to the interleaved code for a winning adversary. Concretely, it has to be within the unique decoding distance, i.e., there is a unique  $ X^* $ in the code that is close to X.

2. Lemma 33: RX and W have to be sufficiently close, due to the randomness of challenge set J.

3. Lemma 34: Using the previous two statements, we get that the distance of  $ \mathbf{RX}^* $ and  $ \mathbf{W} $ is at most  $ d^* $. As both are in the code, we get that  $ \mathbf{RX}^* = \mathbf{W} $. Therefore, there is a column in which  $ \mathbf{X}^* $ and  $ \mathbf{X} $ differ, but  $ \mathbf{RX}^* $ and  $ \mathbf{RX} $ agree on that column. The probability of this can then be bounded, which allows us to prove the central lemma.

We give the formal analysis in Appendix I.1.

Instantiation and Discussion. The main drawback of the construction presented in this section is the following. When we use it to construct a data availability sampling scheme, a single symbol of the encoding is rather large. Concretely, it has size  $ \sqrt{|data| / \log |F|} \cdot \log |F| $ bits, where  $ |data| $ denotes the size of the encoded data in bits. Another drawback is that the scheme does not have message-bound openings, as defined in Definition 22. We can easily see this by considering an adversary that outputs (1) an honest commitment to some message and enough openings including the first symbol, and (2) an almost honest commitment to the same message, where  $ h_1 $ is malformed, and enough openings not including the first symbol. On the other hand, the main advantage of the construction in this section is that it only relies on the security of hash functions and does not require expensive operations such as multiplications over cyclic groups or pairings. Especially, no trusted setup is needed, and we can instantiate the construction over a small field  $ \mathbb{F} $, e.g., the field with  $ 2^{32} $ elements, leading to computational efficiency.

### 9.2 Construction from Homomorphic Hash Functions

In this section, we present a variant of our construction in Section 9.1. This variant makes use of homomorphic hash functions (see Definition 19). Compared to the construction in Section 9.1, this can reduce the size of the commitment for certain instantiations.

Supported Erasure Code. Let  $ \mathcal{C}:\mathbb{F}^k\to\mathbb{F}^n $ be a linear erasure code and let  $ \mathbf{G}\in\mathbb{F}^{n\times k} $ be its generator matrix. We construct an erasure code commitment scheme for the interleaved code  $ \mathcal{C}^{\equiv k}:\mathbb{F}^{k^2}\to\left(\mathbb{F}^k\right)^n $.

Commitment Construction. We make use of random oracles  $ H_1: \{0,1\}^*\to\mathbb{F}^{P\times k} $ and  $ H_2: \{0,1\}^*\to\mathbb{F}^{n\times L} $, where  $ P,L\in\mathbb{N} $ are parameters. In addition, we rely on a homomorphic hash function family  $ HF = (\text{Gen}, \text{Eval}) $ with domain  $ \mathcal{D}=\mathbb{F}^k $ (see Definition 19). Denote the key space and range of HF by  $ \mathcal{K}, \mathcal{R} $, respectively. Our erasure code commitment scheme  $ \text{CC}[\text{HF}] = (\text{Setup}, \text{Com}, \text{Open}, \text{Ver}) $ for  $ \mathcal{C}^{\equiv k} $ is as follows.

• Setup( $ 1^\lambda $)  $ \rightarrow $ ck: Return ck := hk  $ \leftarrow $ HF.Gen( $ 1^\lambda $).

• Com(ck, m) → (com, St):

1. Write  $ \mathbf{m} $ as a matrix  $ \mathbf{M} \in \mathbb{F}^{k \times k} $, and compute  $ \mathbf{X} := \mathbf{M}\mathbf{G}^\top \in \mathbb{F}^{k \times n} $. Let  $ \mathbf{X}_j \in \mathbb{F}^k $ for  $ j \in [n] $ be the  $ j $th column of  $ \mathbf{X} $.

2. For each  $ j \in [n] $, compute  $ h_j := \text{HF.Eval}(\text{hk}, \mathbf{X}_j) $.

3. Compute  $ \mathbf{R} := \mathbf{H}_1(h_1, \ldots, h_n) $. We have  $ \mathbf{R} \in \mathbb{F}^{P \times k} $.

4. Compute  $ \mathbf{W} := \mathbf{R}\mathbf{X} \in \mathbb{F}^{P \times n} $.

5. Compute  $ \mathbf{S} := \mathbf{H}_2(h_1, \ldots, h_n, \mathbf{W}) $. We have  $ \mathbf{S} \in \mathbb{F}^{n \times L} $.

6. Compute  $ \mathbf{Y} := \mathbf{X}\mathbf{S} \in \mathbb{F}^{k \times L} $.

7. Set  $ \complement = \big((h_j)_{j \in [n]}, \mathbf{W}, \mathbf{Y}\big) $ and  $ St := \bot $.

 $$ Open(ck,St,j)\rightarrow\tau:Return\tau:=\perp. $$

• Ver(ck, com,  $ j^* $,  $ \hat{m}_j^* = \mathbf{X}_{j^*}, \tau = \perp $)  $ \rightarrow $ b:

1. If  $ \text{VerCol}(\text{ck}, \text{com}, j^*, \mathbf{X}_{j^*}) = 0 $, return 0, where subroutine  $ \text{VerCol}(\text{ck}, \text{com}, j^*, \mathbf{X}_{j^*}) $ is as follows:

(a) Let  $ \text{com} = \left((h_i)_{i \in [n]}, \mathbf{W}, \mathbf{Y}\right) $.

(b) If  $ h_j^* \neq \text{HF.Eval}(\text{hk}, \mathbf{X}_j^*) $ or  $ \mathbf{X}_j^* \notin \mathbb{F}^k $, return 0.

(c) Compute  $ \mathbf{R} := \mathbf{H}_1(h_1, \ldots, h_n) $.

(d) Let  $ W_j^* $ be the  $ j^* $th column of W. If  $ W_j^* \neq \mathbf{R}X_j^* $, return 0. Otherwise, return 1.

2. If VerCom(ck, com) = 0, return 0, where subroutine VerCom(ck, com) is as follows:

(a) Let  $ \complement = ((h_j)_{j \in [n]}, \mathbf{W}, \mathbf{Y}) $.

(b) If there is a row  $ \mathbf{w}^\top \in \mathbb{F}^{1 \times n} $ of  $ \mathbf{W} $ such that  $ \mathbf{w} \notin \mathcal{C} $, then return 0.

(c) Compute  $ \mathbf{R} := \mathbf{H}_1(h_1, \ldots, h_n) $.

(d) Set  $ \mathbf{S} := \mathsf{H}_2(h_1, \ldots, h_n, \mathbf{W}) $. Let  $ \mathbf{S}_j \in \mathbb{F}^k $ and  $ \mathbf{Y}_j \in \mathbb{F}^k $ for  $ j \in [L] $ be the  $ j $th column of  $ \mathbf{S} $ and  $ \mathbf{Y} $, respectively.

(e) Return 1, if for each  $ j \in [L] $, we have  $ \text{HF.Eval}(hk, \mathbf{Y}_j) = [h_1, \ldots h_n] \mathbf{S}_j $ and  $ \mathbf{RY} = \mathbf{WS} $. Otherwise, return 0.

3. Return 1.

Completeness easily follows from the homomorphism property of HF.

Security. We show position-binding and code-binding. Position-binding follows directly from the collision-resistance of HF.

Lemma 21. Given that HF is a homomorphic family of hash functions, we have that CC[HF] is position-binding. Concretely, for every PPT algorithm A, there is a PPT algorithm B with  $ \mathbf{T}(\mathcal{B}) \approx \mathbf{T}(\mathcal{A}) $, such that

 $$ \mathrm{A d v}_{\mathcal{A},\mathrm{C C}[\mathrm{H F}]}^{\mathrm{p o s-b i n d}}(\lambda)\leq\mathrm{A d v}_{\mathcal{B},\mathrm{H F}}^{\mathrm{c o l l}}(\lambda). $$

Proof. If we have an adversary that breaks position-binding of CC[HF], then it must provide two distinct preimages of one of the hash values contained in the commitment. More formally, let $\mathcal{A}$ be a PPT algorithm in the position-binding game of CC[HF]. We construct a reduction $\mathcal{B}$ against collision-resistance of HF as follows. Reduction $\mathcal{B}$ gets input $\hbar\hbar$ from the collision-resistance experiment. It defines $\mathbf{ck} := \hbar\hbar$, and runs $\mathcal{A}$ on input $\mathbf{ck}$. When $\mathcal{A}$ terminates, it outputs $\mathbf{com}, j^*$, $\mathbf{X}_{j^*}, \tau$, $\mathbf{X}_{j^*}, \tau'$. The reduction outputs $\mathbf{X}_{j^*}$ and $\mathbf{X}'_*\$ to the collision-resistance game. It is clear that $\mathcal{B}$ perfectly simulates the position-binding game for $\mathcal{A}$, and its running time is dominated by the running time of $\mathcal{A}$. Further, assume $\mathcal{A}$ breaks position-binding, i.e. $\mathbf{X}_{j^*} \neq \mathbf{X}'_*\$, $\mathbf{Ver}(\mathbf{ck}, \mathbf{com}, j^*$, $\mathbf{X}_{j^*}, \tau) = 1$, and $\mathbf{Ver}(\mathbf{ck}, \mathbf{com}, j^*$, $\mathbf{X}'_*, \tau') = 1$. Write $\mathbf{com} = ((h_j)_{j \in [n]}$, $\mathbf{W}$, $\mathbf{Y})$. By definition of $\mathbf{Ver}$, in particular the definition of subroutine $\mathbf{VerCol}$, we know that this implies

 $$ \mathsf{H F.E v a l}(\mathsf{h k},\mathbf{X}_{j^{*}})=h_{j^{*}}=\mathsf{H F.E v a l}(\mathsf{h k},\mathbf{X}_{j^{*}}^{\prime}). $$

As  $ \mathbf{X}_j^* \neq \mathbf{X}_j^* $,  $ \mathcal{B} $ breaks collision-resistance.

Lemma 22. Let HF be a homomorphic family of hash functions. Let  $ H_1\colon\{0,1\}^\ast\to\mathbb{F}^{P\times k} $, and  $ H_2\colon\{0,1\}^\ast\to\mathbb{F}^{n\times L} $ be a random oracle. Then, the scheme CC[HF] is code-binding. Concretely, for any PPT algorithm  $ \mathcal{A} $ that makes at most  $ Q_{H_1} $,  $ Q_{H_2} $ queries to random oracles  $ H_1 $,  $ H_2 $, respectively, there is an EPT algorithm  $ \mathcal{B} $ with expected running time  $ \mathbf{ET}(\mathcal{B})\approx(1+n)\mathbf{T}(\mathcal{A}) $ and

 $$ \mathsf{A d v}_{\mathcal{A},\mathsf{C C}[\mathsf{H F}]}^{\mathsf{c o d e-b i n d}}(\lambda)\leq\bar{Q}_{\mathsf{H}_{1}}\bar{Q}_{\mathsf{H}_{2}}\cdot\left(\frac{n}{|\mathbb{F}|^{L}}+\frac{1}{|\mathbb{F}|^{P}}+\frac{1}{|\mathbb{F}|^{L}}+\mathsf{A d v}_{\mathcal{B},\mathsf{H F}}^{\mathsf{c o l l}}(\lambda)\right), $$

where  $ \bar{Q}_{\mathrm{H}_1} := Q_{\mathrm{H}_1} + Q_{\mathrm{H}_2} + 1 $ and  $ \bar{Q}_{\mathrm{H}_2} := Q_{\mathrm{H}_2} + 1 $.

We provide an overview of the proof strategy we use to prove Lemma 22. The formal analysis is given in Appendix I.2. To show code-binding, we first specify a security game without random oracles by abstracting random oracles away. The central lemma of our analysis (Lemma 36) shows that the adversary can not win this game. Then, we show code-binding using this central lemma, similar to what we have done for our construction based on (non-homomorphic) hash functions. In the game of our central lemma, the adversary first obtains a hash key hk and then specifies hash values  $ h_1, \ldots, h_n $. Then, a matrix  $ \mathbf{R} $ is sampled at random from  $ \mathbb{F}^{P \times k} $ and given to the adversary. The adversary outputs a matrix  $ \mathbf{W} $, and gets back a random matrix  $ \mathbf{S} \in \mathbb{F}^{n \times L} $. This reflects the interaction between the adversary and the random oracles. Finally, the adversary outputs  $ \mathbf{Y}, J' $,  $ (\mathbf{X}_j)_{j \in J'} $, which reflects that the adversary outputs a commitment and some openings in the code-binding game. The adversary wins if the matrices and openings satisfy all conditions as in the code-binding game. For examples, the openings  $ \mathbf{X}_j $ have to satisfy

HF.Eval(hk, X_j) = h_j. A major challenge we have to deal with when proving our central lemma is that initially we only get hash values h_1, ..., h_n from the adversary, and not their preimages. Later, we get some of the preimages. This is in contrast to our construction based on non-homomorphic hash functions modeled as random oracles, for which we could easily extract the preimages by observing the random oracle. Thus, we need another way of extracting these preimages. Our idea is as follows. We first fix some hash key and adversarial randomness, leading to fixed hash values h_1, ..., h_n. Then, we run the rest of the experiment a number of times, i.e., we rewind the adversary. Recall that one winning condition is that a homomorphic check on the hash values, given by the condition HF.Eval(hk, Y_j) = [h_1, ... h_n]S_j for each j ∈ [L]. From this check, we observe that if we have enough such S with enough linearly independent columns, we find the preimages of h_1, ..., h_n by solving a linear system of equations. Once we have this, we run the game a final time, rule out inconsistent openings by reducing to collision-resistance, and conclude using statistical arguments. Turning this intuition into a formal proof is surprisingly challenging, especially to make the rewinding work without subtle problems. For example, to get expected polynomial running time of our reduction, we have to ensure that the rewinding always (not only in an overwhelming fraction of cases) ends after a finite number of repetitions.

Instantiation and Discussion. The scheme presented in this section comes with many of the drawbacks and advantages of the scheme presented in Section 9.1. Namely, while a single symbol of the encoding is rather large, we avoid a trusted setup when instantiating the homomorphic hash function appropriately. In contrast to the scheme in Section 9.1, we can get a smaller commitment when using a large field. This is because we only require minimal parallel repetition (parameter L) whereas the scheme in Section 9.1 requires a large L even with a large field. The price we pay is the use of a computationally more expensive large field and public key operations. An example instantiation of the homomorphic hash function is the function

 $$ \mathbb{Z}_{p}^{k}\to\mathbb{G},\quad(x_{1},\ldots,x_{k})\mapsto\prod_{i=1}^{k}g_{i}^{x_{i}} $$

over a cyclic group G of prime order p with generators  $ g_i $. The function is collision-resistant if the DLOG assumption holds in G. We leave investigating a lattice-based instantiation of the homomorphic hash function as future work.

## 10 Evaluation and Comparison

In this section, we give an overview of how the different constructions compare in terms of efficiency. As many of these constructions are written in a generic way, we can not cover all possible instantiations and parameter settings. Instead, we pick reasonable instantiations, suitable for comparison across schemes.

### 10.1 Setting the Stage

Before we discuss the results of our comparison, we first explain which constructions of data availability sampling we consider, which aspects we analyze, and how our results are derived.

Schemes. We consider data availability sampling schemes that follow our construction in Section 6. That is, they are constructed using an erasure code C, an erasure code commitment CC for C, and an index sampler. We use the index sampler Sample_{wr} from Section 6.2, i.e. sampling with replacement, and assume that each client makes Q = 1 query, which has no effect for this particular sampler.

Concrete Erasure Code Commitments. All our concrete instantiations of erasure code commitments target 128-bits of computational security, and we include two “trivial” schemes as a baseline. The following schemes are compared: 1. Naive, the naive scheme, where the encoding has a single symbol, containing all the data, and the commitment is a SHA-256 hash of the data. 2. Merkle, a trivial scheme based on Merkle Trees [Mer88] and the identity code. 3. RS, a scheme where we encode the data using a Reed-Solomon code and commit to it using the KZG [KZG10] polynomial commitment scheme. 4. Tensor, an instantiation of the tensor code construction (Section 8) using KZG as a base scheme. 5. Hash, the scheme for interleaved codes from random oracles (Section 9.1), instantiated with SHA-256 and Reed-Solomon codes over a 32-bit field. 6. HomHash, the scheme for interleaved codes from homomorphic hashing (Section 9.2), instantiated with Pedersen commitments over the Secp256k1 curve, SHA-256, and Reed-Solomon codes over the scalar field of Secp256k1. An overview is provided in Table 1.

Qualitative Criteria. To evaluate the schemes mentioned above, we consider both qualitative aspects and efficiency aspects. In terms of qualitative aspects we are interested in the cryptographic assumptions, the idealized models that the schemes rely on and whether the schemes require a trusted setup.

Efficiency Criteria. We compare the schemes by fixing the data size. Then, we compute the encoding and commitment size and the communication complexity per query of a client. We are also interested in estimating the threshold of the schemes, i.e., the number of queries need to be made by clients, such that the probability of reconstructing is overwhelming. In our comparison, we want it to be at least  $ 1 - 2^{-40} $ (40-bits of statistical security). We determine the threshold using the bounds in Lemma 3 and Examples 5 and 6. Once we determined the threshold, we can then also compute the overall communication complexity required to reconstruct the data. Finally, we will briefly discuss the asymptotic computational efficiency of the schemes. We leave implementing the schemes and comparing concrete running times for future work.



<table border=1 style='margin: auto; word-wrap: break-word;'><tr><td style='text-align: center; word-wrap: break-word;'>Name</td><td style='text-align: center; word-wrap: break-word;'>Code  $ \mathcal{C} $</td><td style='text-align: center; word-wrap: break-word;'>Commitment CC</td><td style='text-align: center; word-wrap: break-word;'>Parameters/Comments</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>Naive</td><td style='text-align: center; word-wrap: break-word;'>-</td><td style='text-align: center; word-wrap: break-word;'>Hash</td><td style='text-align: center; word-wrap: break-word;'>All data in one encoding symbol</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>Merkle</td><td style='text-align: center; word-wrap: break-word;'>Identity</td><td style='text-align: center; word-wrap: break-word;'>Merkle Tree</td><td style='text-align: center; word-wrap: break-word;'>Size of Leaf:  $ 2^{10} $ bit</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>RS</td><td style='text-align: center; word-wrap: break-word;'>$ \mathcal{RS}[k, n, \mathbb{F}] $</td><td style='text-align: center; word-wrap: break-word;'>KZG [KZG10]</td><td style='text-align: center; word-wrap: break-word;'>$ n = 4k $,  $ \mathbb{F} = \mathbb{Z}_p $</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>Tensor</td><td style='text-align: center; word-wrap: break-word;'>$ \mathcal{RS}[k, n, \mathbb{F}]^{\otimes} $</td><td style='text-align: center; word-wrap: break-word;'>Section 8</td><td style='text-align: center; word-wrap: break-word;'>$ n = 2k $,  $ \mathbb{F} = \mathbb{Z}_p $</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>Hash</td><td style='text-align: center; word-wrap: break-word;'>$ \mathcal{RS}[k, n, \mathbb{F}]^{\equiv k} $</td><td style='text-align: center; word-wrap: break-word;'>Section 9.1</td><td style='text-align: center; word-wrap: break-word;'>$ n = 4k $,  $ |\mathbb{F}| = 2^{32} $,  $ P = 8 $,  $ L = 64 $</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>HomHash</td><td style='text-align: center; word-wrap: break-word;'>$ \mathcal{RS}[k, n, \mathbb{F}]^{\equiv k} $</td><td style='text-align: center; word-wrap: break-word;'>Section 9.2</td><td style='text-align: center; word-wrap: break-word;'>Pedersen Hash,  $ n = 4k $,  $ \mathbb{F} = \mathbb{Z}_p $,  $ P = L = 2 $</td></tr></table>

<div style="text-align: center;"><div style="text-align: center;">Table 1: Overview of the different instantiations of erasure code commitments that we compare in Section 10. For each scheme, parameter  $ k $ is picked such that the input domain fits the data length. The notation  $ \mathcal{RS}[k, n, \mathbb{F}]^{\otimes} $ is a short notation for  $ \mathcal{RS}[k, n, \mathbb{F}] \otimes \mathcal{RS}[k, n, \mathbb{F}] $.</div> </div>




<table border=1 style='margin: auto; word-wrap: break-word;'><tr><td style='text-align: center; word-wrap: break-word;'>Scheme</td><td style='text-align: center; word-wrap: break-word;'>Assumption</td><td style='text-align: center; word-wrap: break-word;'>Idealized Model</td><td style='text-align: center; word-wrap: break-word;'>Trusted Setup</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>Naive</td><td style='text-align: center; word-wrap: break-word;'>Hash</td><td style='text-align: center; word-wrap: break-word;'>-</td><td style='text-align: center; word-wrap: break-word;'>✗</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>Merkle</td><td style='text-align: center; word-wrap: break-word;'>Hash</td><td style='text-align: center; word-wrap: break-word;'>-</td><td style='text-align: center; word-wrap: break-word;'>✗</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>RS</td><td style='text-align: center; word-wrap: break-word;'>q-Type</td><td style='text-align: center; word-wrap: break-word;'>AGM</td><td style='text-align: center; word-wrap: break-word;'>✓</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>Tensor</td><td style='text-align: center; word-wrap: break-word;'>q-Type</td><td style='text-align: center; word-wrap: break-word;'>AGM</td><td style='text-align: center; word-wrap: break-word;'>✓</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>Hash</td><td style='text-align: center; word-wrap: break-word;'>-</td><td style='text-align: center; word-wrap: break-word;'>ROM</td><td style='text-align: center; word-wrap: break-word;'>✗</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>HomHash</td><td style='text-align: center; word-wrap: break-word;'>DLOG</td><td style='text-align: center; word-wrap: break-word;'>ROM</td><td style='text-align: center; word-wrap: break-word;'>✗</td></tr></table>

<div style="text-align: center;"><div style="text-align: center;">Table 2: Qualitative comparison of different data availability sampling schemes. The details of the schemes are given in Table 1. We compare the cryptographic assumptions and idealized models that these schemes use, and whether they rely on a trusted setup or not.</div> </div>


### 10.2 Results

We implemented our methodology in Python scripts given in Appendix K. Our results are presented in Tables 2 and 3 and Figure 3. We now discuss the results.

Assumptions, Models, and Setup. In terms of qualitative criteria, the schemes Hash, Naive, Merkle are the most desirable ones, as they do not rely on a trusted setup and only rely on hash functions. Scheme HomHash is also a good choice as it avoids trusted setup. Depending on the instantiation of the homomorphic hash function, it only relies on mild cryptographic assumptions, e.g., DLOG. Schemes RS and Tensor require trusted setup and stronger assumptions.

Encoding Size. In terms of encoding size, schemes RS and Tensor have a slightly larger encoding than Hash and HomHash, which comes from the KZG [KZG10] openings that have to be stored in addition to the codeword. It is natural that Hash and HomHash have (almost) the same encoding size, as they encode data using the same code with no explicit opening, the field size does not affect the size of the encoding significantly – the minimal discrepancy comes from rounding.

Commitment Size. In terms of commitment size, schemes Naive, Merkle, RS, and Tensor perform best. The commitment for Naive, Merkle is a single hash value. For RS, the commitment is a single group

element over a group of size $p$, namely, a single KZG [KZG10] commitment. Especially, the commitment size for these three schemes Naive, Merkle, and RS is constant, i.e., independent of the size of the data. For Tensor, $\Theta(\sqrt{|data|}/\log p)$ such KZG commitments are needed. The schemes Hash and HomHash perform worse in terms of commitment size. Especially, Hash has a larger commitment. This is because due to the small field size, we require large repetition factor $L$ which shows up in the commitment size. Concretely, the commitment contains $L$ random columns of the codeword, which are of size $k = \sqrt{|data|}/32$ field elements. On the other hand, for HomHash, we had to choose a large field to implement the homomorphic hash function, leading to small repetition factors and thus a smaller commitment size than for Hash.

Communication per Query. In terms of communication complexity per query, scheme Naive disqualifies, as expected. Optimal with respect to this measure are RS and Tensor, for which the communication complexity per query is constant, i.e., independent of the data size. This is because both return a single KZG [KZG10] opening and a single field element. Schemes Hash and HomHash perform worse in terms of communication complexity per query, which is due to the use of the interleaved code, which has symbols of size  $ f \cdot \sqrt{|data|}/f $, where  $ f $ is the number of bits needed to represent one field element. If we compare these two schemes, we see the inverse of what we saw for the commitment size. Namely, Hash performs better. This can be explained by the different field sizes. Namely,  $ f $ does not cancel out in the symbol size  $ f \cdot \sqrt{|data|}/f = \sqrt{|data|} \cdot \sqrt{f} $. The ratio between  $ \sqrt{256} $ and  $ \sqrt{32} $ matches the gap that we see in Table 3 and Figure 3.

Total Communication. Multiplying the communication per query with the number of samples required to reconstruct the data with high probability, we obtain the total communication cost. We see that Merkle disqualifies due to a huge number of samples, which follows Lemma 3 and Examples 5 and 6. Further, we see that RS and Tensor perform worse than Hash and HomHash. This is because Hash and HomHash use an interleaved code, leading to a smaller number of symbols and therefore to a smaller number of required samples. One could expect that the large communication per query of Hash and HomHash outweighs this, but our results show that this is not the case. We can explain this by comparing with scheme Naive, which has only one symbol. Of course, this scheme achieves the optimal total communication of exactly |data|. We can think of Hash and HomHash as being between this naive scheme and schemes like RS and Tensor. Namely, they have a small number of large symbols. We thus expect that the total communication gets worse if we increase the number of symbols and decrease their size.

Computational Efficiency. Clients are computationally lightweight in all schemes. For example, in KZG-based constructions (RS and Tensor), each sample is verified using two pairings. For encoding, the computational complexity for all schemes depends on the encoding complexity for the underlying code. For the interleaved constructions (Hash and HomHash), we can assume that the code has encoding time of  $ \Theta(k \log k) $ using FFT techniques. Then, encoding for the interleaved code takes time  $ \Theta(\sqrt{k} \cdot (\sqrt{k} \log \sqrt{k})) = \Theta(k \log k) $. A similar complexity can be achieved for Tensor if KZG opening proofs are computed efficiently using recent techniques [FK23].

Conclusion. Clearly, the schemes Naive and Merkle are far from being usable in practice due to huge communication costs per query or in total, respectively. They should only be understood as a baseline. If we are interested in using schemes that do not rely on trusted setup and use minimal assumptions, the schemes Hash and HomHash are desirable. If we compare these two, Hash performs better in terms of communication complexity per query, but worse in terms of commitment size. Additionally, Hash avoids computationally expensive public key operations and instead only needs hash operations and arithmetic over small fields. On the other hand, if the communication effort per client is our primary goal, schemes RS and Tensor are the best choice, as the commitment size is minimal and the communication per query is constant.



<table border=1 style='margin: auto; word-wrap: break-word;'><tr><td style='text-align: center; word-wrap: break-word;'></td><td style='text-align: center; word-wrap: break-word;'>Scheme</td><td style='text-align: center; word-wrap: break-word;'>$ \left|com\right| $ [KB]</td><td style='text-align: center; word-wrap: break-word;'>$ \left|\pi\right| $ [MB]</td><td style='text-align: center; word-wrap: break-word;'>Query [KB]</td><td style='text-align: center; word-wrap: break-word;'>Samples</td><td style='text-align: center; word-wrap: break-word;'>Total [MB]</td></tr><tr><td rowspan="6">$ \left|data\right|=1 $ MB</td><td style='text-align: center; word-wrap: break-word;'>Naive</td><td style='text-align: center; word-wrap: break-word;'>0.03</td><td style='text-align: center; word-wrap: break-word;'>1.00</td><td style='text-align: center; word-wrap: break-word;'>1000.00</td><td style='text-align: center; word-wrap: break-word;'>1</td><td style='text-align: center; word-wrap: break-word;'>1.00</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>Merkle</td><td style='text-align: center; word-wrap: break-word;'>0.03</td><td style='text-align: center; word-wrap: break-word;'>4.25</td><td style='text-align: center; word-wrap: break-word;'>0.55</td><td style='text-align: center; word-wrap: break-word;'>286655</td><td style='text-align: center; word-wrap: break-word;'>156.40</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>RS</td><td style='text-align: center; word-wrap: break-word;'>0.05</td><td style='text-align: center; word-wrap: break-word;'>8.00</td><td style='text-align: center; word-wrap: break-word;'>0.10</td><td style='text-align: center; word-wrap: break-word;'>35881</td><td style='text-align: center; word-wrap: break-word;'>3.52</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>Tensor</td><td style='text-align: center; word-wrap: break-word;'>6.96</td><td style='text-align: center; word-wrap: break-word;'>8.07</td><td style='text-align: center; word-wrap: break-word;'>0.10</td><td style='text-align: center; word-wrap: break-word;'>160115</td><td style='text-align: center; word-wrap: break-word;'>15.70</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>Hash</td><td style='text-align: center; word-wrap: break-word;'>256.00</td><td style='text-align: center; word-wrap: break-word;'>4.00</td><td style='text-align: center; word-wrap: break-word;'>2.00</td><td style='text-align: center; word-wrap: break-word;'>879</td><td style='text-align: center; word-wrap: break-word;'>1.76</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>HomHash</td><td style='text-align: center; word-wrap: break-word;'>80.00</td><td style='text-align: center; word-wrap: break-word;'>4.01</td><td style='text-align: center; word-wrap: break-word;'>5.67</td><td style='text-align: center; word-wrap: break-word;'>323</td><td style='text-align: center; word-wrap: break-word;'>1.83</td></tr><tr><td rowspan="6">$ \left|data\right|=32 $ MB</td><td style='text-align: center; word-wrap: break-word;'>Naive</td><td style='text-align: center; word-wrap: break-word;'>0.03</td><td style='text-align: center; word-wrap: break-word;'>32.00</td><td style='text-align: center; word-wrap: break-word;'>32000.00</td><td style='text-align: center; word-wrap: break-word;'>1</td><td style='text-align: center; word-wrap: break-word;'>32.00</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>Merkle</td><td style='text-align: center; word-wrap: break-word;'>0.03</td><td style='text-align: center; word-wrap: break-word;'>176.00</td><td style='text-align: center; word-wrap: break-word;'>0.71</td><td style='text-align: center; word-wrap: break-word;'>10038776</td><td style='text-align: center; word-wrap: break-word;'>7089.80</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>RS</td><td style='text-align: center; word-wrap: break-word;'>0.05</td><td style='text-align: center; word-wrap: break-word;'>256.00</td><td style='text-align: center; word-wrap: break-word;'>0.10</td><td style='text-align: center; word-wrap: break-word;'>1147584</td><td style='text-align: center; word-wrap: break-word;'>113.23</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>Tensor</td><td style='text-align: center; word-wrap: break-word;'>39.22</td><td style='text-align: center; word-wrap: break-word;'>256.32</td><td style='text-align: center; word-wrap: break-word;'>0.10</td><td style='text-align: center; word-wrap: break-word;'>4626776</td><td style='text-align: center; word-wrap: break-word;'>456.52</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>Hash</td><td style='text-align: center; word-wrap: break-word;'>1448.45</td><td style='text-align: center; word-wrap: break-word;'>128.05</td><td style='text-align: center; word-wrap: break-word;'>11.32</td><td style='text-align: center; word-wrap: break-word;'>4888</td><td style='text-align: center; word-wrap: break-word;'>55.32</td></tr><tr><td style='text-align: center; word-wrap: break-word;'>HomHash</td><td style='text-align: center; word-wrap: break-word;'>452.00</td><td style='text-align: center; word-wrap: break-word;'>128.00</td><td style='text-align: center; word-wrap: break-word;'>32.00</td><td style='text-align: center; word-wrap: break-word;'>1740</td><td style='text-align: center; word-wrap: break-word;'>55.68</td></tr></table>

<div style="text-align: center;"><div style="text-align: center;">Table 3: Efficiency comparison of different data availability sampling schemes. Details of the schemes are given in Table 1. For given size of data, we compare the size of commitments  $ \text{com} $, encodings  $ \pi $, and communication complexity per query. Column “Samples” shows the total number of samples that clients need to query such that data can be reconstructed with probability at least  $ 1 - 2^{-40} $, and the final column denotes the total communication cost for this process.</div> </div>


<div style="text-align: center;"><img src="images/HAS23 - Fig 3 - Index sampler quality.jpg" alt="Image" width="67%" /></div>


<div style="text-align: center;"><div style="text-align: center;">Figure 3: Efficiency of data availability sampling schemes. The details of the schemes are given in Table 1. We compare the size of commitments, the size of the encoding, the communication complexity per query, and the total communication complexity when increasing the data size. Schemes Naive and Merkle are omitted.</div> </div>


## References

[ABC+07] Giuseppe Ateniese, Randal C. Burns, Reza Curtmola, Joseph Herring, Lea Kissner, Zachary N. J. Peterson, and Dawn Song. Provable data possession at untrusted stores. In Peng Ning, Sabrina De Capitani di Vimercati, and Paul F. Syverson, editors, ACM CCS 2007, pages 598–609. ACM Press, October 2007. (Cited on page 5.)

[ADVZ21] Nicolas Alhaddad, Sisi Duan, Mayank Varia, and Haibin Zhang. Succinct erasure coding proof systems. Cryptology ePrint Archive, Report 2021/1500, 2021. https://eprint.iacr.org/2021/1500. (Cited on page 5.)

[AHIV17] Scott Ames, Carmit Hazay, Yuval Ishai, and Muthuramakrishnan Venkitasubramaniam. Ligero: Lightweight sublinear arguments without a trusted setup. In Bhavani M. Thuraisingham, David Evans, Tal Malkin, and Dongyan Xu, editors, ACM CCS 2017, pages 2087–2104. ACM Press, October / November 2017. (Cited on page 12, 27.)

[AHIV22] Scott Ames, Carmit Hazay, Yuval Ishai, and Muthuramakrishnan Venkitasubramaniam. Ligero: Lightweight sublinear arguments without a trusted setup. Cryptology ePrint Archive, Paper 2022/1608, 2022. https://eprint.iacr.org/2022/1608. (Cited on page 27, 55.)

[ASBK21] Mustafa Al-Bassam, Alberto Sonnino, Vitalik Buterin, and Ismail Khoffi. Fraud and data availability proofs: Detecting invalid blocks in light clients. In Nikita Borisov and Claudia Díaz, editors, Financial Cryptography and Data Security - 25th International Conference, FC 2021, Virtual Event, March 1-5, 2021, Revised Selected Papers, Part II, volume 12675 of Lecture Notes in Computer Science, pages 279–298. Springer, 2021. (Cited on page 3.)

[BBHR18] Eli Ben-Sasson, Iddo Bentov, Yinon Horesh, and Michael Riabzev. Fast reed-solomon interactive oracle proofs of proximity. In Ioannis Chatzigiannakis, Christos Kaklamanis, Dániel Marx, and Donald Sannella, editors, ICALP 2018, volume 107 of LIPIcs, pages 14:1–14:17. Schloss Dagstuhl, July 2018. (Cited on page 6.)

[BCG+17] Eli Ben-Sasson, Alessandro Chiesa, Ariel Gabizon, Michael Riabzev, and Nicholas Spooner. Interactive oracle proofs with constant rate and query complexity. In Ioannis Chatzigiannakis, Piotr Indyk, Fabian Kuhn, and Anca Muscholl, editors, ICALP 2017, volume 80 of LIPics, pages 40:1–40:15. Schloss Dagstuhl, July 2017. (Cited on page 5, 6.)

[BDFG20] Dan Boneh, Justin Drake, Ben Fisch, and Ariel Gabizon. Efficient polynomial commitment schemes for multiple points and polynomials. Cryptology ePrint Archive, Report 2020/081, 2020. https://eprint.iacr.org/2020/081. (Cited on page 5.)

[BFM88] Manuel Blum, Paul Feldman, and Silvio Micali. Non-interactive zero-knowledge and its applications (extended abstract). In 20th ACM STOC, pages 103–112. ACM Press, May 1988. (Cited on page 8.)

[BGH $ ^{+} $06] Eli Ben-Sasson, Oded Goldreich, Prahladh Harsha, Madhu Sudan, and Salil Vadhan. Robust pbps of proximity, shorter pbps, and applications to coding. SIAM Journal on Computing, 36(4):889–974, 2006. (Cited on page 5.)

[BGKS20] Eli Ben-Sasson, Lior Goldberg, Swastik Kopparty, and Shubhangi Saraf. DEEP-FRI: Sampling outside the box improves soundness. In Thomas Vidick, editor, ITCS 2020, volume 151, pages 5:1–5:32. LIPIcs, January 2020. (Cited on page 5.)

[CDD $ ^{+} $16] Ignacio Cascudo, Ivan Damgård, Bernardo David, Nico Döttling, and Jesper Buus Nielsen. Rate-1, linear time and additively homomorphic UC commitments. In Matthew Robshaw and Jonathan Katz, editors, CRYPTO 2016, Part III, volume 9816 of LNCS, pages 179–207. Springer, Heidelberg, August 2016. (Cited on page 14.)

[CF13] Dario Catalano and Dario Fiore. Vector commitments and their applications. In Kaoru Kurosawa and Goichiro Hanaoka, editors, PKC 2013, volume 7778 of LNCS, pages 55–72. Springer, Heidelberg, February / March 2013. (Cited on page 17.)

[CFM08] Dario Catalano, Dario Fiore, and Mariagrazia Messina. Zero-knowledge sets with short proofs. In Nigel P. Smart, editor, EUROCRYPT 2008, volume 4965 of LNCS, pages 433–450. Springer, Heidelberg, April 2008. (Cited on page 5.)

[CGKS22] Matteo Campanelli, Chaya Ganesh, Hamidreza Khoshakhlagh, and Janno Siim. Impossibilities in succinct arguments: Black-box extraction and more. Cryptology ePrint Archive, Report 2022/638, 2022. https://eprint.iacr.org/2022/638. (Cited on page 25.)

[CHL+05] Melissa Chase, Alexander Healy, Anna Lysyanskaya, Tal Malkin, and Leonid Reyzin. Mercurial commitments with applications to zero-knowledge sets. In Ronald Cramer, editor, EUROCRYPT 2005, volume 3494 of LNCS, pages 422–439. Springer, Heidelberg, May 2005. (Cited on page 5.)

[CHM $ ^{+} $20] Alessandro Chiesa, Yuncong Hu, Mary Maller, Pratyush Mishra, Psi Vesely, and Nicholas P. Ward. Marlin: Preprocessing zkSNARKs with universal and updatable SRS. In Anne Canteaut and Yuval Ishai, editors, EUROCRYPT 2020, Part I, volume 12105 of LNCS, pages 738–768. Springer, Heidelberg, May 2020. (Cited on page 5.)

[CKW13] David Cash, Alptekin Küpçü, and Daniel Wichs. Dynamic proofs of retrievability via oblivious RAM. In Thomas Johansson and Phong Q. Nguyen, editors, EUROCRYPT 2013, volume 7881 of LNCS, pages 279–295. Springer, Heidelberg, May 2013. (Cited on page 5.)

[CT05] Christian Cachin and Stefano Tessaro. Asynchronous verifiable information dispersal. In Pierre Fraigniaud, editor, Distributed Computing, 19th International Conference, DISC 2005, Cracow, Poland, September 26-29, 2005, Proceedings, volume 3724 of Lecture Notes in Computer Science, pages 503–504. Springer, 2005. (Cited on page 5.)

[DVW09] Yevgeniy Dodis, Salil P. Vadhan, and Daniel Wichs. Proofs of retrievability via hardness amplification. In Omer Reingold, editor, TCC 2009, volume 5444 of LNCS, pages 109–127. Springer, Heidelberg, March 2009. (Cited on page 5.)

[Fei23] Dankrad Feist. Data availability encoding. https://notes.ethereum.org/ReasmW86SuKqC2FaX83T1g, 2023. Accessed: 2023-05-08. (Cited on page 27.)

[Fe187] Paul Feldman. A practical scheme for non-interactive verifiable secret sharing. In 28th FOCS, pages 427–437. IEEE Computer Society Press, October 1987. (Cited on page 12.)

[FK23] Dankrad Feist and Dmitry Khovratovich. Fast amortized KZG proofs. Cryptology ePrint Archive, Report 2023/033, 2023. https://eprint.iacr.org/2023/033. (Cited on page 33.)

[FKL18] Georg Fuchsbauer, Eike Kiltz, and Julian Loss. The algebraic group model and its applications. In Hovav Shacham and Alexandra Boldyreva, editors, CRYPTO 2018, Part II, volume 10992 of LNCS, pages 33–62. Springer, Heidelberg, August 2018. (Cited on page 17.)

[Gro16] Jens Groth. On the size of pairing-based non-interactive arguments. In Marc Fischlin and Jean-Sébastien Coron, editors, EUROCRYPT 2016, Part II, volume 9666 of LNCS, pages 305–326. Springer, Heidelberg, May 2016. (Cited on page 8.)

[GW11] Craig Gentry and Daniel Wichs. Separating succinct non-interactive arguments from all falsifiable assumptions. In Lance Fortnow and Salil P. Vadhan, editors, 43rd ACM STOC, pages 99–108. ACM Press, June 2011. (Cited on page 25.)

[HASW24] Mathias Hall-Andersen, Mark Simkin, and Benedikt Wagner. FRIDA: Data availability sampling from fri. In Leonid Reyzin and Douglas Stebila, editors, CRYPTO 2024 (to appear), LNCS. Springer, Heidelberg, August 18–22, 2024. (Cited on page 5.)

[JK07] Ari Juels and Burton S. Kaliski Jr. Pors: proofs of retrievability for large files. In Peng Ning, Sabrina De Capitani di Vimercati, and Paul F. Syverson, editors, ACM CCS 2007, pages 584–597. ACM Press, October 2007. (Cited on page 5.)

[Kil92] Joe Kilian. A note on efficient zero-knowledge proofs and arguments (extended abstract). In 24th ACM STOC, pages 723–732. ACM Press, May 1992. (Cited on page 8.)

[KZG10] Aniket Kate, Gregory M. Zaverucha, and Ian Goldberg. Constant-size commitments to polynomials and their applications. In Masayuki Abe, editor, ASIACRYPT 2010, volume 6477 of LNCS, pages 177–194. Springer, Heidelberg, December 2010. (Cited on page 5, 8, 17, 27, 31, 32, 33, 45.)

[LRY16] Benoît Libert, Somindu C. Ramanna, and Moti Yung. Functional commitment schemes: From polynomial commitments to pairing-based accumulators from simple assumptions. In Ioannis Chatzigiannakis, Michael Mitzenmacher, Yuval Rabani, and Davide Sangiorgi, editors, ICALP 2016, volume 55 of LIPIcs, pages 30:1–30:14. Schloss Dagstuhl, July 2016. (Cited on page 5.)

[LY10] Benoit Libert and Moti Yung. Concise mercurial vector commitments and independent zero-knowledge sets with short proofs. In Daniele Micciancio, editor, TCC 2010, volume 5978 of LNCS, pages 499–517. Springer, Heidelberg, February 2010. (Cited on page 5.)

[Mer88] Ralph C. Merkle. A digital signature based on a conventional encryption function. In Carl Pomerance, editor, CRYPTO'87, volume 293 of LNCS, pages 369–378. Springer, Heidelberg, August 1988. (Cited on page 9, 17, 25, 31.)

[NNT21] Kamilla Nazirkhanova, Joachim Neu, and David Tse. Information dispersal with provable retrievability for rollups. Cryptology ePrint Archive, Report 2021/1544, 2021. https://eprint.iacr.org/2021/1544. (Cited on page 3, 5.)

[Ped92] Torben P. Pedersen. Non-interactive and information-theoretic secure verifiable secret sharing. In Joan Feigenbaum, editor, CRYPTO'91, volume 576 of LNCS, pages 129–140. Springer, Heidelberg, August 1992. (Cited on page 8.)

[Rab89] Michael O. Rabin. Efficient dispersal of information for security, load balancing, and fault tolerance. J. ACM, 36(2):335–348, 1989. (Cited on page 5.)

[SSP13] Elaine Shi, Emil Stefanov, and Charalampos Papamanthou. Practical dynamic proofs of retrievability. In Ahmad-Reza Sadeghi, Virgil D. Gligor, and Moti Yung, editors, ACM CCS 2013, pages 325–336. ACM Press, November 2013. (Cited on page 5.)

[SW08] Hovav Shacham and Brent Waters. Compact proofs of retrievability. In Josef Pieprzyk, editor, ASIACRYPT 2008, volume 5350 of LNCS, pages 90–107. Springer, Heidelberg, December 2008. (Cited on page 5.)

[SXKV21] Peiyao Sheng, Bowen Xue, Sreeram Kannan, and Pramod Viswanath. ACeD: Scalable data availability oracle. In Nikita Borisov and Claudia Díaz, editors, FC 2021, Part II, volume 12675 of LNCS, pages 299–318. Springer, Heidelberg, March 2021. (Cited on page 3.)

[YSL+20] Mingchao Yu, Saeid Sahraei, Songze Li, Salman Avestimehr, Sreeram Kannan, and Pramod Viswanath. Coded merkle tree: Solving data availability attacks in blockchains. In Joseph Bonneau and Nadia Heninger, editors, FC 2020, volume 12059 of LNCS, pages 114–134. Springer, Heidelberg, February 2020. (Cited on page 3.)

## Part II Appendix

A Definition of Cryptographic Building Blocks 38

B Some Useful Bounds 40

C Omitted Details from Section 3 40
C.1 Omitted Details from Section 3.1 40
C.2 Extension: Repairability 41
C.3 Extension: Local Accessibility 41

D Omitted Details from Section 5 42

E Additional Notions for Erasure Code Commitments 42
E.1 Message-Bound Openings 42
E.2 Computational Uniqueness 43
E.3 Extractability 44

F Omitted Details from Section 6 45
F.1 Omitted Details from Section 6.1 45
F.2 Omitted Details from Section 6.2 46
F.3 Omitted Details from Section 6.3 47

G Omitted Details from Section 7 48

H Omitted Details from Section 8 49

I Omitted Details from Section 9 54
I.1 Omitted Details from Section 9.1 54
I.2 Omitted Details from Section 9.2 58

J Simulation of Index Samplers 64

K Script for Parameter Computation 66

### A Definition of Cryptographic Building Blocks

Definition 15 (Vector Commitment Scheme). A vector commitment scheme over alphabet  $ \Sigma $ with length  $ \ell $ and opening alphabet  $ \Xi $ is a tuple  $ \mathsf{VC} = (\mathsf{Setup}, \mathsf{Com}, \mathsf{Open}, \mathsf{Ver}) $ of PPT algorithms, with the following syntax:

• Setup( $ 1^{\lambda} $) → ck takes as input the security parameter, and outputs a commitment key ck.

-  $ \text{Com}(ck,m) \to (\text{com}, St) $ takes as input a commitment key  $ ck $ and a string  $ m \in \Sigma^\ell $, and outputs a commitment  $ \text{com} $ and a state  $ St $.

- Open(ck, St, i) → τ takes as input a commitment key ck, a state St, and an index i ∈ [ℓ], and outputs an opening τ ∈ ∃.

- Ver(ck, com, i, m_i,  $ \tau $)  $ \rightarrow $ b is deterministic, takes as input a commitment key ck, a commitment com, and index  $ i \in [\ell] $, a symbol  $ m_i \in \Sigma $, and an opening  $ \tau \in \Xi $, and outputs a bit  $ b \in \{0, 1\} $.

Further, we require that the following completeness property holds: For every  $ \mathbf{ck} \in \text{Setup}(1^\lambda) $, every  $ m \in \Sigma^\ell $, and every  $ i \in [\ell] $, we have

 $$ \begin{array}{l}\operatorname{P r}\left[\operatorname{V e r}(\operatorname{c k},\operatorname{c o m},i,m_{i},\tau)=1\left|\begin{array}{l}(\operatorname{c o m},S t)\leftarrow\operatorname{C o m}(\operatorname{c k},m),\\ \tau\leftarrow\operatorname{O p e n}(\operatorname{c k},S t,i)\end{array}\right.\right]\geq1-\operatorname{n e g l}(\lambda).\end{array} $$

Definition 16 (Position-Binding of VC). Let  $ \mathsf{VC} = (\mathsf{Setup}, \mathsf{Com}, \mathsf{Open}, \mathsf{Ver}) $ be a vector commitment scheme over alphabet  $ \Sigma $ with length  $ \ell $. We say that  $ \mathsf{VC} $ is position-binding, if for every PPT algorithm  $ \mathcal{A} $, the following advantage is negligible:

 $$ \begin{array}{l}Adv_{\mathcal{A},\mathsf{V C}}^{\mathsf{p o s-b i n d}}(\lambda):=\operatorname{P r}\left[\begin{array}{c}m\neq m^{\prime}\\ \wedge\operatorname{V e r}(\mathsf{c k},\operatorname{c o m},i,m,\tau)=1\\ \wedge\operatorname{V e r}(\mathsf{c k},\operatorname{c o m},i,m^{\prime},\tau^{\prime})=1\end{array}\right|\begin{array}{l}\mathsf{c k}\leftarrow\mathsf{S e t u p}(1^{\lambda}),\\ (\mathsf{c o m},i,m,\tau,m^{\prime},\tau^{\prime})\leftarrow\mathcal{A}(\mathsf{c k})\end{array}\right].\end{array} $$

Definition 17 (NP-Relation). Let  $ \mathcal{R} = (\mathcal{R}_\lambda)_\lambda $ be a family of binary relations  $ \mathcal{R}_\lambda \subseteq \{0,1\}^* \times \{0,1\}^* $. We define the language of yes-instances  $ \mathcal{L}_\lambda $ via

 $$ \mathcal{L}_{\lambda}:=\left\{\mathsf{s t m t}\in\{0,1\}^{*}\mid\exists\mathsf{w i t n}\in\{0,1\}^{*}:(\mathsf{s t m t},\mathsf{w i t n})\in\mathcal{R}_{\lambda}\right\}. $$

We say that R is an NP-relation, if the following properties hold:

• There exists a polynomial poly, such that for any  $ \text{stmt} \in \mathcal{L}_\lambda $, we have  $ |\text{stmt}| \leq \text{poly}(\lambda) $.

• Membership in  $ R_{\lambda} $ is efficiently decidable, i.e. there exists a deterministic polynomial time algorithm that decides  $ R_{\lambda} $.

• There is a polynomial poly' such that for all (stmt, witn) ∈ Rλ we have |witn| ≤ poly'(|stmt|).

Definition 18 (Non-Interactive Argument of Knowledge). Let  $ \mathcal{R} $ be an NP-relation. A non-interactive argument of knowledge for  $ \mathcal{R} $ is a tuple  $ \operatorname{PS} = (\operatorname{Setup}, \operatorname{PProve}, \operatorname{PVer}) $ of PPT algorithms with the following syntax:

• Setup(1λ) → crs takes as input the security parameter, and outputs a common reference string crs.

• PProve(crs, stmt, witn) → π takes as input a common reference string crs, a statement stmt, and a witness witn, and outputs a proof π.

- PVer(crs, stmt,  $ \pi $)  $ \rightarrow $ b is deterministic, takes as input a common reference string crs, a statement stmt, a proof  $ \pi $, and outputs a bit  $ b \in \{0, 1\} $.

We require that the following properties hold:

• Completeness. For all  $ crs \in Setup(1^\lambda) $, and all  $ (stmt, witn) \in \mathcal{R}_\lambda $, we have

 $$ \Pr\left[PVer(crs,stmt,\pi)=1\mid\pi\leftarrow PProve(crs,stmt,witn)\right]=1. $$

• Knowledge Soundness. There is a PPT algorithm Ext, such that for any PPT algorithm A, the following advantage is negligible:

 $$ \begin{aligned}&Adv_{\mathcal{A},\mathrm{PS},\mathrm{Ext}}^{\mathrm{kn-sound}}(\lambda):=\operatorname{Pr}\left[(\mathrm{stmt},\mathrm{witn})\notin\mathcal{R}_{\lambda}\land\mathrm{PVer}(\mathrm{crs},\mathrm{stmt},\pi)=1\right.\left|\begin{array}{c}\mathrm{crs}\leftarrow\mathrm{Setup}(1^{\lambda}),\ $ \mathrm{stmt},\pi)\leftarrow\mathcal{A}(\mathrm{crs}),\\\mathrm{witn}\leftarrow\mathrm{Ext}(\mathrm{crs},\mathrm{stmt},\pi).\end{array}\right].\end{aligned} $$

We say that Ext is the knowledge extractor of PS.

Definition 19 (Homomorphic Hash Function). Let  $ \mathcal{K} = \{\mathcal{K}_\lambda\}_{\lambda}, \mathcal{D} = \{\mathcal{D}_\lambda\}_{\lambda}, \mathcal{R} = \{\mathcal{R}_\lambda\}_{\lambda} $ be families of sets, such that for each  $ \lambda $,  $ \mathcal{D}_\lambda $ and  $ \mathcal{R}_\lambda $ are abelian groups. We denote both group operations additively. A homomorphic hash function family with key space  $ \mathcal{K} $, domain  $ \mathcal{D} $, and range  $ \mathcal{R} $ is a pair  $ \mathsf{HF} = (\mathsf{Gen}, \mathsf{Eval}) $ of PPT algorithms, with the following syntax:

• Gen(1λ) → hk takes as input the security parameter, and outputs a hash key hk ∈ Kλ.

•  $ \text{Eval}(hk,x) \to y $ is deterministic, takes as input a hash key  $ hk \in \mathcal{K}_\lambda $, and an element  $ x \in \mathcal{D}_\lambda $, and outputs an element  $ y \in \mathcal{R}_\lambda $.

Further, we require that the following properties holds:

• Homomorphism. For any  $ \mathsf{hk} \in \mathsf{Gen}(1^\lambda) $, and all  $ x, x' \in \mathcal{D}_\lambda $, we have

 $$ \mathsf{Eval}(\mathsf{hk},x+x^{\prime})=\mathsf{Eval}(\mathsf{hk},x)+\mathsf{Eval}(\mathsf{hk},x^{\prime}). $$

• Collision-Resistance. For any EPT algorithm A, the following advantage is negligible:

 $$ \begin{array}{r}{\mathrm{A d v}_{\mathcal{A},\mathrm{H F}}^{\mathrm{c o l l}}(\lambda):=\operatorname*{P r}\left[\begin{array}{c|c}{x\neq x^{\prime}}&{\mathrm{h k}\leftarrow\mathrm{G e n}(1^{\lambda}),}\\ {\wedge\mathrm{E v a l}(\mathrm{h k},x)=\mathrm{E v a l}(\mathrm{h k},x^{\prime})}&{(x,x^{\prime})\leftarrow\mathcal{A}(\mathrm{h k})}\end{array}\right].}\end{array} $$

For simplicity, we omit the subscript  $ \lambda $ and write  $ \mathcal{K}, \mathcal{D}, \mathcal{R} $ instead of  $ \mathcal{K}_{\lambda}, \mathcal{D}_{\lambda}, \mathcal{R}_{\lambda} $, if  $ \lambda $ is clear from the context.

### B Some Useful Bounds

Lemma 23 (Chernoff Bound). Let  $ X_1, \ldots, X_t $ be independent random variables with values in  $ \{0,1\} $. Let  $ \delta \geq 0 $. Then, we have

 $$ \Pr\left[\sum_{i=1}^{t}X_{i}\leq(1-\delta)\mu\right]\leq\exp(-\delta^{2}\mu/2),for\mu:=\mathbb{E}\left[\sum_{i=1}^{t}X_{i}\right]. $$

Lemma 24. Let $N, D, L \in \mathbb{N}$ with $D, L \leq N, L \leq N - \Delta$. Then, we have

 $$ \binom{N-D}{L}\bigg/\binom{N}{L}\leq\left(1-\frac{D}{N}\right)^{L}. $$

Proof. We have

 $$ \begin{align*}\binom{N-D}{L}\bigg/\binom{N}{L}&=\frac{(N-D)!\cdot L!\cdot(N-L)!}{L!\cdot(N-D-L)!\cdot N!}=\prod_{i=0}^{L-1}\frac{N-D-i}{N-i}\\&=\prod_{j=N-L+1}^{N}\frac{j-D}{j}=\prod_{j=N-L+1}^{N}1-\frac{D}{j}\leq\prod_{j=N-L+1}^{N}1-\frac{D}{N}=\left(1-\frac{D}{N}\right)^{L}.\end{align*} $$

### C Omitted Details from Section 3

### C.1 Omitted Details from Section 3.1

The following lemma shows that data availability sampling, in particular the consistency property, implies a collision-resistant hash function induced by the mapping from data to com via algorithm Encode, given that the commitment com is smaller than the data data.

Lemma 25. Let DAS = (Setup, Encode, V = (V₁, V₂), Ext) be a data availability sampling scheme with threshold T ∈ N. For any PPT algorithm A, there is a PPT algorithm B with T(B) ≈ T(A)+2T(Encode)+2TT(V₁) and

 $$ \begin{aligned}Pr\left[\begin{array}{c|c}\text{data}_{1}\neq\text{data}_{2}&\text{par}\leftarrow\text{Setup}(1^{\lambda}),\\ \wedge\text{com}_{1}=\text{com}_{2}&\text{(data}_{1},\text{data}_{2})\leftarrow\mathcal{A}(\text{par}),\\ &\left(\pi_{1},\text{com}_{1}\right):=\text{Encode}(\text{data}_{1}),\\ &\left(\pi_{2},\text{com}_{2}\right):=\text{Encode}(\text{data}_{2}).\end{array}\right]\leq Adv_{B,T,T,\text{DAS}}^{\text{cons}}(\lambda)+\text{negl}(\lambda).\end{aligned} $$

Proof. Let $\mathcal{A}$ be a PPT algorithm that on input par outputs $(\mathsf{data}_1, \mathsf{data}_2)$ such that there are $\pi_1, \pi_2$ with $(\pi_1, \mathrm{com}) = \mathrm{Encode}(\mathsf{data}_1)$ and $(\pi_2, \mathrm{com}) = \mathrm{Encode}(\mathsf{data}_2)$. Then, we construct an algorithm $\mathcal{B}$ against consistency of DAS as follows:

• When  $ \mathcal{B} $ gets as input par, it runs  $ (\mathsf{data}_{1},\mathsf{data}_{2}) \leftarrow \mathcal{A}(\mathsf{par}) $.

• Then, it computes  $ (\pi_1, \text{com}_1) := \text{Encode}(\text{data}_1) $ and  $ (\pi_2, \text{com}_2) := \text{Encode}(\text{data}_2) $. If  $ data_1 = data_2 $ or  $ com_1 \neq com_2 $,  $ \mathcal{B} $ aborts. Otherwise, it sets  $ com := \text{com}_1 = \text{com}_2 $.

• Next,  $ \mathcal{B} $ runs  $ \text{tran}_{j,i} \leftarrow \mathsf{V}_1^{\pi_j,Q}(\text{com}) $ for all  $ i \in [T] $ and  $ j \in \{1,2\} $

• Finally,  $ \mathcal{B} $ outputs (com,  $ (\text{tran}_{1,i})_{i=1}^{T} $,  $ (\text{tran}_{2,i})_{i=1}^{T} $).

We claim that, except with negligible probability,  $ \mathcal{B} $ breaks consistency. Namely, by completeness of DAS, with overwhelming probability the following event holds for both  $ j \in \{1, 2\} $:

 $$ \mathsf{d a t a}_{k}=\mathsf{E x t}(\mathsf{t r a n}_{j,1},\dots,\mathsf{t r a n}_{j,\ell_{j}}). $$

As data $ _{1} \neq data_{2} $, B breaks consistency.

### C.2 Extension: Repairability

Definition 20 (Repairable DAS). Let DAS = (Setup, Encode,  $ V = (V_1, V_2) $, Ext) be a data availability sampling scheme with encoding alphabet  $ \Sigma $, data length  $ K \in \mathbb{N} $, and encoding length  $ N \in \mathbb{N} $. We say that DAS is  $ (L, \ell) $-repairable, if there is a deterministic polynomial time algorithm Repair, with the following syntax and properties:

- Repair(com, tran₁, …, tranₚ) → π/⊥ takes as input a commitment com, a list of transcripts tranₙ, and outputs an encoding π ∈ Σ⁻⁴ or an abort symbol ⊥.

• Repair Liveness. Let A be a stateful algorithm and consider the following experiment G:

1. Run par  $ \leftarrow $ Setup $ (1^\lambda) $ and com  $ \leftarrow $  $ \mathcal{A}(\text{par}) $.

2. Run  $ (\text{tran}_i)_i=1 \leftarrow \text{Interact}[\mathsf{V}_1, \mathcal{A}]_{Q,L} $ (com) and  $ b_i := \mathsf{V}_2(\text{com}, \text{tran}_i) $ for all  $ i \in [L] $.

3. Run  $ (i_j)_j=1^\ell \leftarrow \mathcal{A}(\text{tran}_1, \ldots, \text{tran}_L) $.

4. Run  $ \bar{\pi} \leftarrow $ Repair(com, tran $ _{i_1}, \ldots, tran_{i_\ell} $).

5. For all  $ i \in [L] $, run  $ \text{tran}_i' \leftarrow \text{V}_1^{\bar{\pi},Q}(\text{com}) $ and  $ b_i' := \text{V}_2(\text{com}, \text{tran}_i') $.

Then, we require that for any stateful PPT algorithm A, the following advantage is negligible:

 $$ \mathrm{A d v}_{\mathcal{A},L,\ell,\mathrm{D A S},\mathrm{R e p a i r}}^{\mathrm{r e p a i r l i v e}}(\lambda):=\operatorname*{P r}_{\mathcal{G}}\left[\forall j\in[\ell]:b_{i_{j}}=1\wedge\exists i\in[L]:b_{i}^{\prime}=0\right]. $$

On Soundness and Consistency. One may wonder why we do not define any consistency or soundness property for a scenario where clients interact with a repaired codeword. We claim that this is not needed, as our consistency and soundness notions for data availability sampling schemes are robust enough to cover such scenarios. The intuition is that whatever scenario could happen including algorithm Repair and violate soundness or consistency, could be simulated by an adversary in the soundness or consistency game, respectively.

### C.3 Extension: Local Accessibility

Definition 21 (Locally Accessible DAS). Let DAS = (Setup, Encode, V = (V₁, V₂), Ext) be a data availability sampling scheme with data alphabet Γ, encoding alphabet Σ, data length K ∈ N, and encoding length N ∈ N. We say that DAS is locally accessible with query complexity L, if there is a PPT algorithm Access, with the following syntax and properties:

- Access $ \pi,L(\text{com},i) \to d/\perp $ takes as input a commitment  $ \text{com} $, and an index  $ i \in [K] $, gets  $ L $-time oracle access to an encoding  $ \pi \in \Sigma^N $, and outputs a symbol  $ d \in \Gamma $ or an abort symbol  $ \perp $.

• Local Access Completeness. For any par ∈ Setup(1λ), any i ∈ [K], and all data ∈ ΓK, we have

 $$ \Pr\left[d=data_{i}\middle|\begin{array}{l}(\pi,com):=Encode(data),\\d\leftarrow Access^{\pi,L}(com,i)\end{array}\right]\geq1-negl(\lambda). $$

- Local Access Consistency. For any stateful PPT algorithm  $ \mathcal{A} $, any index  $ i \in [K] $, and any integer  $ \ell = \text{poly}(\lambda) $, the following advantage is negligible:

 $$ \begin{aligned}Adv_{\mathcal{A},i,\ell,D A S,A c c e s s}^{a c c-c o n s}(\lambda):=Pr\left[\begin{array}{l}data\neq\perp\land d\neq\perp\land d\neq data_{i}\\\end{array}\left|\begin{array}{l}par\leftarrow Setup(1^{\lambda}),com\leftarrow\mathcal{A}(par),\\d\leftarrow Access^{\mathcal{A},L}(com,i),\ $ tran_{1},\ldots,tran_{\ell})\leftarrow\mathcal{A}(par),\\data:=Ext(com,tran_{1},\ldots,tran_{\ell})\\\end{array}\right.\right].\end{aligned} $$

### D Omitted Details from Section 5

Lemma 26. Let  $ \mathcal{C}_r: \mathbb{F}^{k_r} \to \mathbb{F}^{n_r} $ and  $ \mathcal{C}_c: \mathbb{F}^{k_c} \to \mathbb{F}^{n_c} $ be linear erasure codes with reception efficiencies  $ t_r, t_c $, respectively. Then,  $ \mathcal{C}_r \otimes \mathcal{C}_c: \mathbb{F}^{k_r \cdot k_c} \to \mathbb{F}^{n_r \cdot n_c} $ is an erasure code with reception efficiency

 $$ t=n_{c}n_{r}-(n_{c}-t_{c}+1)(n_{r}-t_{r}+1)+1. $$

Proof. We want to reconstruct data $\mathbf{M} \in \mathbb{F}^{k_c \times k_r}$ given a set of symbols of $\mathbf{X} = \mathbf{G}_c \mathbf{M} \mathbf{G}_r^\top \in \mathbb{F}^{n_c \times n_r}$. Let $\mathcal{X} \subseteq [n_c] \times [n_r]$ be the set of indices of these symbols in $\mathbf{X}$, i.e., for each $(i,j) \in \mathcal{X}$, we know $\mathbf{X}_{i,j} \in \mathbb{F}$. We say that a row $i \in [n_c]$ (resp. column $j \in [n_r]$) is saturated if we have at least $t_r$ (resp. $t_c$) symbols, i.e., $|\mathcal{X} \cap \{i\} \times [n_r]| \geq t_r$ (resp. $\mathcal{X} \cap [n_c] \times \{j\} \geq t_c$). Clearly, if a row (resp. column) is saturated, we can reconstruct the entire row (resp. column) using reconstruction of the codes $\mathcal{C}_r$ (resp. $\mathcal{C}_c$). Now, assume there is no way in which we can reconstruct $\mathbf{M}$. If at least $t_c$ rows are saturated, we can reconstruct the entire matrix, contradicting our assumption. Thus, assume that at most $t_c-1$ rows are saturated. Each saturated row has at most $n_r$ symbols in $\mathcal{X}$. There are $n_c-(t_c-1)$ remaining rows, all of which are not saturated. Each of those has at most $t_r-1$ symbols in $\mathcal{X}$. Thus, we have at most $(t_c-1)n_r+(n_c-t_c+1)(t_r-1)$ symbols in $\mathcal{X}$. In summary, if we can not reconstruct $\mathbf{M}$, then $\mathcal{X}$ has size at most $(t_c-1)n_r+(n_c-t_c+1)(t_r-1)$, which can be simplified to $n_c n_r-(n_c-t_c+1)(n_r-t_r+1)+1$.

### E Additional Notions for Erasure Code Commitments

In this section, we define additional notions for erasure code commitment schemes that are helpful in some cases.

### E.1 Message-Bound Openings

We formally define the notion of message-bound openings for erasure code commitment schemes. To recall, this notion is used when proving repairability of the resulting data availability sampling scheme, see Section 6.3.

Definition 22 (Message-Bound Openings). Let CC = (Setup, Com, Open, Ver) be an erasure code commitment scheme for an erasure code C with reception efficiency t and reconstruction algorithm Reconst. We say that CC has message-bound openings, if for every PPT algorithm A, the following advantage is negligible:

 $$ \begin{array}{l}\mathrm{d v}_{\mathcal{A},\mathsf{C C}}^{\mathrm{m b-o p e n}}(\lambda):=\\\operatorname{P r}\left[\begin{array}{c}\left|I_{0}\right|\geq t\wedge\left|I_{1}\right|\geq t\wedge\bot\notin\left\{m_{0},m_{1}\right\}\\ \wedge\quad m_{0}=m_{1}\\ \wedge\quad\forall i\in I_{0}:\mathsf{V e r}(\mathsf{c k},\mathsf{c o m}_{0},i,\hat{m}_{0,i},\tau_{0,i})=1\\ \wedge\quad\forall i\in I_{1}:\mathsf{V e r}(\mathsf{c k},\mathsf{c o m}_{1},i,\hat{m}_{1,i},\tau_{1,i})=1\\ \wedge\quad\exists i\in I_{1}:\mathsf{V e r}(\mathsf{c k},\mathsf{c o m}_{0},i,\hat{m}_{1,i},\tau_{1,i})=0\end{array}\right|\begin{array}{l}\mathsf{c k}\leftarrow\mathsf{S e t u p}(1^{\lambda}),\\ \left(\left(\mathsf{c o m}_{0},(\hat{m}_{0,i},\tau_{0,i})_{i\in I_{0}}\right)\right)\leftarrow\mathcal{A}(\mathsf{c k}),\\ m_{0}:=\mathsf{R e c o n s t}(((\hat{m}_{0,i})_{i\in I_{0}}),\\ m_{1}:=\mathsf{R e c o n s t}((\hat{m}_{1,i})_{i\in I_{1}})\end{array}\right].\end{array} $$

### E.2 Computational Uniqueness

We define the notion of computational uniqueness for erasure code commitments and study its implications.

Definition 23 (Computational Uniqueness). Let CC = (Setup, Com, Open, Ver) be an erasure code commitment scheme for an erasure code C with reception efficiency t and reconstruction algorithm Reconst. We say that CC is computationally unique, if for every PPT algorithm A, the following advantage is negligible:

 $$ \begin{aligned}Adv_{\mathcal{A},\mathsf{CC}}^{v-m_{0}}(\lambda)&:=&Pr\left[\begin{array}{c}\left|I_{0}\right|\geq t\wedge\left|I_{1}\right|\geq t\wedge\bot\notin\left\{m_{0},m_{1}\right\}\wedge m_{0}=m_{1}\\\wedge\forall i\in I_{0}:\operatorname{Ver}(\mathbf{ck},\mathbf{com}_{0},i,\hat{m}_{0,i},\tau_{0,i})=1\\\wedge\forall i\in I_{1}:\operatorname{Ver}(\mathbf{ck},\mathbf{com}_{1},i,\hat{m}_{1,i},\tau_{1,i})=1\\\wedge\operatorname{com}_{0}\neq\mathbf{com}_{1}\end{array}\right|\begin{array}{l}\mathbf{ck}\leftarrow\operatorname{Setup}(1^{\lambda}),\\\left(\begin{matrix}(\mathbf{com}_{0},(\hat{m}_{0,i},\tau_{0,i})_{i\in I_{0}})\\\left(\mathbf{com}_{1},(\hat{m}_{1,i},\tau_{1,i})_{i\in I_{1}}\right)\\m_{0}:=\operatorname{Reconst}((\hat{m}_{0,i})_{i\in I_{0}}),\\m_{1}:=\operatorname{Reconst}((\hat{m}_{1,i})_{i\in I_{1}})\end{array}\right).\end{array}\right]\end{aligned} $$

We show that computational uniqueness implies both message-bound openings and code-binding. Remark that the converse direction is not true. Message-bound openings do not imply computational uniqueness.

Lemma 27. Let $\mathcal{C}:\Gamma^k \to \Lambda^n$ be an erasure code. Let $\mathsf{CC} = (\mathsf{Setup}, \mathsf{Com}, \mathsf{Open}, \mathsf{Ver})$ be an erasure code commitment scheme for $\mathcal{C}$ such that $\mathsf{CC}$ is computationally unique. Then, $\mathsf{CC}$ has message-bound openings. Concretely, for any $PPT$ algorithm $\mathcal{A}$, there is a $PPT$ algorithm $\mathcal{B}$ with $\mathbf{T}(\mathcal{B}) \approx \mathbf{T}(\mathcal{A})$ and

 $$ \mathsf{A d v}_{\mathcal{A},\mathsf{C C}}^{\mathsf{m b-o p e n}}(\lambda)\leq\mathsf{A d v}_{\mathcal{B},\mathsf{C C}}^{\mathsf{c-u n i q}}(\lambda). $$

Proof. Let A be an adversary against the message-bound openings property of CC. We construct an adversary B against computational uniqueness as follows:

1.  $ \mathcal{B} $ gets as input a commitment key  $ \text{ck} $. Then,  $ \mathcal{B} $ runs  $ \mathcal{A} $ on input  $ \text{ck} $ to get commitments and openings  $ (\text{com}_0, (\hat{m}_{0,i}, \tau_{0,i})_{i \in I_0}) $ and  $ (\text{com}_1, (\hat{m}_{1,i}, \tau_{1,i})_{i \in I_1}) $.

2.  $ \mathcal{B} $ outputs  $ (\mathsf{com}_{0}, (\hat{m}_{0,i}, \tau_{0,i})_{i \in I_{0}}) $ and  $ (\mathsf{com}_{1}, (\hat{m}_{1,i}, \tau_{1,i})_{i \in I_{1}}) $.

Note that if  $ \complement_0 = \complement_1 $, the adversary  $ \mathcal{A} $ trivially loses the message-bound opening game. Thus, if  $ \mathcal{A} $ wins in the message-bound openings game,  $ \mathcal{B} $ wins the computational uniqueness game.

Lemma 28. Let $\mathcal{C}:\Gamma^k \to \Lambda^n$ be an MDS code. Let $\mathsf{CC} = (\mathsf{Setup}, \mathsf{Com}, \mathsf{Open}, \mathsf{Ver})$ be an erasure code commitment scheme for $\mathcal{C}$ such that $\mathsf{CC}$ is computationally unique and satisfies position-binding. Then, $\mathsf{CC}$ satisfies code-binding. Concretely, for any $PPT$ algorithm $\mathcal{A}$ there are $PPT$ algorithms $\mathcal{B}_1, \mathcal{B}_2$ with $\mathbf{T}(\mathcal{B}_1) \approx \mathbf{T}(\mathcal{A}), \mathbf{T}(\mathcal{B}_2) \approx \mathbf{T}(\mathcal{A})$, and

 $$ \mathsf{A d v}_{\mathcal{A},\mathsf{C C}}^{\mathsf{c o d e-b i n d}}(\lambda)\leq\mathsf{A d v}_{\mathcal{B}_{1},\mathsf{C C}}^{\mathsf{p o s-b i n d}}(\lambda)+\mathsf{A d v}_{\mathcal{B}_{2},\mathsf{C C}}^{\mathsf{c-u n i q}}(\lambda). $$

Proof. We first recall the code-binding game for an adversary $\mathcal{A}$ as in the statement. The adversary $\mathcal{A}$ first gets a freshly sampled commitment key $\text{ck} \leftarrow \text{Setup}(1^\lambda)$. Then, it outputs a commitment and a few openings. Denote them by $(\text{com}_0, (\hat{m}_0, i, \tau_0, i))_{i \in I_0}$ where $I_0 \subseteq [n]$ is the set of positions for which the adversary opens the commitment. Then, $\mathcal{A}$ breaks code-binding, if all openings verify, i.e., $\text{Ver}(\text{ck}, \text{com}_0, i, \hat{m}_0, i, \tau_0, i) = 1$ for all $i \in I_0$, and there is no codeword in $\mathcal{C}$ that is consistent with these openings $\hat{m}_0, i$. Our proof is as follows. We first observe that $|I_0| > k$ has to hold, as $\mathcal{C}$ is an MDS code. Next, let $R \subset I_0$ be the set of the first $k$ of the openings. Further, let $m = \text{Reconst}((\hat{m}_0, i)_{i \in R}, \hat{m}_1 = \mathcal{C}(m)$, and $(\text{com}_1, St) \leftarrow \text{Com}(\text{ck}, m)$. We know that $m \neq \bot$ as $\mathcal{C}$ is an MDS code. In other words, $\hat{m}_1 \in \mathcal{C}$ is the unique codeword consistent with the openings in $R$. Now, we can consider two cases. In the first case, $\text{com}_1 = \text{com}_0$. In this case, we break position-binding. This is because there has to be at least one $i^* \in I_0$ with $\hat{m}_0, i^* \neq \hat{m}_{1,i^*}$, as otherwise the openings output by $\mathcal{A}$ would be consistent with the codeword $\hat{m}_1$. A reduction can just compute an opening for $\hat{m}_{1,i^*}$ honestly and use it in combination with $\hat{m}_0, i^*$, $\tau_0, i^*$ to break position-binding. In the second case, $\text{com}_1 \neq \text{com}_0$. Here, we break computational uniqueness. Namely, a reduction can output $\text{com}_0$ with all openings output by the adversary in $R$, and output $\text{com}_1$ with enough honestly computed openings. We omit a more formal exposition of these two reductions.

### E.3 Extractability

We define the notion of extractability for erasure code commitment schemes, and study its implications. We start with the formal definition.

Definition 24 (Extractable CC). Let $\mathcal{C}:\Gamma^k \to \Lambda^n$ be an erasure code. Let $\mathbb{C} = (\text{Setup}, \text{Com}, \text{Open}, \text{Ver})$ be an erasure code commitment scheme for $\mathcal{C}$ such that $\text{Com}$ is deterministic, and use the notation $\text{com} = \widehat{\text{Com}}(\text{ck}, m)$ for $(\text{com}, St) = \text{Com}(\text{ck}, m)$. We say that $\text{CC}$ is extractable, if there is a PPT algorithm $\text{Ext}$, such that for any PPT algorithm $\mathcal{A}$, the following advantage is negligible:

 $$ \begin{array}{r}{\mathrm{A d v}_{\mathcal{A},\mathrm{E x t},\mathrm{C C}}^{\mathrm{e x t r}}(\lambda):=\mathrm{P r}\left[\begin{array}{c|c}{\mathrm{V e r}(\mathrm{c k},\mathrm{c o m},i,\hat{m},\tau)=1}&{\mathrm{c k}\leftarrow\mathrm{S e t u p}(1^{\lambda}),}\\ {\wedge}&{\widehat{\mathrm{C o m}}(\mathrm{c k},m)\neq\mathrm{c o m}}\\ \end{array}\right.\left.\begin{array}{l}{(\mathrm{c o m},i,\hat{m},\tau)\leftarrow\mathcal{A}(\mathrm{c k}),}\\ {m\leftarrow\mathrm{E x t}(\mathrm{c k},\mathrm{c o m},i,\hat{m},\tau)}\\ \end{array}\right].}\end{array} $$

Next, we show that extractability is a strong notion, in a sense that, in combination with position-binding, it implies code-binding and computational uniqueness.

Lemma 29. Let $\mathcal{C}:\Gamma^k \to \Lambda^n$ be an erasure code. Let $\mathsf{CC} = (\mathsf{Setup}, \mathsf{Com}, \mathsf{Open}, \mathsf{Ver})$ be an erasure code commitment scheme for $\mathcal{C}$ such that $\mathsf{Com}$ is deterministic. Further, assume that $\mathsf{CC}$ is position-binding and extractable. Then, $\mathsf{CC}$ is computationally unique. Concretely, for any $PPT$ algorithm $\mathcal{A}$, there are $PPT$ algorithms $\mathcal{B}, \mathcal{B}'$ with $\mathbf{T}(\mathcal{B}) \approx \mathbf{T}(\mathcal{A}), \mathbf{T}(\mathcal{B}') \approx \mathbf{T}(\mathcal{A})$, and

 $$ \begin{array}{r}{\mathrm{A d v}_{\mathcal{A},\mathrm{C C}}^{\mathrm{c-uniq}}(\lambda)\leq2\cdot\mathrm{A d v}_{\mathcal{B},\mathrm{E x t},\mathrm{C C}}^{\mathrm{e x t r}}(\lambda)+\mathrm{A d v}_{\mathcal{B}^{\prime},\mathrm{C C}}^{\mathrm{p o s-b i n d}}(\lambda).}\end{array} $$

Proof. Let $\mathcal{A}$ be an algorithm that breaks computational uniqueness of CC. That is, it gets as input a commitment key $\mathsf{ck}$ and outputs commitments $\mathsf{com}_0$ and $\mathsf{com}_1$ as well as two sets of openings $(\hat{m}_0,i, \tau_0,i)_i \in I_0$ and $(\hat{m}_{1,i}, \tau_{1,i})_{i \in I_1}$. It breaks computational uniqueness if $\mathsf{com}_0 \neq \mathsf{com}_1$, all openings verify, i.e., for all $b \in \{0,1\}$ and all $i \in I_b$ we have $\mathsf{Ver}(\mathsf{ck}, \mathsf{com}_b, i, \hat{m}_{b,i}, \tau_{b,i}) = 1$, and both sets of openings reconstruct to the same message, i.e., $|I_0| \geq t$, $|I_1| \geq t$, and for $m_0 := \mathsf{Reconst}((\hat{m}_0,i)_i \in I_0)$ and $m_1 := \mathsf{Reconst}((\hat{m}_{1,i})_{i \in I_1})$ we have $m_0 = m_1$ and both are not $\perp$. To prove that $\mathcal{A}$ can not win, our strategy is to extract two messages that commit to $\mathsf{com}_0$ and $\mathsf{com}_1$, respectively. For that, we use the extractability of CC. Then, we argue that they have to be the same. More precisely, we run $m_0^* \leftarrow \mathsf{Ext}(\mathsf{ck}, \mathsf{com}_0, i_0, \hat{m}_{0,i_0}, \tau_{0,i_0})$ for some arbitrary, say the first, $i_0 \in I_0$, and $m_1^* \leftarrow \mathsf{Ext}(\mathsf{ck}, \mathsf{com}_1, i_1, \hat{m}_{1,i_1}, \tau_{1,i_1})$ for some arbitrary, say the first, $i_1 \in I_1$, where $\mathsf{Ext}$ is the extractability that exists by extractability of CC. Extractability tells us that $\widehat{\mathsf{Com}}(\mathsf{ck}, m_0^*) = \mathsf{com}_0$ and $\widehat{\mathsf{Com}}(\mathsf{ck}, m_1^*) = \mathsf{com}_1$, except with probability $2 \cdot \mathsf{Adv}_{\mathcal{B},\mathsf{Ext},\mathsf{CC}}^{\mathsf{extr}}(\lambda)$ for some reduction $\mathcal{B}$. Thus, as soon as we can show that $m_0^* = m_1^*$, we know that $\mathcal{A}$ can not break computational uniqueness. To show this, we define $\tilde{m}_0 := \mathcal{C}(m_0)$ and $\tilde{m}_1 := \mathcal{C}(m_1)$. Using a reduction $\mathcal{B}'$ to position-binding, we can argue that $\hat{m}_{b,i} = \tilde{m}_{b,i}$ for both $b \in \{0,1\}$ and each $i \in I_b$, except with probability $\mathsf{Adv}_{\mathcal{B}',\mathsf{CC}}^{\mathsf{pos-bind}}(\lambda)$. Thus, we have

 $$ m_{0}^{*}=\mathsf{R e c o n s t}((\tilde{m}_{0,i})_{i\in I_{0}})=\mathsf{R e c o n s t}((\hat{m}_{0,i})_{i\in I_{0}})=m_{0}. $$

Analogously, we can show that  $ m_{1}^{*}=m_{1} $. As  $ m_{0}=m_{1} $, we can conclude that  $ m_{0}^{*}=m_{1}^{*} $.

Lemma 30. Let $\mathcal{C}:\Gamma^k \to \Lambda^n$ be an erasure code. Let $\mathsf{CC} = (\mathsf{Setup}, \mathsf{Com}, \mathsf{Open}, \mathsf{Ver})$ be an erasure code commitment scheme for $\mathcal{C}$ such that $\mathsf{Com}$ is deterministic. Further, assume that $\mathsf{CC}$ is position-binding and extractable. Then, $\mathsf{CC}$ is code-binding. Concretely, for any $PPT$ algorithm $\mathcal{A}$, there are $PPT$ algorithms $\mathcal{B}, \mathcal{B}'$ with $\mathbf{T}(\mathcal{B}) \approx \mathbf{T}(\mathcal{A}), \mathbf{T}(\mathcal{B}') \approx \mathbf{T}(\mathcal{A})$, and

 $$ \mathsf{A d v}_{\mathcal{A},\mathsf{C C}}^{\mathsf{c-uniq}}(\lambda)\leq\mathsf{A d v}_{\mathcal{B},\mathsf{E x t},\mathsf{C C}}^{\mathsf{e x t r}}(\lambda)+\mathsf{A d v}_{\mathcal{B}^{\prime},\mathsf{C C}}^{\mathsf{p o s-b i n d}}(\lambda). $$

Proof. We only sketch the proof, as it is very similar to the proof of Lemma 29. Let  $ \mathcal{A} $ be an adversary against code-binding of CC. That is,  $ \mathcal{A} $ gets as input a commitment key  $ ck \leftarrow \text{Setup}(1^\lambda) $ and outputs a commitment and a few openings. We denote them by  $ (\text{com}, (\hat{m}_i, \tau_i)_{i \in I}) $, where  $ I \subseteq [n] $ is the set

of positions for which the adversary opens the commitment. The adversary $\mathcal{A}$ breaks code-binding if all openings verify, and there is no codeword that is consistent with the openings. Now, our goal is to break position-binding with a reduction $\mathcal{B}$. For that, $\mathcal{B}'$ first runs the extractor, namely, it runs $m^* \leftarrow \text{Ext}(\text{ck}, \text{com}, i_0, \hat{m}_{i_0}, \tau_{i_0})$ for some arbitrary, say the first, $i_0 \in I$. Except with probability $\text{Adv}_{\mathcal{B}, \text{Ext}, \mathcal{C}}^{\text{extr}}(\lambda)$ for some reduction $\mathcal{B}$, we have that $\text{Com}(\text{ck}, m^*) = \text{com}$. Then, setting $\hat{m}^* := \mathcal{C}(m^*)$, reduction $\mathcal{B}'$ can compute valid openings $\tau_i^*$ for $\hat{m}^*$ with respect to $\text{com}$ for any position $i \in [n]$. As no codeword is consistent with $\mathcal{A}'$s openings $\hat{m}_i$, we know that there is at least one $i^* \in I$ for which $\hat{m}_i^* \neq \hat{m}_{i^*}$. Reduction $\mathcal{B}'$ can thus output $\text{com}, i^*$, $\hat{m}_i^*$, $\tau_i^*$, $\hat{m}_{i^*}$, $\tau_{i^*}$ to break position-binding of $\text{CC}$.

Lemma 31 (Informal). The KZG polynomial commitment scheme [KZG10] is extractable in the algebraic group model.

Proof Sketch. Suppose $\mathcal{A}$ is an algebraic algorithm running in the extractability game. It gets as input a commitment key $g, g^s, \ldots, g^{s^{k-1}}$ for some degree bound $k-1$. Then, it outputs a commitment $\text{com}$, elements $x, y \in \mathbb{Z}_p$, and an opening $\tau$. As both $\text{com}$ and $\tau$ are group elements and $\mathcal{A}$ is algebraic, it also outputs coefficients $\alpha_i$ and $\gamma_i$ such that $\text{com} = \prod_{i=0}^{k-1} \left( g^{s^i} \right)^{\alpha_i}$ and $\tau = \prod_{i=0}^{k-1} \left( g^{s^i} \right)^{\gamma_i}$. The extractor can now just output the polynomial defined by coefficients $\alpha_i$.

### F Omitted Details from Section 6

### F.1 Omitted Details from Section 6.1

Proof of Lemma 2. Let $\mathcal{A}$ be an adversary against reconstruction-binding of $\mathbb{C}\mathbb{C}$. That is, $\mathcal{A}$ outputs $(\mathrm{com}, (\hat{m}_i, \tau_i)_{i\in I}, (\hat{m}_i', \tau_i')_{i\in I'})$ on input $\mathbf{ck} \leftarrow \mathsf{Setup}(1^\lambda)$. We distinguish two cases by defining the following events:

- Event Win: This event occurs if $\mathcal{A}$ breaks reconstruction-binding, i.e. for $m := \text{Reconst}((\hat{m}_i)_{i \in I})$ and $m' := \text{Reconst}((\hat{m}_i')_{i \in I'})$ we have $|I| \geq t, |I'| \geq t$, $m \neq m', \text{Ver}(ck, \text{com}, i, \hat{m}_i, \tau_i) = 1$ for all $i \in I$ and $\text{Ver}(ck, \text{com}, i, \hat{m}_i', \tau_i') = 1$ for all $i \in I'$.

• Event BreakPosBind: This event occurs if there is an index  $ i^* \in I \cap I' $ such that  $ \hat{m}_i^* \neq \hat{m}_{i^*}' $.

Clearly, we can write

 $$ \mathrm{A d v}_{\mathcal{A},k,\mathsf{C C}}^{\mathsf{r e c-b i n d}}(\lambda)=\mathrm{P r}\left[\mathrm{W i n}\right]=\mathrm{P r}\left[\mathrm{W i n}\wedge\mathsf{B r e a k P o s B i n d}\right]+\mathrm{P r}\left[\mathrm{W i n}\wedge\neg\mathsf{B r e a k P o s B i n d}\right]. $$

We bound these terms individually. First, consider the event  $ \text{Win} \wedge \text{BreakPosBind} $. Note that if this event occurs, then especially  $ \tau_i^* $ and  $ \tau_i^* $ are valid openings for  $ \hat{m}_{i^*} \neq \hat{m}_{i^*}^* $, respectively. Therefore, we can easily bound the probability of this event using a reduction  $ \mathcal{B}_1 $ that breaks position-binding of CC as follows: On input ck,  $ \mathcal{B}_1 $ runs  $ \mathcal{A}(\text{ck}) $ and gets (com,  $ (\hat{m}_{i^*}, \tau_i)_{i \in I} $,  $ (\hat{m}_{i^*}, \tau_i')_{i \in I'} $). Then,  $ \mathcal{B}_1 $ checks if event  $ \text{Win} \wedge \text{BreakPosBind} $ occurs, which can be done efficiently. If it does,  $ \mathcal{B}_1 $ outputs (com,  $ i^* $,  $ \hat{m}_{i^*} $,  $ \tau_i^* $,  $ \hat{m}_{i^*} $,  $ \tau_i^* $), where  $ i^* $ is the index in the definition of  $ \text{BreakPosBind} $. It is easy to see that  $ \mathcal{B}_1 $ breaks position-binding if event  $ \text{Win} \wedge \text{BreakPosBind} $ occurs, and the running time of  $ \mathcal{B}_1 $ is dominated by running  $ \mathcal{A} $.

Next, we bound the probability of Win ∧ ¬BreakPosBind. Assume that this event occurs. Then we know that for all  $ i \in I \cap I' $ we have  $ \hat{m}_i = \hat{m}_i' $, i.e.  $ \hat{m} $ and  $ \hat{m}' $ are consistent on  $ I \cap I' $. We can define

 $$ \hat{m}_{i}^{*}:=\begin{cases}{\hat{m}_{i},}&{\mathrm{i f~}i\in I\setminus I^{\prime},}\\ {\hat{m}_{i}=\hat{m}_{i}^{\prime},}&{\mathrm{i f~}i\in I\cap I^{\prime},}\\ {\hat{m}_{i}^{\prime},}&{\mathrm{i f~}i\in I^{\prime}\setminus I}\\ \end{cases}\mathrm{~f o r~a l l~}i\in I\cup I^{\prime}. $$

Note that for all  $ \hat{m}_i^*, i \in I \cup I' $, we have valid openings  $ \tau_i $, as  $ \text{Win} $ occurs. We claim that there is no  $ m^* \in \Gamma^k $, such that the codeword  $ c = \mathcal{C}(m^*) $ is consistent with  $ (\hat{m}_i^*)_{i \in I \cup I'} $. Once this is established, the reduction  $ \mathcal{B}_2 $ breaking code-binding by outputting  $ (\hat{m}_i^*)_{i \in I \cup I'} $ is clear. Assume towards contradiction that such an  $ m^* \in \Gamma^k $ exists. Then by completeness of algorithm  $ \text{Reconst} $, and because both  $ (\hat{m}_i)_{i \in I} $ and  $ (\hat{m}_i')_{i \in I'} $ are a subsequence of  $ c = \mathcal{C}(m^*) $, we have  $ \text{Reconst}_k((\hat{m}_i)_{i \in I}) = m^* = \text{Reconst}((\hat{m}_i')_{i \in I'}) $. A contradiction.

### F.2 Omitted Details from Section 6.2

Proof of Lemma 3. We want to analyze the quality of algorithm Sample $ _{wr} $ that samples indices uniformly at random with replacement. Recall that for that, we have to upper bound the probability that  $ \ell $ invocations of Sample $ _{wr} $(1 $ ^Q $, 1 $ ^N $) jointly sample at most  $ \Delta $ distinct indices in [N]. To this end, consider the experiment  $ (i_{l,j})_{j\in[Q]}\leftarrow\text{Sample}_{wr}(1^Q,1^N) $ for each  $ l\in[\ell] $ as in the definition of index samplers. For each subset  $ I\subseteq[N] $ with  $ |I|\leq\Delta $, let  $ E_I $ be the event that the sampled indices  $ i_{l,j} $ are all in I. Then, it is clear that

 $$ \operatorname*{P r}_{\mathcal{G}}\left[\left|\bigcup_{l\in[\ell]}\{i_{l,j}\mid j\in[Q]\}\right|\leq\Delta\right]\leq\sum_{I\subseteq[N],|I|\leq\Delta}\operatorname*{P r}\left[E_{I}\right]. $$

Now, we fix one such subset I. The probability of  $ E_{I} $ is at most

 $$ \left(\frac{|I|}{N}\right)^{Q\ell}\leq\left(\frac{\Delta}{N}\right)^{Q\ell}, $$

because all  $ Q\ell $ indices are sampled independently. As there are  $ \binom{N}{\Delta} $ such subsets, the first part of the lemma follows. To obtain the simpler bound, we use the fact

 $$ \forall n\in\mathbb{N}:\forall k\in[n]:\begin{pmatrix}n\\ k\end{pmatrix}<\left(\frac{n\cdot e}{k}\right)^{k}. $$

Then, we have

 $$ \binom{N}{\Delta}\left(\frac{\Delta}{N}\right)^{Q\ell}<\frac{N^{\Delta}\cdot e^{\Delta}}{\Delta^{\Delta}}\cdot\frac{\Delta^{Q\ell}}{N^{Q\ell}}=e^{\Delta}\cdot N^{\Delta-Q\ell}\cdot\Delta^{Q\ell-\Delta}. $$

Now, we use  $ c := \Delta / N $, and conclude with

 $$ e^{\Delta}\cdot N^{\Delta-Q\ell}\cdot\Delta^{Q\ell-\Delta}=e^{\Delta}\cdot N^{\Delta-Q\ell}\cdot(c N)^{Q\ell-\Delta}\leq e^{\Delta}\cdot c^{Q\ell-\Delta}\leq c^{\log_{c}(e)\Delta+Q\ell-\Delta}\leq c^{Q\ell-(1-\log_{c}(e))\Delta}. $$

Proof of Lemma 4. We analyze the locality of sampling uniformly with replacement. For that, consider the experiment  $ (i_j)_{j\in[Q]}\leftarrow\mathsf{Sample}_{wr}(1^Q,1^N) $ and define the set  $ \Gamma:=\{\mathcal{S}(i_j)\mid j\in[Q]\} $. Then, we need to upper bound the probability that  $ \Gamma $ is of size at most  $ D $. For that, fix any subset  $ I\subset\mathbb{N} $ of size  $ D $. Using a union bound, we can as well upper bound the probability of  $ \Gamma\subseteq I $. As all indices  $ i_j $ are sampled independently from  $ [N] $, and  $ \mathcal{S} $ is a  $ Q $-to-1 mapping onto a set of size  $ N/Q $, the probability that  $ I\subset\mathbb{N} $ is  $ (D/(N/Q))^Q $. In combination, we have

 $$ \begin{align*}\Pr\left[|\Gamma|\leq D\right]&=\binom{N/Q}{D}\cdot\Pr\left[\Gamma\subseteq I\right]=\binom{N/Q}{D}\cdot\left(\frac{D}{N/Q}\right)^{Q}\\&<\left(\frac{e\cdot N/Q}{D}\right)^{D}\cdot\left(\frac{D}{N/Q}\right)^{Q}=e^{D}\cdot\left(\frac{D}{N/Q}\right)^{Q-D},\end{align*} $$

where we used the fact

 $$ \forall n\in\mathbb{N}:\forall k\in[n]:\begin{pmatrix}n\\ k\end{pmatrix}<\left(\frac{n\cdot e}{k}\right)^{k}. $$

□

Proof of Lemma 5. We want to analyze the quality of sampling uniformly without replacement. Recall that for that, we have to upper bound the probability that $\ell$ invocations of $\text{Sample}_{\text{wor}}(1^Q, 1^N)$ jointly sample at most $\Delta$ distinct indices in [N]. Consider the experiment $(i_{l,j})_{j \in [Q]} \leftarrow \text{Sample}(1^Q, 1^N)$ for each $l \in [\ell]$ as in the definition of index samplers. For each subset $I \subseteq [N]$ with $|I| = \Delta$, let $E_I$ be the event that the sampled indices $i_{l,j}$ are all in $I$. Then, we have

 $$ \Pr\left[\left|\bigcup_{l\in[\ell]}\{i_{l,j}\mid j\in[Q]\}\right|\leq\Delta\right]\leq\sum_{I\subseteq[N],|I|\leq\Delta}\Pr\left[E_{I}\right]. $$

Now, fix one such subset I. The probability of  $ E_{I} $ is at most

 $$ \left(\binom{\Delta}{Q}\bigg/\binom{N}{Q}\right)^{\ell}. $$

This is because each of the  $ \ell $ invocations of the sampler samples uniformly from  $ \binom{[N]}{Q} $, and all invocations are independent. As there are  $ \binom{N}{\Delta} $ such subsets I, the claim follows.

Proof of Lemma 6. It is clear that the claim holds for  $ N \mod Q \neq 0 $. Thus, assume that  $ N $ is a multiple of  $ Q $ and set  $ N' := N/Q $. Now, observe that  $ \ell $ copies of  $ \text{Sample}_{\text{seg}} $ output at most  $ \Delta $ distinct indices, if and only of they sample at most  $ \Delta' := \Delta/Q $ distinct segments  $ \text{seg}_1, \ldots, \text{seg}_\ell \in [N'] $. We can view the sampling of  $ \text{seg}_1, \ldots, \text{seg}_\ell $ as  $ \ell $ independent executions of  $ \text{Sample}_{wr}(1^1, 1^{N'}) $, which shows the claim.

### F.3 Omitted Details from Section 6.3

Proof of Lemma 11. Let $\mathcal{A}$ be an algorithm against local access consistency, and let $i_0 \in [K]$. We first recall the local access consistency game. In this game, $\mathcal{A}$ first gets parameters $\text{par} = \text{ck} \leftarrow \text{Setup}(1^\lambda)$ as input. Then, it outputs a commitment $\text{com}$. Next, algorithm Access is run on input $\text{com}, i_0$ and with oracle access to $\mathcal{A}$. The algorithm outputs $d$ after making exactly one query to $\mathcal{A}$. Finally, $\mathcal{A}$ outputs transcripts $(\text{tran}_1, \ldots, \text{tran}_\ell)$ and data := Ext(\text{com}, \text{tran}_1, \ldots, \text{tran}_\ell)$ is run. The adversary $\mathcal{A}$ breaks local access consistency, if data $\neq \perp$, $d \neq \perp$, and $d \neq \mathsf{data}_{i_0}$. Intuitively, this means that the outputs of Access and Ext are not consistent. Now, let us introduce some notation. As in algorithm Ext, write $\text{tran}_l := (i_{l,j}, \widehat{\text{data}}_{l,i_{l,j}}, \tau_{l,i_{l,j}})_{j \in [Q]}$ for each $l \in [L]$, and define the set $I \subseteq [N]$ of indices $i \in [N]$ such that there is a $(l,j) \in [L] \times [Q]$ with $i_{l,j} = i$. Further, let $(\widehat{\text{data}}_{i_0}^' \tau_{i_0}')$ be the result of the query that Access made. Assuming data $\neq \perp$, we know that $|I| \geq t$, by definition of Ext. Define the index $i_1 := \hat{i}_0$ if $\hat{i}_0 \in I$ and $i_1 \in I$ arbitrary if $\hat{i}_0 \notin I$. Then, define the set $I' := (I \setminus \{i_1\}) \cup \{\hat{i}_0\}$. Clearly, we have $|I'| = |I| \geq t(K)$. For each $i \in I$, define $\widehat{\text{data}}_i$ exactly as in algorithm Ext. Further, for each $i \in I$ define $\tau_i$ to be the corresponding opening such that $\text{Ver}(\text{ck}, \text{com}, i, \widehat{\text{data}}_i, \tau_i) = 1$. For each $i \in I \setminus \{i_1\}$, set $\widehat{\text{data}}_i' := \widehat{\text{data}}_i$ and $\tau_i' := \tau_i$. Now, we claim that $(\text{com}, (\widehat{\text{data}}_i, \tau_i))_i \in I$, $(\widehat{\text{data}}_i', \tau_i')_i \in I'$ is an output with which a reduction $\mathcal{B}$ can break reconstruction-binding of CC. Clearly, a reduction can compute this output. Further, we $|I| \geq t$ and $|I'| \geq t$, as already observed. As data $\neq \perp$ and $d \neq \perp$, we know that all openings are valid, i.e. $\text{Ver}(\text{ck}, \text{com}, i, \hat{m}_i', \tau_i') = 1$ and $\text{Ver}(\text{ck}, \text{com}, i, \hat{m}_i', \tau_i') = 1$ for all $i \in I, i' \in I'$. Finally, we know that the $i_0$th symbol of $m := \text{Reconst}((\hat{m}_i)_{i \in I})$ and the $i_0$th symbol of $m' := \text{Reconst}((\hat{m}_i')_{i \in I'})$ are distinct. This is because the $i_0$th symbol of $m'$ is $d$ by the second property generalized systematic encoding, and the $i_0$th symbol of $m$ is $\text{data}_{i_0}$ by definition of Ext.

Proof of Lemma 12. Let $\mathcal{A}$ be an adversary against the $(L,\ell)$-repairability of DAS[CC, Sample]. We first recall the repair liveness game. In this game, parameters par := ck ← Setup(1^λ) are generated and $\mathcal{A}$ is run on input par. Then, $\mathcal{A}$ outputs a commitment com. After that, $L$ copies of $V_1(\text{com})$ are run, where their oracle queries are answered by $\mathcal{A}$. Let $\text{tran}_1, \ldots, \text{tran}_L$ denote the resulting transcripts that they output, and $b_i := \mathsf{V}_2(\text{com}, \text{tran}_i)$ for all $i \in [L]$. Then, $\mathcal{A}$ gets to pick a subset $\{i_1, \ldots, i_\ell\} \subseteq [L]$ of $\ell$ of these transcripts and algorithm Repair is run on input com, $\text{tran}_{i_1}, \ldots, \text{tran}_{i_\ell}$. It outputs a new encoding $\bar{\pi}$ or $\bot$. If it does not output $\bot$, all $L$ clients are run again, i.e., $\text{tran}_i' \leftarrow \mathsf{V}_1^{\bar{\pi},Q}(\text{com})$ and $b_i := \mathsf{V}_2(\text{com}, \text{tran}_i')$ for all $i \in [L]$. The adversary $\mathcal{A}$ breaks repair liveness, if for all $j \in [L]$, we have $b_{ij} = 1$, i.e., all selected clients accepted before the repairing took place, but there is some $i \in [L]$ with $b_i' = 0$. The latter includes the case where Repair output $\bot$. We will now distinguish two cases, captured by the following two events.

• Event RepairBot: This event occurs, if Repair outputs ⊥ and the adversary breaks repair liveness.

- Event RepairSucc: This event occurs, if Repair does not output ⊥, i.e., it outputs an encoding  $ \bar{\pi} $, and the adversary breaks repair liveness.

Clearly, we have

 $$  Adv_{\mathcal{A},L,\ell,D A S[C C,S a m p l e],R e p a i r}^{r e p a i r l i v e}(\lambda)\leq\Pr\left[R e p a i r B o t\right]+R e p a i r S u c c. $$

We will bound the probability of both events separately. Let us start with event RepairBot. Recall that algorithm Repair internally runs Ext(com, tran_{i_1}, ..., tran_{i_\ell}), and only outputs  $ \perp $ if Ext does. Therefore, if

event RepairBot occurs, the adversary first received parameters, then it output a commitment, and then it found  $ \ell $ accepting out of  $ L $ transcripts, such that these do not suffice to reconstruct the data. Intuitively, this means that the adversary breaks subset-soundness of DAS[CC, Sample]. Indeed, one can make this intuition formal. We only sketch a reduction  $ \mathcal{B}_1 $ here. A reduction that runs in the subset-soundness game gets as input par and forwards them to  $ \mathcal{A} $. Then, it gets a commitment com and outputs it to the subset-soundness game. It simulates the interaction with  $ L $ copies of  $ V_1 $ by forwarding between  $ \mathcal{A} $ and the subset-soundness game. Finally, it forwards  $ \mathcal{A} $'s selection of indices  $ i_1, \ldots, i_\ell $ to the subset-soundness game. One can easily see that this reduction breaks  $ (L, \ell) $-subset-soundness if event RepairBot occurs. We have

 $$ \operatorname{P r}\left[\mathsf{R e p a i r B o t}\right]\leq\mathsf{A d v}_{\mathcal{B}_{1},L,\ell,\mathsf{D A S}}^{\mathsf{s u b-s o u n d}}(\lambda). $$

Next, we want to bound the probability of event  $ \overline{\text{RepairSucc}} $. Intuitively, if this event occurs, then Ext run within Repair was able to reconstruct data  $ \overline{\text{data}} $, and thus  $ (\bar{\pi}, \overline{\text{com}}) = \text{Encode}(\overline{\text{data}}) $, but the new encoding  $ \bar{\pi} $ does not verify with respect to the initial commitment  $ \text{com} $. If we recall the structure of an encoding, i.e., each symbol consists of an opening for the erasure code commitment  $ \text{com} $, then we see that the adversary must intuitively break message-bound openings in this case. More precisely, this works as follows. Because  $ \overline{\text{data}} $ was extracted by Ext, we know by definition of Ext that the transcripts  $ \text{tran}_{i_1}, \ldots, \text{tran}_{i_\ell} $ contain at least  $ t $ valid symbols and openings  $ \overline{\text{data}}_i, \tau_i $ for  $ \overline{\text{commitment}} $  $ \text{com} $. Due to completeness, the new encoding  $ \bar{\pi} $ contains at least  $ t $ valid openings  $ \bar{\tau}_i $ for  $ \overline{\text{data}}_i $ and commitment  $ \overline{\text{com}} $. Here  $ \overline{\text{data}} := \mathcal{C}(\overline{\text{data}}) $ as computed in  $ \text{Encode} $ by algorithm Repair. Assuming adversary breaks repair liveness, we know that one of the clients after the repairing rejects, i.e.,  $ b_i' = 0 $ for some  $ i \in [L] $. By definition of  $ \mathbf{V}_2 $, this means that at least one of the new valid openings, say the  $ j $th, contained in the new encoding  $ \bar{\pi} $ does not work with the old commitment  $ \text{com} $. More precisely, letting  $ \overline{\text{data}}_j, \bar{\tau}_j $ be the  $ j $th symbol of  $ \bar{\pi} $, we know that  $ \text{Ver}(\text{ck}, \text{com}, j, \overline{\text{data}}_j, \bar{\tau}_j) = 0 $. This leads to a reduction  $ \mathbf{B}_2 $ that breaks the message-bound openings property of CC. The reduction gets as input the commitment key  $ ck $ and runs  $ \mathcal{A} $ in the repair liveness game with  $ \text{par} := \text{ck} $. If event  $ \text{RepairSucc} $ occurs, the reduction outputs  $ \text{com}, (\overline{\text{data}}_j, \tau_j)_j $ and  $ \overline{\text{com}}, (\overline{\text{data}}_j, \bar{\tau}_i)_j $. We have

 $$ \operatorname*{P r}\left[\mathsf{R e p a i r S u c c}\right]\leq\mathsf{A d v}_{\mathcal{B}_{2},\mathsf{C C}}^{\mathsf{m b-o p e n}}(\lambda). $$

□

### G Omitted Details from Section 7

Proof of Lemma 14. We prove the statement via a sequence of games. Let A be an algorithm in the code-binding game of CC[C, VC, PS].

 $ \underline{\text{Game G}_0} $: We define  $ \mathbf{G}_0 $ to be the code-binding game of  $ \text{CC}[\mathcal{C}, \text{VC}, \text{PS}] $. That is, adversary  $ \mathcal{A} $ gets as input  $ \text{ck} = (\text{ck}_{\text{VC}}, \text{crs}, \rho) $ generated as in  $ \text{Setup} $ and outputs  $ (\text{com}, (\hat{m}_i, \tau_i)_{i \in I}) $ to break code-biding. The game outputs 1 if all  $ \tau_i $ are valid openings for  $ \hat{m}_i $, i.e.  $ \text{Ver}(\text{ck}, \text{com}, i, \hat{m}_i, \tau_i) = 1 $ for all  $ i \in I $, and there is no  $ m $ such that the  $ \hat{m}_i $ are compatible with  $ \mathcal{C}(m) $. By definition, we have

 $$ \operatorname{Pr}\left[\mathbf{G}_{0}\Rightarrow1\right]=Adv_{\mathcal{A},\mathsf{CC}[\mathcal{C},\mathsf{VC},\mathsf{PS}]}^{code-bind}(\lambda). $$

Game  $ \mathbf{G}_1 $: This game is defined as  $ \mathbf{G}_0 $, with an additional check at the end. Namely, after  $ \mathcal{A} $ outputs  $ \overline{\mathrm{com}}, (\hat{m}_i, \tau_i)_{i\in I} $, the game parses  $ \mathrm{com} = (\mathrm{com}_{\mathcal{V}C}, \pi) $ and sets  $ \mathrm{stmt} := (\mathrm{ck}_{\mathcal{V}C}, \mathrm{com}_{\mathcal{V}C}, \rho) $. Then, it runs  $ \mathrm{witn} \leftarrow \mathrm{PS.Ext}(\mathrm{crs}, \mathrm{stmt}, \pi) $. It returns 0 if we have  $ (\mathrm{stmt}, \mathrm{witn}) \notin \mathcal{R} $ and  $ \mathrm{PVer}(\mathrm{crs}, \mathrm{stmt}, \pi) = 1 $. Otherwise, it returns whatever  $ \mathbf{G}_0 $ would have returned. It is clear that the difference between  $ \mathbf{G}_0 $ and  $ \mathbf{G}_1 $ can be bounded using a straight-forward reduction  $ \mathcal{B}_1 $ that breaks knowledge soundness of PS. We have

 $$ \left|\operatorname{Pr}\left[\mathbf{G}_{0}\Rightarrow1\right]-\operatorname{Pr}\left[\mathbf{G}_{1}\Rightarrow1\right]\right|\leq\operatorname{Adv}_{\mathcal{B}_{1},\mathrm{PS},\mathrm{PS}.\mathrm{Ext}}^{\mathrm{kn-sound}}(\lambda). $$

Finally, we bound the probability that $\mathbf{G}_1$ outputs 1 using a reduction $\mathcal{B}_2$ that breaks position-binding of $\mathcal{V}$C. The intuition is as follows: If $\mathbf{G}_1$ outputs 1, we extracted witness $\text{witn} = m$ such that for $\hat{m}^* := \mathcal{C}(m)$ we have $(\text{com}_{\mathcal{V}C}, St_{\mathcal{V}C}) = \mathcal{V}$C. $\text{Com}(\text{ck}_{\mathcal{V}C}, \hat{m}^*; \rho)$ for some state $St_{\mathcal{V}C}$, due to the definition of relation $\mathcal{R}$. If $\mathbf{G}_1$ outputs 1, then in particular $\mathcal{A}$ breaks code-binding. Thus, there must be some index $i$ such that the

returned $\hat{m}_i$ is different from $\hat{m}_i^*$. By completeness of VC, we can use $St_{VC}$ to compute a valid opening $\tau_i$ for $\hat{m}_i^*$ for commitment $\text{com}_{VC}$. Now, we have valid openings for $\text{com}_{VC}$ for two different symbols $\hat{m}_i \neq \hat{m}_i^*$ at position $i$, i.e. we break position-binding. It is trivial to turn this intuition into a formal reduction $\mathcal{B}_2$, which gets as input $\text{ck}_{VC}$, simulates $\mathbf{G}_1$ for $\mathcal{A}$, and outputs $\hat{m}_i, \hat{m}_i^*$ along with their respective openings. We have

 $$ \operatorname*{P r}\left[\mathbf{G}_{1}\Rightarrow1\right]\leq\mathsf{A d v}_{\mathcal{B}_{2},\mathsf{V C}}^{\mathsf{p o s-b i n d}}(\lambda). $$

Proof of Lemma 15. We prove the statement via a sequence of games.

Game G₀: Game G₀ is the message-bound openings game. Recall that in this game, A outputs com₀, (∂m₀,₀, τ₀,₁)ᵢₙ₊₁, (∂m₁,₀, τ₁,₁)ᵢₙ₊₁ on input ck = (ckᵥc, crₛ, ρ). The game G₀ outputs 1, i.e., A breaks the message-bound openings property of CC, if both sets of openings (∂m₀,₁, τ₀,₁)ᵢₙ₊₁, i.e., A allows to reconstruct the same message, the openings verify with respect to their respective commitments, but the openings in I₁ do not all verify with respect to com₀. Recall that com₀ and com₁ have the form com₀ = (comₕc,₀, π₀) and com₁ = (comₕc,₁, π₁), respectively. It will be our goal to show that the vector commitments comₕc,₀, comₕc,₁ are the same. It is clear from the construction that this implies that A can not win. We have

 $$ \mathrm{A d v}_{\mathcal{A},\mathsf{C C}}^{\mathsf{m b-o p e n}}(\lambda)=\operatorname*{P r}\left[\mathbf{G}_{0}\Rightarrow1\right]. $$

Game G₁: In G₁, we use the knowledge extractor PS.Ext of PS to extract witnesses from the proofs π₀ and π₁ contained in com₀ and com₁. Namely, the game runs m₀ ← PS.Ext(crs, (ckv_c, com_v_c, 0, ρ), π₀) and m₁ ← PS.Ext(crs, (ckv_c, com_v_c, 1, ρ), π₁). The game outputs 0 if the first component of VC.Com(ckv_c, C(m₀); ρ) is not com_v_c, or the first component of VC.Com(ckv_c, C(m₁); ρ) is not com_v_c,¹. Otherwise, G₁ behaves as G₀. Clearly, the difference between games G₀ and G₁ can bounded using the knowledge soundness of PS, i.e., we have a reduction B₁ with

 $$ \left|\mathrm{Pr}\left[\mathbf{G}_{0}\Rightarrow1\right]-\mathrm{Pr}\left[\mathbf{G}_{1}\Rightarrow1\right]\right|\leq2\cdot\mathrm{Adv}_{\mathcal{B}_{1},\mathrm{PS},\mathrm{PS}.\mathrm{Ext}}^{\mathrm{kn-sound}}(\lambda). $$

Game $\mathbf{G}_2$: Game $\mathbf{G}_2$ is as game $\mathbf{G}_1$, but with an additional modification of the winning condition. Namely, if there is a $b \in \{0,1\}$, and an $i \in I_b$ such that $\hat{m}_{b,i} \neq \mathcal{C}(m_b)_{i}$, then the game outputs 0. Otherwise, it behaves as $\mathbf{G}_1$. Here, recall that $\hat{m}_{b,i}$ is part of the opening that $\mathcal{A}$ outputs, and $m_b$ is the message that the game extracts from $\pi_b$ as described in $\mathbf{G}_1$. Note that for $\hat{m}_{b,i}$, $\mathcal{A}$ also outputs an opening $\tau_{b,i}$ that verifies with respect to $\text{com}_{\mathcal{C},b}$. Also, a reduction can obtain a valid opening for $C(m_b)_{i}$ using $\rho$. Thus, we can easily construct a reduction $\mathcal{B}_2$ that breaks position-binding of $\mathcal{V}$ if $\mathcal{A}$ can distinguish $\mathbf{G}_1$ and $\mathbf{G}_2$. We have

 $$ \left|\mathrm{P r}\left[\mathbf{G}_{1}\Rightarrow1\right]-\mathrm{P r}\left[\mathbf{G}_{2}\Rightarrow1\right]\right|\leq\mathrm{A d v}_{\mathcal{B}_{2},\mathsf{V C}}^{\mathsf{p o s-b i n d}}(\lambda). $$

We can now argue that the probability that  $ G_{2} $ outputs 1 is zero. For that, observe that

 $$ m_{0}=\mathsf{R e c o n s t}((\hat{m}_{0,i})_{i\in I_{0}})=\mathsf{R e c o n s t}((\hat{m}_{1,i})_{i\in I_{1}})=m_{1}, $$

where the second equality follows from the winning condition of message-bound openings, and the first and last equality follow from correctness of Reconst. From that, we get that the vector commitments  $ \text{com}_{VC,0} $ and  $ \text{com}_{VC,1} $ contained in  $ \text{com}_{0} $ and  $ \text{com}_{1} $ are the same. One can observe that in this case, A can never win, i.e.,

 $$ \Pr\left[\mathbf{G}_{2}\Rightarrow1\right]=0. $$

### H Omitted Details from Section 8

Proof of Lemma 16. Let $\mathcal{A}$ be an adversary against position-binding of $\mathsf{CC}^{\otimes}$. We give a reduction $\mathcal{B}$ that runs $\mathcal{A}$ internally, and breaks position-binding of $\mathsf{CC}_c$ if $\mathcal{A}$ breaks position-binding of $\mathsf{CC}^{\otimes}$. Namely, $\mathcal{B}$ gets as input a commitment key $\mathsf{ck}$ and runs $\mathcal{A}$ on input $\mathsf{ck}$. Then, $\mathcal{A}$ terminates with output $(\mathsf{com}, j, \hat{m}, \tau, \hat{m}', \tau')$. Finally, $\mathcal{B}$ writes $\mathsf{com} = (\mathsf{com}_1, \ldots, \mathsf{com}_{n_r}),$ sets $(i^*, j^*) := \mathsf{ToMatldx}(j)$, and outputs

(comₙ*, i*, ℱ̂, τ, ℱ̂'ₙ', τ'). Clearly, ℱ perfectly simulates the position-binding game for ℱ, and its running time is dominated by the running time of ℱ. Assuming that ℱ breaks position-binding, we know that ℱ̂ ≠ ℱ̂' and by definition of Ver⊗, we have Ver⊗(ck, comₙ*, i*, ℱ̂, τ) = 1 and Ver⊗(ck, comₙ*, i*, ℱ̂'ₙ', τ') = 1. This means that ℱ breaks position-binding of CCₙ.

Proof of Lemma 17. We prove computational uniqueness by showing a simpler yet stronger statement. Namely, let $\mathcal{A}$ be a PPT algorithm. Assume that $\mathcal{A}$ gets as input a commitment key $\mathsf{ck} \leftarrow \mathsf{Setup}_c(1^\lambda)$ and outputs a commitment $\mathsf{com} = (\mathsf{com}_1, \ldots, \mathsf{com}_{n_r})$, and some openings. We denote these openings by $\mathbf{X}_{i,j} \in \mathbb{F}$, $\tau_{i,j}$ for $(i,j) \in I \subseteq [n_c] \times [n_r]$, where $I$ denotes the set of indices for which $\mathcal{A}$ opens the commitment. Further, assume the following three conditions hold:

• The size of $I$ is at least the reception efficiency $t$ of $\mathcal{C}_r \otimes \mathcal{C}_c$.

- The reconstruction algorithm of  $ C_r \otimes C_c $ does not output  $ \perp $. The output is  $ \mathbf{m} \in \mathbb{F}^{k_c k_r} $, which defines a matrix  $ \mathbf{M} \in \mathbb{F}^{k_c \times k_r} $.

• All openings  $ \mathbf{X}_{i,j} \in \mathbb{F}, \tau_{i,j} $ are valid according to  $ \mathrm{Ver}^{\otimes} $.

In this case, we have (except with some negligible probability $\delta$) that for all $j \in [n_r]$ we have $\widehat{\mathbf{Com}}_c(\mathbf{ck}, (\mathbf{MG}_r^\top)_j) = \mathbf{com}_j$, where $(\mathbf{MG}_r^\top)_j$ denotes the $j$th column of $\mathbf{MG}_r$. It can easily be observed that this statement implies computational uniqueness and the advantage against computational uniqueness is bounded by $2\delta$. The rest of the proof is dedicated to showing this statement. We do so by providing a sequence of games.

 $ \underline{\text{Game G}_0 $: We start with G_0, which models the setting above. Namely, in game G_0, the game first samples ck ← Setup_c(1^\lambda). Then, it runs A on input ck. As a result A outputs a commitment com = (com_1, ..., com_n_r) and openings X_{i,j} ∈ F, \tau_{i,j} for (i, j) ∈ I ⊆ [n_c] × [n_r] as above. The game outputs 1 if the three conditions from above hold, but there is a j ∈ [n_r] such that  $ \widehat{\text{Com}_c}(\text{ck}, (\mathbf{MG}_r^\top)_j) ≠ \text{com}_j $. Our goal is to upper bound

 $$ \delta:=\operatorname*{P r}\left[\mathbf{G}_{0}\Rightarrow1\right]. $$

Before we continue with the next game, we introduce the set  $ I^* \subseteq [n_r] $, which is defined as

 $$ I^{*}:=\{j\in[n_{r}]\mid\exists i\in[n_{r}]:(i,j)\in I\}. $$

Intuitively,  $ I^* $ corresponds the set of columns in which the adversary opened any index. It is easy to see that  $ I^* $ contains at least  $ k_r $ elements if  $ \mathbf{G}_0 $ outputs 1.

Game $\mathbf{G}_1$: This game is as $\mathbf{G}_0$, but we additionally run the extractor $\text{Ext}$ of the commitment scheme $\overline{\text{CC}}_c$ a few times. Precisely, after obtaining the output from $\mathcal{A}$, the game does the following for each $j \in I^*$: It first tries to extract a preimage of the commitment $\text{com}_j$ via $\mathbf{Y}_j \leftarrow \text{Ext}(\text{ck}, \text{com}_j, i, \mathbf{X}_{i,j}, \tau_{i,j})$, where $i \in [n_r]$ is the first index such that $(i,j) \in I$. Here, we have $\mathbf{Y}_j \in \mathbb{F}^{k_c}$. Then, the game outputs 0 and terminates if for $(\text{com}, St) = \text{Com}_c(\text{ck}, \mathbf{Y}_j)$ we have $\text{com} \neq \text{com}_j$. Finally, if the game did not yet terminate after having done this for all $j \in I^*$, it returns whatever $\mathbf{G}_0$ would return. Clearly, games $\mathbf{G}_0$ and $\mathbf{G}_1$ only differ in extraction fails, i.e., $\mathcal{A}$ manages to output an opening $\mathbf{X}_{i,j}, \tau_{i,j}$ as above which verifies with respect to commitment $\text{com}_j$, but for which $\text{Ext}$ does not output a correct preimage $\mathbf{Y}_j$. A straight-forward reduction $\mathcal{B}$ against extractability of $\text{CC}_c$ shows

 $$ \left|\mathrm{P r}\left[\mathbf{G}_{0}\Rightarrow1\right]-\mathrm{P r}\left[\mathbf{G}_{1}\Rightarrow1\right]\right|\leq\mathrm{A d v}_{\mathcal{B},\mathrm{E x t},\mathsf{C C}_{c}}^{\mathrm{e x t r}}(\lambda). $$

 $ \underline{\text{Game G}_2 $: This game is as G}_1 $, but we introduce a bad event and let the game abort if it occurs. To define the bad event, we first recall that during verification of  $ \mathcal{A} $'s output, vectors  $ \mathbf{a} \in \mathbb{F}^{n_r - k_r} $ are sampled uniformly, and the equation  $ \widehat{\text{Com}}_c(\mathbf{c}\mathbf{k}, \mathbf{0}) \neq \sum_{i=1}^{n_r} \mathbf{h}_j \cdot \text{com}_j $ is checked, where  $ \mathbf{h} = \mathbf{H}^\top \mathbf{a} $. Written differently, it is checked that  $ \widehat{\text{Com}}_c(\mathbf{c}\mathbf{k}, \mathbf{0}) = \text{com} \mathbf{H}^\top \mathbf{a} $.

- Event LinCol: This event occurs, if  $ \widehat{\text{Com}_c}(\text{ck}, \mathbf{0}) = \text{com} \mathbf{H}^\top \mathbf{a} $, but there is a column of com  $ \mathbf{H}^\top $ which is not equal to  $ \widehat{\text{Com}_c}(\text{ck}, \mathbf{0}) $, where  $ \mathbf{a} \in \mathbb{F}^{n_r - k_r} $ is sampled uniformly during verification (see algorithm  $ \text{Ver}^\otimes $).

We can easily bound the probability of LinCol. For that, observe that if a column of com  $ \mathbf{H}^\top $ is not equal to  $ \widehat{\text{Com}_c}(\text{ck}, \mathbf{0}) $, then the map  $ \mathbf{a} \mapsto \text{com} \mathbf{H}^\top \mathbf{a} $ is a non-zero homomorphism from  $ \mathbb{F}^{n_r - k_r} $ to the commitment space. As  $ \mathbf{a} $ is sampled uniformly and independent of everything else, the probability that it ends up being in the kernel of this map is at most  $ 1/|\mathbf{F}| $. We have

 $$ \left|\mathrm{Pr}\left[\mathbf{G}_{1}\Rightarrow1\right]-\mathrm{Pr}\left[\mathbf{G}_{2}\Rightarrow1\right]\right|\leq\mathrm{Pr}\left[\mathrm{LinCol}\right]\leq\frac{1}{\left|\mathbb{F}\right|}. $$

Next, we introduce some notation. Namely, we define the set  $ \mathcal{H} \subseteq [n_r] $ to be the first  $ k_r $ indices in  $ I^* $. Further, we define the set  $ \mathcal{W} := [n_r] \setminus \mathcal{H} $ of the remaining indices. Having defined the sets  $ \mathcal{H} $ and  $ \mathcal{W} $, we now define certain matrices and vectors:

- Consider the parity-check matrix  $ \mathbf{H} \in \mathbb{F}^{(n_r - k_r) \times n_r} $ of  $ \mathcal{C}_r $. We split  $ \mathbf{H} $ into two matrices  $ \mathbf{H}_H \in \mathbb{F}^{(n_r - k_r) \times k_r} $ and  $ \mathbf{H}_W \in \mathbb{F}^{(n_r - k_r) \times (n_r - k_r)} $. This is done in the following way: The matrix  $ \mathbf{H}_H $ contains all columns with indices in  $ \mathcal{H} $, and the matrix  $ \mathbf{H}_W $ contains all columns with indices in  $ \mathcal{W} $. Both are ordered in the canonical way. Observe that because of our assumption that  $ \mathcal{C}_r $ is an MDS code, we know that  $ \mathbf{H}_W $ and  $ \mathbf{H}_W^\top $ are invertible.

• We partition the commitments  $ \text{com}_j, j \in [n_r] $ in the same way into  $ \text{com}_\mathcal{H} = (\text{com}_j)_{j \in \mathcal{H}} $ and  $ \text{com}_\mathcal{W} = (\text{com}_j)_{j \in \mathcal{W}} $.

- Recall from $\mathbf{G}_1$ that the game extracts vectors $\mathbf{Y}_j \in \mathbb{F}^{k_c}$ for every $j \in I^*$. In particular, it extracts $\mathbf{Y}_j$ for every $j \in \mathcal{H} \subseteq I^*$. We arrange these $\mathbf{Y}_j$ for $j \in \mathcal{H}$ into a matrix $\mathbf{Y}_{\mathcal{H}} \in \mathbb{F}^{k_c \times k_r}$. Further, we define the matrix

 $$ \mathbf{Y}_{\mathcal{W}}:=-\mathbf{Y}_{\mathcal{H}}\mathbf{H}_{\mathcal{H}}^{\top}\left(\mathbf{H}_{\mathcal{W}}^{\top}\right)^{-1}. $$

Also, we define the matrix  $ \mathbf{Y} \in \mathbb{F}^{k_c \times n_r} $ by merging  $ \mathbf{Y}_\mathcal{H} $ and  $ \mathbf{Y}_\mathcal{W} $ in the natural way, i.e., the columns in  $ \mathcal{H} $ of  $ \mathbf{Y} $ are filled by  $ \mathbf{Y}_\mathcal{H} $ and the columns in  $ \mathcal{W} $ are filled by  $ \mathbf{Y}_\mathcal{W} $, both by respecting the natural order.

• We encode the matrix Y that we just defined using the code  $ C_c $. That is, we define a matrix  $ \hat{X} := G_c Y \in \mathbb{F}^{n_c \times n_r} $.

The intuition is as follows: The matrix  $ \mathbf{Y}_{\mathcal{W}} $ completes the extracted  $ \mathbf{Y}_{\mathcal{H}} $ into a matrix with rows in the code. The matrix is consistent with the commitments and openings output by A, as we will show. We continue by making this intuition formal in the following claims.

Claim 1. Consider the notations and assumptions from the proof of Lemma 17. Every row of Y and every row of  $ \hat{X} $ is in the code  $ C_r $.

We prove Claim 1. To do so, it is sufficient to show that  $ \mathbf{Y}\mathbf{H}^{\top}=\mathbf{0} $. Observe that

 $$ \begin{aligned}\mathbf{Y}\mathbf{H}^{\top}&=\mathbf{Y}_{\mathcal{H}}\mathbf{H}_{\mathcal{H}}^{\top}+\mathbf{Y}_{\mathcal{W}}\mathbf{H}_{\mathcal{W}}^{\top}\\&=\mathbf{Y}_{\mathcal{H}}\mathbf{H}_{\mathcal{H}}^{\top}-\mathbf{Y}_{\mathcal{H}}\mathbf{H}_{\mathcal{H}}^{\top}\left(\mathbf{H}_{\mathcal{W}}^{\top}\right)^{-1}\mathbf{H}_{\mathcal{W}}^{\top}\\&=\mathbf{Y}_{\mathcal{H}}\mathbf{H}_{\mathcal{H}}^{\top}-\mathbf{Y}_{\mathcal{H}}\mathbf{H}_{\mathcal{H}}^{\top}=\mathbf{0}.\\ \end{aligned} $$

Claim 2. Consider the notations and assumptions from the proof of Lemma 17. Let  $ j \in [n_r] $ be arbitrary. Then for the  $ j $th column  $ \mathbf{Y}_j $ of  $ \mathbf{Y} $, we have that  $ \widehat{\text{Com}}_c(\text{ck}, \mathbf{Y}_j) = \text{com}_j $.

To prove Claim 2, we first observe that by  $ \mathbf{G}_1 $ and the definition of  $ \mathbf{Y}_{\mathcal{H}} $, the claim holds for all  $ j \in \mathcal{H} $. Thus, it remains to prove the claim for all  $ j \in \mathcal{W} $. For that, we first recall from  $ \mathbf{G}_2 $, that every column of  $ \text{com} \mathbf{H}^\top $ is equal to  $ \widehat{\text{Com}_c}(\text{ck}, \mathbf{0}) $. Using the homomorphic properties of  $ \widehat{\text{Com}_c}(\text{ck}, \cdot) $, this implies that

 $$ \mathsf{c o m}_{\mathcal{W}}\;\mathbf{H}_{\mathcal{W}}^{\top}=-\mathsf{c o m}_{\mathcal{H}}\;\mathbf{H}_{\mathcal{H}}^{\top}. $$

Now, multiplying both sides with  $ (H_{W}^{\top})^{-1} $, we have

 $$ \mathsf{c o m}_{\mathcal{W}}=-\mathsf{c o m}_{\mathcal{H}}\mathbf{H}_{\mathcal{H}}^{\top}\left(\mathbf{H}_{\mathcal{W}}^{\top}\right)^{-1}. $$

If we now look at one specific column  $ j \in \mathcal{W} $ of this equation, we have

 $$ \begin{align*}\mathrm{com}_{j}&=-\mathrm{com}_{\mathcal{H}}\mathbf{H}_{\mathcal{H}}^{\top}\left(\mathbf{H}_{\mathcal{W}}^{\top}\right)_{j}^{-1}\\&=\widehat{\mathrm{Com}}_{c}(\mathrm{ck},\mathbf{Y}_{\mathcal{H}}\mathbf{H}_{\mathcal{H}}^{\top}\left(\mathbf{H}_{\mathcal{W}}^{\top}\right)_{j}^{-1})=\widehat{\mathrm{Com}}_{c}(\mathrm{ck},\mathbf{Y}_{j}),\end{align*} $$

as desired.

Claim 3. Consider the notations and assumptions from the proof of Lemma 17. Let  $ (i,j) \in I $ be arbitrary. Then, we have  $ \mathbf{X}_{i,j} = \hat{\mathbf{X}}_{i,j} $, except with probability  $ \text{Adv}_{\mathcal{B}^{\prime}, \mathcal{C} \mathcal{C}_{c}}^{\text{pos-bind}}(\lambda) $, for a reduction  $ \mathcal{B}^{\prime} $ with  $ \mathbf{T}(\mathcal{B}^{\prime}) \approx \mathbf{T}(\mathcal{A}) $.

To see that Claim 3 holds, observe that a reduction simulating  $ \mathbf{G}_2 $ knows a preimage  $ \mathbf{Y}_j $ for all commitments  $ \text{com}_j $ output by the adversary (cf. Claim 2). Thus, in case  $ \mathbf{X}_{i,j} \neq \hat{\mathbf{X}}_{i,j} $ holds for some  $ (i,j) \in I $, a reduction can output  $ \text{com}_j $, the opening  $ \mathbf{X}_{i,j}, \tau_{i,j} $, and an opening for  $ \hat{\mathbf{X}}_{i,j} $ to break position-binding of  $ \text{CC}_c $. The reduction can compute the latter opening as it knows  $ \mathbf{Y}_j $.

Finally, we show how to use the three claims to argue that (except with the probability bounded by reduction  $ \mathcal{B}' $ in Claim 3)  $ \mathbf{G}_2 $ does not output 1. This is done as follows. From Claim 1, we know that  $ \hat{\mathbf{X}} = \mathbf{G}_c \tilde{\mathbf{M}} \mathbf{G}_r^\top $ for some  $ \tilde{\mathbf{M}} \in \mathbb{F}^{k_c \times n_r} $. As  $ |I| \geq t $, we thus know that  $ \tilde{\mathbf{M}} $ is defined by the output by the reconstruction algorithm on input  $ (\tilde{\mathbf{X}}_{i,j})_{(i,j) \in I} $. As  $ \mathbf{X}_{i,j} = \tilde{\mathbf{X}}_{i,j} $ for all  $ (i,j) \in I $, we know that this input is the same as  $ (\mathbf{X}_{i,j})_{(i,j) \in I} $. An initial assumption (see  $ \mathbf{G}_0 $) was that reconstructing from  $ (\mathbf{X}_{i,j})_{(i,j) \in I} $ yields  $ \mathbf{M} $. Therefore, we have  $ \tilde{\mathbf{M}} = \mathbf{M} $. Thus, we showed that  $ \mathbf{G}_c \mathbf{Y} = \tilde{\mathbf{X}} = \mathbf{G}_c \mathbf{M} \mathbf{G}_r^\top $. As  $ \mathbf{G}_c $ induces an injective mapping, we have  $ \mathbf{Y} = \mathbf{M} \mathbf{G}_r^\top $. Thus, by Claim 2, we have that the  $ j $th column of  $ \mathbf{M} \mathbf{G}_r^\top $ commits to  $ \complement_j $ for all  $ j \in [n_r] $, which is what we wanted to show. In summary, we showed that

 $$ \delta\leq\mathsf{A d v}_{\mathcal{B},\mathsf{E x t},\mathsf{C C}_{c}}^{\mathsf{e x t r}}(\lambda)+\mathsf{A d v}_{\mathcal{B}^{\prime},\mathsf{C C}_{c}}^{\mathsf{p o s-b i n d}}(\lambda)+\frac{1}{|\mathbb{F}|}. $$

Proof of Lemma 18. We want to prove that $\mathbb{CC}^\otimes$ is code-binding. For that, we consider two cases. Namely, either the adversary outputs openings such that in at least one column the openings are not consistent with any codeword, or it does the same for at least one row. Formally, consider the code-binding game of $\mathbb{CC}^\otimes$. In this game, first a key $\mathbf{ck} \leftarrow \mathsf{Setup}_c(1^\lambda)$ is generated. Then, the adversary $\mathcal{A}$ gets this key and outputs a commitment $\text{com} = (\text{com}_1, \ldots, \text{com}_{n_r})$, and some openings. We denote these openings by $\mathbf{X}_{i,j} \in \mathbb{F}, \tau_{i,j}$ for $(i,j) \in I \subseteq [n_c] \times [n_r]$, where $I$ denotes the set of indices for which $\mathcal{A}$ opens the commitment. In terms of notation, we define $I_r(i)$ to be the set of indices in row $i$ that are contained in $I$, and $I_c(j)$ to be the set of indices in column $j$ that are contained in $I$. More formally, we set

 $$ I_{r}(i):=\{j\in[n_{r}]\mid(i,j)\in I\},I_{c}(j):=\{i\in[n_{c}]\mid(i,j)\in I\}, $$

for each  $ i \in [n_c] $ and each  $ j \in [n_r] $ The adversary  $ \mathcal{A} $ breaks code-binding, if all openings verify, and there is no codeword that is consistent with these openings. Now, we define two events.

- Event BreakCol: This event occurs, if all openings verify, and there is a column  $ j \in [n_r] $, such that no codeword of code  $ C_c $ is consistent with the openings  $ \mathbf{X}_{i,j} $ for  $ i \in I_c(j) $.

- Event BreakRow: This event occurs, if all openings verify, and there is a row  $ i \in [n_c] $, such that no codeword of code  $ C_r $ is consistent with the openings  $ X_{i,j} $ for  $ j \in I_r(i) $.

If A breaks code-binding, at least one of these two events must occur. Therefore, we have

 $$ \operatorname{A d v}_{\mathcal{A},\mathcal{C C}^{\otimes}}^{\operatorname{c o d e-b i n d}}(\lambda)\leq\operatorname*{P r}\left[\operatorname{B r e a k C o l}\right]+\operatorname*{P r}\left[\operatorname{B r e a k R o w}\wedge\neg\operatorname{B r e a k C o l}\right]. $$

Note that each column  $ j \in [n_r] $ is associated to a commitment  $ \text{com}_j $ output by the adversary. Thus, if event  $ \text{BreakCol} $ occurs, a reduction  $ \mathcal{B} $ can break code-binding of  $ \text{CC}_c $. The reduction is trivial and we omit it here. We have

 $$ \operatorname{P r}\left[\operatorname{B r a k C o l}\right]\leq\operatorname{A d v}_{\mathcal{B},\mathcal{C C}_{c}}^{\operatorname{c o d e-b i n d}}(\lambda). $$

For the rest of the proof, we focus on bounding the probability of event BreakRow ∧ →BreakCol. That is, we need to argue that the adversary can not output openings of a row such that no codeword (in the

code  $ C_{r} $) is consistent with the openings. We prove this via a sequence of games. This is almost identical to the proof of Lemma 17, and we encourage the reader to read the proof of Lemma 17 first.

Game G₀: Game G₀ is exactly the code-binding game as above, with the modification that it outputs 1 if and only if event BreakRow ∧ →BreakCol occurs. If it occurs, let i* ∈ [nₑ] be the first row that triggers event BreakRow. That is, let i* be the first row for which no codeword of Cₙ is consistent with the openings X₊₊₊ for j ∈ Iₙ(i*). By definition, we have

 $$ \Pr\left[BreakRow\land\neg BreakCol\right]=\Pr\left[\mathbf{G}_{0}\Rightarrow1\right]. $$

The rest of the proof will not use the openings other than  $ X_{i^{*},j} $

 $ \underline{\text{Game G}_1 $: Game G $ _1 $ is as G $ _0 $. In addition, G $ _1 $ runs the extractor Ext of the column commitment scheme CC $ _c $ a few times. Namely, when obtaining the output from  $ \mathcal{A} $, the game does the following for each  $ j \in I_r(i^*) $: It first runs  $ \mathbf{Y}_j \leftarrow \text{Ext}(\text{ck}, \text{com}_j, i^*, \mathbf{X}_{i^*,j}, \tau_{i^*,j}) $ to extract a preimage of  $ \text{com}_j $. We have  $ \mathbf{Y}_j \in \mathbb{F}^{k_c} $. The game outputs 0 and terminates if for  $ (\text{com}, St) = \text{Com}_c(\text{ck}, \mathbf{Y}_j) $ we have  $ \text{com} \neq \text{com}_j $. Finally, if the game did not yet terminate after having done this for all  $ j \in I_r(i^*) $, it continues as  $ \mathbf{G}_0 $ would do. The difference between  $ \mathbf{G}_0 $ and  $ \mathbf{G}_1 $ can easily be bounded using reduction  $ \mathcal{B}' $ against extractability of CC $ _c $. We have

 $$ \left|\mathrm{P r}\left[\mathbf{G}_{0}\Rightarrow1\right]-\mathrm{P r}\left[\mathbf{G}_{1}\Rightarrow1\right]\right|\leq\mathrm{A d v}_{\mathcal{B}^{\prime},\mathrm{E x t},\mathsf{C C}_{c}}^{\mathrm{e x t r}}(\lambda). $$

 $ \underline{\text{Game G2:}} $ This game is as  $ \mathbf{G}_1 $, with an additional bad event on which the game aborts. Namely, recall that during verification of  $ \mathcal{A} $'s output, vectors  $ \mathbf{a} \in \mathbb{F}^{n_r - k_r} $ are sampled uniformly, and the game checks the equation  $ \widehat{\text{Com}_c}(\text{ck}, \mathbf{0}) \neq \sum_{i=1}^{n_r} \mathbf{h}_j \cdot \text{com}_j $, where  $ \mathbf{h} = \mathbf{H}^\top \mathbf{a} $. That is, it is checked that  $ \widehat{\text{Com}_c}(\text{ck}, \mathbf{0}) = \text{com} \mathbf{H}^\top \mathbf{a} $. We define event LinCol exactly as in  $ \mathbf{G}_2 $ of the proof of Lemma 17.

• Event LinCol: This event occurs, if  $ \widehat{\text{Com}_c}(\text{ck}, \mathbf{0}) = \text{com} \mathbf{H}^\top \mathbf{a} $, but there is a column of  $ \text{com} \mathbf{H}^\top $ which is not equal to  $ \widehat{\text{Com}_c}(\text{ck}, \mathbf{0}) $, where  $ \mathbf{a} \in \mathbb{F}^{n_r - k_r} $ is sampled uniformly during verification (see algorithm  $ \text{Ver}^\otimes $).

The probability of LinCol is at most 1/|F|, which can be seen as in the proof of Lemma 17. We have

 $$ \left|\mathrm{Pr}\left[\mathbf{G}_{1}\Rightarrow1\right]-\mathrm{Pr}\left[\mathbf{G}_{2}\Rightarrow1\right]\right|\leq\mathrm{Pr}\left[\mathrm{LinCol}\right]\leq\frac{1}{\left|\mathbb{F}\right|}. $$

Next, we introduce some notation, which is similar to the notation in the proof of Lemma 17. The set  $ \mathcal{H} \subseteq [n_r] $ is defined to be the first  $ k_r $ indices in  $ I_r(i^*) $. The set  $ \mathcal{W} $ is defined as  $ \mathcal{W} := [n_r] \setminus \mathcal{H} $. Recall that if the game outputs 1, the adversary output openings for all indices  $ j \in \mathcal{H} $ in row  $ i^* $. Additionally, it may have output openings for some indices in  $ \mathcal{W} $. We will later see that there is at least one index in  $ \mathcal{W} $ for which the adversary provided an opening. We now define certain matrices and vectors as in the proof of Lemma 17:

- Let $\mathbf{H} \in \mathbb{F}^{(n_r - k_r) \times n_r}$ be the parity-check matrix of $\mathcal{C}_r$. We split $\mathbf{H}$ into two matrices $\mathbf{H}_\mathcal{H} \in \mathbb{F}^{(n_r - k_r) \times k_r}$ and $\mathbf{H}_\mathcal{W} \in \mathbb{F}^{(n_r - k_r) \times (n_r - k_r)}$). This is done as follows: The matrix $\mathbf{H}_\mathcal{H}$ contains all columns with indices in $\mathcal{H}$, and the matrix $\mathbf{H}_\mathcal{W}$ contains all columns with indices in $\mathcal{W}$. Both are ordered in the canonical way. As $\mathcal{C}_r$ is an MDS code, we know that $\mathbf{H}_\mathcal{W}$ and $\mathbf{H}_\mathcal{W}^\top$ are invertible.

• We partition the commitments  $ \text{com}_j $,  $ j \in [n_r] $ in the same way into  $ \text{com}_\mathcal{H} = (\text{com}_j)_{j \in \mathcal{H}} $ and  $ \text{com}_\mathcal{W} = (\text{com}_j)_{j \in \mathcal{W}} $.

- Recall that the game extracts vectors  $ \mathbf{Y}_j \in \mathbb{F}^{k_c} $ for every  $ j \in I_r(i^*) $ (see  $ \mathbf{G}_1 $). Especially, it extracts  $ \mathbf{Y}_j $ for every  $ j \in \mathcal{H} \subseteq I_r(i^*) $. We arrange these  $ \mathbf{Y}_j $ for  $ j \in \mathcal{H} $ into a matrix  $ \mathbf{Y}_{\mathcal{H}} \in \mathbb{F}^{k_c \times k_r} $. We define

 $$ \mathbf{Y}_{\mathcal{W}}:=-\mathbf{Y}_{\mathcal{H}}\mathbf{H}_{\mathcal{H}}^{\top}\left(\mathbf{H}_{\mathcal{W}}^{\top}\right)^{-1}. $$

We define the matrix  $ \mathbf{Y} \in \mathbb{F}^{k_c \times n_r} $ by merging  $ \mathbf{Y}_\mathcal{H} $ and  $ \mathbf{Y}_\mathcal{W} $ in the natural way, i.e., the columns in  $ \mathcal{H} $ of  $ \mathbf{Y} $ are filled by  $ \mathbf{Y}_\mathcal{H} $ and the columns in  $ \mathcal{W} $ are filled by  $ \mathbf{Y}_\mathcal{W} $, both by respecting the natural order.

• We define a matrix  $ \hat{\mathbf{X}} := \mathbf{G}_c \mathbf{Y} \in \mathbb{F}^{n_c \times n_r} $.

The intuition is as follows: The matrix  $ \mathbf{Y}_{\mathcal{W}} $ completes the extracted  $ \mathbf{Y}_{\mathcal{H}} $ into a matrix with rows in the code, which is consistent with the commitments output by  $ \mathcal{A} $. As we assume that  $ \mathcal{A} $ breaks code-binding, we know that this completed matrix has to be different from the output of  $ \mathcal{A} $, which will allow us to break binding of  $ \mathbf{C}\mathbf{C}_{c} $. To make this intuition formal, we will show three claims.

Claim 4. Consider the notations and assumptions from the proof of Lemma 18. Every row of Y and every row of  $ \hat{X} $ is in the code  $ C_r $.

The proof of Claim 4 is identical to the proof of Claim 1.

Claim 5. Consider the notations and assumptions from the proof of Lemma 18. Let  $ j \in [n_r] $ be arbitrary. Then for the  $ j $th column  $ \mathbf{Y}_j $ of  $ \mathbf{Y} $, we have that  $ \widehat{\text{Com}}_c(\text{ck}, \mathbf{Y}_j) = \text{com}_j $.

The proof of Claim 5 is identical to the proof of Claim 2.

Claim 6. Consider the notations and assumptions from the proof of Lemma 18. There is at least one  $ j^* \in \mathcal{W} $ such that  $ \mathcal{A} $ output an opening of index  $ (i^*, j^*) $, i.e.,  $ j^* \in I_r(i^*) $, and for this  $ j^* $, the opening  $ \mathbf{X}_{i^*,j^*} \in \mathbb{F} $ output by  $ \mathcal{A} $ is different from the element  $ \hat{\mathbf{X}}_{i^*,j^*} $.

To prove Claim 6, observe that if no $j^* \in \mathcal{W}$ is opened or all openings in $\mathcal{W}$ are consistent with $\hat{\mathbf{X}}$, then the opened indices in row $i^*$ are consistent with the $i^*$th row of $\hat{\mathbf{X}}$. However, by Claim 4, the $i^*$th row of $\hat{\mathbf{X}}$ is in $\mathcal{C}_r$. This contradicts the definition of $i^*$.

Now that we made these observations, we can bound the probability that $\mathbf{G}_2$ outputs 1 using a reduction $\mathcal{B}$' that breaks position-binding of $\mathrm{CC}_c$. The reduction can be summarized as follows: It gets as input the commitment key $\mathbf{c}$ and forwards it to $\mathcal{A}$. Once $\mathcal{A}$ outputs a commitment $\mathrm{com} = (\mathrm{com}_1, \ldots, \mathrm{com}_{n_c})$ and openings, $\mathcal{B}$' does all the steps as in $\mathbf{G}_2$. If $\mathbf{G}_2$ outputs 1, $\mathcal{B}$' knows the row $i^*$. It computes the matrix $\mathbf{Y}$ as defined above. Then, $\mathcal{B}$' finds the index $j^*$ as in Claim 6. Now, note that $\mathcal{B}$' can break position-binding of $\mathrm{CC}_c$ by outputting $\mathrm{com}_{j^*}$, the opening that $\mathcal{A}$ output, and an opening for $\hat{\mathbf{X}}_i^*_{,j^*}$. Note that $\mathcal{B}$' can compute this opening, because it knows the commitment preimage $\mathbf{Y}_j^*$ of $\mathrm{com}_j^*$ (see Claim 5). We have

 $$ \operatorname{P r}\left[\mathbf{G}_{2}\Rightarrow1\right]\leq\mathsf{A d v}_{\mathcal{B}^{\prime\prime},\mathsf{C C}_{c}}^{\mathsf{p o s-b i n d}}(\lambda). $$

□

#### I Omitted Details from Section 9

#### I.1 Omitted Details from Section 9.1

Lemma 32. Let Δ ∈ [n]. Let A be any stateful algorithm, and consider the following experiment G:

1. Run A to obtain  $ \mathbf{X} \in \mathbb{F}^{k \times n} $. Let  $ \mathbf{X}_j \in \mathbb{F}^k $ for  $ j \in [n] $ be the jth column of  $ \mathbf{X} $.

2. Sample a matrix  $ \mathbf{R} \leftarrow s \mathbb{F}^P \times k $.

3. Run A on input  $ \mathbf{R} $, and get a matrix  $ \mathbf{W} \in \mathbb{F}^{P \times n} $ from  $ \mathcal{A} $. Let  $ \mathbf{W}_j \in \mathbb{F}^P $ be the  $ j $th column of  $ \mathbf{W} $, for each  $ j \in [n] $.

4. Sample J ↔ s ( [n] ) and set Win := 0. If the following three conditions hold, set Win := 1:

(a) For each row  $ \mathbf{w}^\top \in \mathbb{F}^{1 \times n} $ of  $ \mathbf{W} $, we have  $ \mathbf{w} \in \mathcal{C} $.

(b) For all  $ j \in J $, we have  $ \mathbf{W}_j = \mathbf{R}\mathbf{X}_j $.

(c) We have d_{col}  $ \mathcal{C}^{\equiv k} $,  $ \mathbf{X} $ >  $ \Delta $.

Then, for any A and any Δ as above that satisfies Δ < d* / 4, we have

 $$ \Pr_{\mathcal{G}}\left[\mathrm{W i n}=1\right]\leq\left(\frac{\Delta+1}{\left|\mathbb{F}\right|}\right)^{P}+\left(1-\frac{\Delta+1}{n}\right)^{L}. $$

Proof. The proof follows the arguments in [AHIV22], Theorem B.1. Consider game G specified in the lemma, and let the variables X, R, W be as in the game. We define the following event in game G:

- Event CloseRX: This event occurs, if there is a  $ Y \in \mathcal{C}^{\equiv P} $ such that  $ d_{col}(Y, \mathbf{R}X) \leq \Delta $.

Note that CloseRX implies that for each row  $ \mathbf{y}^\top $ of  $ \mathbf{Y} $ and the corresponding row  $ \mathbf{r}^\top\mathbf{X} $ of  $ \mathbf{R}\mathbf{X} $, we have  $ d\left(\mathbf{y}^\top,\mathbf{r}^\top\mathbf{X}\right)\leq\Delta $. Now, we can apply Lemma 4.2 in [AHIV22] to each column and get

 $$ \Pr_{\mathcal{G}}\left[\mathrm{W i n}=1\wedge\mathrm{C l o s e R X}\right]\leq\left(\frac{\Delta+1}{\left|\mathbb{F}\right|}\right)^{P}. $$

Further, we can write

 $$ \Pr_{\mathcal{G}}\left[\mathrm{W i n}=1\right]\leq\Pr_{\mathcal{G}}\left[\mathrm{W i n}=1\land\neg\mathrm{C l o s e R X}\right]+\Pr_{\mathcal{G}}\left[\mathrm{W i n}=1\land\mathrm{C l o s e R X}\right]. $$

Thus, it remains to bound the probability that CloseRX does not occur and Win = 1. If CloseRX does not occur and Win = 1, we know that  $ \mathbf{W} \in \mathcal{C}^{\equiv P} $, and for each  $ \mathbf{Y} \in \mathcal{C}^{\equiv P} $ we have  $ d_{col}(\mathbf{Y}, \mathbf{R}\mathbf{X}) > \Delta $. Thus, we have  $ d_{col}(\mathbf{W}, \mathbf{R}\mathbf{X}) > \Delta $, meaning that there are at most  $ n - \Delta - 1 $ columns on which  $ \mathbf{W} $ and  $ \mathbf{R}\mathbf{X} $ agree. Denote the set of these columns by  $ J^* \subseteq [n], |J^*| \leq n - \Delta - 1 $. The probability that CloseRX does not occur and Win = 1 can now be bounded by the probability that  $ J \subseteq J^* $, which is at most

 $$ \frac{\binom{|J^{*}|}{L}}{\binom{n}{L}}\leq\frac{\binom{n-\Delta-1}{L}}{\binom{n}{L}}\leq\left(1-\frac{\Delta+1}{n}\right)^{L}, $$

where we used Lemma 24.

Lemma 33. Let Δ ∈ [n]. Let A be any stateful algorithm, and consider the following experiment G:

1. Run $\mathcal{A}$ to obtain matrices $\mathbf{X} \in \mathbb{F}^{k \times n}$, $\mathbf{W} \in \mathbb{F}^{P \times n}$, and $\mathbf{R} \in \mathbb{F}^{P \times k}$. Let $\mathbf{X}_j \in \mathbb{F}^k$ ($resp$. $\mathbf{W}_j \in \mathbb{F}^P$) for $j \in [n]$ be the $j$th column of $\mathbf{X}$ ($resp$. $\mathbf{W}$).

2. Sample J ↔ s ( [n] ) and set Win := 0. If the following two conditions hold, set Win := 1:

(a) For all  $ j \in J $, we have  $ \mathbf{W}_j = \mathbf{R}\mathbf{X}_j $.

(b) We have  $ d_{col}(\mathbf{R}\mathbf{X},\mathbf{W}) > \Delta $.

Then, for any A and any  $ \Delta $ as above, we have

 $$ \Pr_{\mathcal{G}}\left[\mathrm{W i n}=1\right]\leq\left(1-\frac{\Delta}{n}\right)^{L}. $$

Proof. Consider an algorithm $\mathcal{A}$ running in the game specified by the lemma. Clearly, if $n - \Delta < L$, the probability that $\mathrm{Win} = 1$ is zero. So, assume that $L \leq n - \Delta$, and let $J^*$ be the set of columns $j \in [n]$ in which $\mathbf{RX}$ and $\mathbf{W}$ differ. Note that $J^*$ is fixed before $J$ is sampled. If the second winning condition holds, we know that $|J^*| > \Delta$. If the first winning condition holds, we know that $J \subseteq [n] \setminus J^*$. As $J$ is sampled uniformly at random from the size $L$ subsets of $[n]$, we have can upper bound the probability of $J \subseteq [n] \setminus J$ by

 $$ \frac{\binom{n-|J^{*}|}{L}}{\binom{n}{L}}\leq\frac{\binom{n-\Delta}{L}}{\binom{n}{L}}\leq\left(1-\frac{\Delta}{n}\right)^{L}, $$

where we used Lemma 24.

Lemma 34. Let Δ1, Δ2 ∈ [n]. Let A be any stateful algorithm, and consider the following experiment G:

1. Run A to obtain  $ \mathbf{X} \in \mathbb{F}^{k \times n} $. Let  $ \mathbf{X}_j \in \mathbb{F}^k $ for  $ j \in [n] $ be the jth column of  $ \mathbf{X} $.

2. Sample a matrix  $ \mathbf{R} \leftarrow s \mathbb{F}^P \times k $.

3. Run $\mathcal{A}$ on input $\mathbf{R}$, and get a matrix $\mathbf{W} \in \mathbb{F}^{P \times n}$ and a set $J \subseteq [n]$ from $\mathcal{A}$. Let $\mathbf{W}_j \in \mathbb{F}^P$ be the $j$th column of $\mathbf{W}$, for each $j \in [n]$.

4. Set Win := 0. If the following four conditions hold, set Win := 1:

(a) There is a  $ \mathbf{X}^* \in \mathcal{C}^{\equiv k} $, such that  $ d_{col}(\mathbf{X}^*, \mathbf{X}) \leq \Delta_1 $.

(b) There is no  $ \mathbf{X}' \in \mathcal{C}^{\equiv k} $, such that for each  $ j \in J $, the jth column of  $ \mathbf{X}' $ is equal to  $ \mathbf{X}_j $.

(c) For each row  $ \mathbf{w}^\top \in \mathbb{F}^{1 \times n} $ of  $ \mathbf{W} $, we have  $ \mathbf{w} \in \mathcal{C} $.

(d) For all  $ j \in J $, we have  $ \mathbf{W}_j = \mathbf{R}\mathbf{X}_j $, and we have  $ d_{col}(\mathbf{R}\mathbf{X}, \mathbf{W}) \leq \Delta_2 $.

Then, for any A and any  $ \Delta_1 $,  $ \Delta_2 $ as above that satisfy  $ \Delta_1 + \Delta_2 < d^* $ and  $ \Delta_1 \leq \lfloor(d^* - 1)/2\rfloor $, we have

 $$ \Pr_{\mathcal{G}}\left[\mathrm{W i n}=1\right]\leq\frac{1}{\left|\mathbb{F}\right|^{P}}. $$

Proof. Let $\mathcal{A}$ be an algorithm in the game specified in the lemma. Consider the event that $\mathcal{A}$ wins, i.e. $\mathrm{Win}=1$. If this event occurs, we note that due to the assumption $\Delta_1 \leq \lfloor(d^* - 1)/2 \rfloor$, we know that $\mathbf{X}^*$ from the first winning condition is uniquely determined by $\mathbf{X}$. Because $\mathbf{X}^* \in \mathcal{C}^{\equiv k}$, the second winning condition implies that there is at least one column $j^* \in J$ such that the $j^*$th column of $\mathbf{X}^*$, denoted $\mathbf{X}_j^*$ is not equal to $\mathbf{X}_{j^*}$. By the fourth winning condition, we have $\mathbf{W}_{j^*} = \mathbf{R}\mathbf{X}_j^*$. Further, we have

 $$ d_{col}\left(\mathbf{R}\mathbf{X}^{*},\mathbf{W}\right)\leq d_{col}\left(\mathbf{R}\mathbf{X}^{*},\mathbf{R}\mathbf{X}\right)+d_{col}\left(\mathbf{R}\mathbf{X},\mathbf{W}\right)\leq\Delta_{1}+\Delta_{2}<d^{*}. $$

Because  $ d_{col}(\mathbf{R}\mathbf{X}^*, \mathbf{W}) < d^* $ and  $ \mathbf{R}\mathbf{X}^* \in \mathcal{C}^{\equiv P} $ and  $ \mathbf{W} \in \mathcal{C}^{\equiv P} $, we have  $ \mathbf{R}\mathbf{X}^* = \mathbf{W} $. Thus, we have

 $$ \mathbf{R}\mathbf{X}_{j^{*}}=\mathbf{W}_{j^{*}}=\mathbf{R}\mathbf{X}_{j^{*}}^{*}. $$

In summary, we showed the probability that  $ \mathrm{Win} = 1 $ can be upper bounded by the probability of  $ \mathbf{R}\mathbf{X}_{j^{*}} = \mathbf{R}\mathbf{X}_{j^{*}}^{*} $, where  $ \mathbf{X}_{j^{*}}, \mathbf{X}_{j^{*}}^{*} $ are fixed arbitrarily such that  $ \mathbf{X}_{j^{*}} \neq \mathbf{X}_{j^{*}}^{*} $, and  $ \mathbf{R} \in \mathbb{F}^{P \times k} $ is sampled uniformly. Each row of  $ \mathbf{R} $ is sampled independently, and thus we have

 $$ \mathrm{P r}_{\mathbf{R}}\left[\mathbf{R}\mathbf{X}_{j^{*}}=\mathbf{R}\mathbf{X}_{j^{*}}^{*}\right]\leq\left(\frac{1}{\left|\mathbb{F}\right|}\right)^{P}. $$

Lemma 35. Let A be any stateful algorithm, and consider the following experiment G:

1. Run A to obtain  $ \mathbf{X} \in \mathbb{F}^{k \times n} $. Let  $ \mathbf{X}_j \in \mathbb{F}^k $ for  $ j \in [n] $ be the jth column of  $ \mathbf{X} $.

2. Sample a matrix  $ \mathbf{R} \leftarrow s \mathbb{F}^{P \times k} $.

3. Run A on input  $ \mathbf{R} $, and get a matrix  $ \mathbf{W} \in \mathbb{F}^{P \times n} $. Let  $ \mathbf{W}_j \in \mathbb{F}^P $ be the  $ j $th column of  $ \mathbf{W} $, for each  $ j \in [n] $.

4. Sample a set  $ J \leftarrow s\left(\begin{matrix}[n]\\ L\end{matrix}\right) $.

5. Run A on input J, and obtain an output  $ J' $ from A.

6. Set Win := 0. If the following four conditions hold, set Win := 1:

(a) There is no  $ \mathbf{X}' \in \mathcal{C}^{\equiv k} $, such that for each  $ j \in J' $, the jth column of  $ \mathbf{X}' $ is equal to  $ \mathbf{X}_j $.

(b) For each row  $ \mathbf{w}^\top \in \mathbb{F}^{1 \times n} $ of  $ \mathbf{W} $, we have  $ \mathbf{w} \in \mathcal{C} $.

) For all  $ j \in J $, we have  $ \mathbf{W}_j = \mathbf{R}\mathbf{X}_j $.

(d) For all  $ j \in J' $, we have  $ \mathbf{W}_j = \mathbf{R}\mathbf{X}_j $.

Then, for any  $ \mathcal{A} $ as above, and any  $ \Delta_1, \Delta_2 \in [n] $ with  $ \Delta_1 + \Delta_2 < d^* $ and  $ \Delta_1 \leq d^* / 4 $, we have

 $$ \Pr_{\mathcal{G}}\left[\mathrm{W i n}=1\right]\leq\left(\frac{\Delta_{1}+1}{\left|\mathbb{F}\right|}\right)^{P}+\left(1-\frac{\Delta_{1}+1}{n}\right)^{L}+\left(1-\frac{\Delta_{2}}{n}\right)^{L}+\frac{1}{\left|\mathbb{F}\right|^{P}}. $$

Proof. We prove the statement via a sequence of games, using Lemmata 32 to 34.

 $ \underline{\text{Game G0:}} $ This game is as game G from the lemma, and it outputs 1 if and only if Win = 1. We have

 $$ \operatorname*{P r}_{\mathcal{G}}\left[\mathsf{W i n}=1\right]=\operatorname*{P r}\left[\mathbf{G}_{0}\Rightarrow1\right]. $$

 $ \underline{\text{Game G}_1 $: In this game, we change the winning condition of the game. Namely, the game additionally checks if  $ d_{col}(\mathcal{C}^{\equiv k}, \mathbf{X}) \leq \Delta_1 $. If  $ d_{col}(\mathcal{C}^{\equiv k}, \mathbf{X}) > \Delta_1 $, the game outputs 0. If all previous winning conditions hold, and  $ d_{col}(\mathcal{C}^{\equiv k}, \mathbf{X}) \leq \Delta_1 $, the game outputs 1. It is clear that games  $ \mathbf{G}_0 $ and  $ \mathbf{G}_1 $ only differ if  $ d_{col}(\mathcal{C}^{\equiv k}, \mathbf{X}) > \Delta_1 $. A simple reduction that runs in the game in Lemma 32 shows that

 $$ \left|\mathrm{P r}\left[\mathbf{G}_{0}\Rightarrow1\right]-\mathrm{P r}\left[\mathbf{G}_{1}\Rightarrow1\right]\right|\leq\left(\frac{\Delta_{1}+1}{\left|\mathbb{F}\right|}\right)^{P}+\left(1-\frac{\Delta_{1}+1}{n}\right)^{L}. $$

 $ \underline{\text{Game G2}} $: In this game, we change the winning condition of the game again. Namely, as an additional check, the game checks if  $ d_{col}(\mathbf{RX}, \mathbf{W}) > \Delta_2 $. If this holds, it outputs 0. Otherwise, it behaves as  $ \mathbf{G}_1 $. We can easily bound the difference between  $ \mathbf{G}_1 $ and  $ \mathbf{G}_2 $ using a reduction that runs in the game in Lemma 33, and get

 $$ \left|\mathrm{P r}\left[\mathbf{G}_{1}\Rightarrow1\right]-\mathrm{P r}\left[\mathbf{G}_{2}\Rightarrow1\right]\right|\leq\left(1-\frac{\Delta_{2}}{n}\right)^{L}. $$

Finally, we can easily bound the probability that G₂ outputs 1 using Lemma 34. We get

 $$ \mathrm{P r}\left[\mathbf{G}_{2}\Rightarrow1\right]\leq\frac{1}{\left\|\mathbb{F}\right\|^{P}}. $$

Proof of Lemma 20. We first make some simple changes using a sequence of games. Then, we prove the statement via a reduction that runs in the game specified in Lemma 35.

 $ \underline{\text{Game G}_0} $: Let  $ \mathcal{A} $ be an algorithm as in the lemma, running in the code-binding game of CC. We refer to this game as  $ \mathbf{G}_0 $. That is,  $ \mathcal{A} $ is run with input  $ ck := \bot $ and access to random oracles  $ \mathsf{H}, \mathsf{H}_1, \mathsf{H}_2 $. It makes at most  $ Q_{\mathsf{H}}, Q_{\mathsf{H}_1}, Q_{\mathsf{H}_2} $ queries to random oracles  $ \mathsf{H}, \mathsf{H}_1, \mathsf{H}_2 $. Then,  $ \mathcal{A} $ outputs a commitment  $ \text{com} = \big((h_j)_{j \in [n]}, \mathbf{W}, (\mathbf{X}_j)_{j \in J}\big) $ and symbols  $ \mathbf{X}_j' \in \mathbb{F}^k $ for all  $ j $ in some set  $ J' \subseteq [n] $. Technically,  $ \mathcal{A} $ also outputs openings  $ \tau_j = \bot $ for all  $ j \in J' $. The game outputs 1, if there is no  $ \hat{\mathbf{X}} \in \mathcal{C}^{\equiv k} $ such that  $ \hat{\mathbf{X}} $ is consistent with  $ (\mathbf{X}_j')_{j \in J'} $, and all openings verify, i.e.  $ \text{VerCom}(\text{ck}, \text{com}) = 1 $ and for all  $ j \in J' $ it holds that  $ \text{VerCol}(\text{ck}, \text{com}, j, \mathbf{X}_j') = 1 $. Without loss of generality, we assume that  $ \mathcal{A} $ never queries the same input to the same random oracle twice, and that  $ \mathcal{A} $ made all queries that algorithm  $ \text{Ver} $ makes to check  $ \mathcal{A} $'s final output. Also, we assume that whenever  $ \mathcal{A} $ makes a query  $ \mathsf{H}_2(h_1, \ldots, h_n, \mathbf{W}) $, it queried  $ \mathsf{H}_1(h_1, \ldots, h_n) $ before. These assumptions can be achieved by wrapping an additional algorithm around  $ \mathcal{A} $, which increases  $ Q_{\mathsf{H}}, Q_{\mathsf{H}_1}, Q_{\mathsf{H}_2} $ to  $ \bar{Q}_{\mathsf{H}} := Q_{\mathsf{H}} + n, \bar{Q}_{\mathsf{H}_1} := Q_{\mathsf{H}_1} + Q_{\mathsf{H}_2} + 1, \bar{Q}_{\mathsf{H}_2} := Q_{\mathsf{H}_2} + 1 $, respectively. We have

 $$ \mathrm{P r}\left[\mathbf{G}_{0}\Rightarrow1\right]=\mathrm{A d v}_{\mathcal{A},\mathrm{C C}}^{\mathrm{c o d e-b i n d}}(\lambda). $$

Game G₁: This game is defined as G₀, but we introduce two bad events HashPre and HashColl and let the game abort if this event occurs. The events are defined as follows.

- Event HashPre: This event occurs, if $\mathcal{A}$ ever makes a query $\mathsf{H}_1(h_1, \ldots, h_n)$, and later makes a query $\mathsf{H}(x)$ for some input $x \in \{0,1\}^*$ such that $\mathsf{H}(x) = h_j$ for some $j \in [n]$. Phrased differently, this event occurs, if $\mathcal{A}$ makes a query $\mathsf{H}(x)$ that evaluates to $h_j$, and $h_j$ has been input to $\mathsf{H}_1$ before in a query $\mathsf{H}_1(h_1, \ldots, h_n)$.

- Event HashColl: This event occurs, if $\mathcal{A}$ ever makes two different query $\mathsf{H}(x)$, $\mathsf{H}(x')$ for $x \neq x' \in \{0,1\}^*$ such that $\mathsf{H}(x) = \mathsf{H}(x')$.

Using a union bound over all pairs of queries to H, we can bound the probability of HashColl by  $ \bar{Q}_{H}^{2}/2^{\lambda} $. To bound the probability of event HashPre, note that for a fixed query to H, a fixed query to H₁, and a

fixed index  $ j \in [n] $, the probability that HashPre occurs for these queries and this index is  $ 2^{-\lambda} $. Thus, a union bound leads to

 $$ \left|\operatorname{Pr}\left[\mathbf{G}_{0}\Rightarrow1\right]-\operatorname{Pr}\left[\mathbf{G}_{1}\Rightarrow1\right]\right|\leq\operatorname{Pr}\left[\mathbf{H a s h P r e}\right]+\operatorname{Pr}\left[\mathbf{H a s h C o l l}\right]\leq\frac{\bar{Q}_{\mathrm{H}}\bar{Q}_{\mathrm{H}_{1}}n}{2^{\lambda}}+\frac{\bar{Q}_{\mathrm{H}}^{2}}{2^{\lambda}}. $$

Game $\mathbf{G}_2$: In this game, we guess the random oracle queries that are used for $\mathcal{A}$'s final output. More precisely, the game is as $\mathbf{G}_1$, but if first samples two indices $i_1 \leftarrow s$ [$\overline{Q}_{\mathbf{H}_1}$] and $i_2 \leftarrow s$ [$\overline{Q}_{\mathbf{H}_2}$]. Then, it runs $\mathbf{G}_1$ as it is. If the $i_1$th query to $\mathbf{H}_1$ occurs after the $i_2$th query to $\mathbf{H}_2$, the game aborts. Also, let the $i_1$th query to $\mathbf{H}_1$ be $\mathbf{H}_1(h_1, \ldots, h_n)$ and the $i_2$th query to $\mathbf{H}_2$ be $\mathbf{H}_2(h_1', \ldots, h_n', \mathbf{W})$. If $(h_1, \ldots, h_n) \neq (h_1', \ldots, h_n')$, the game also aborts. Consider the final output $\mathbf{com} = ((h_j)_{j \in [n]}; \mathbf{W}, (\mathbf{X}_j)_{j \in J})$ of $\mathcal{A}$. If the $i_1$th query to $\mathbf{H}_1$ was $\mathbf{H}_1(h_1, \ldots, h_n)$ and the $i_2$th query to $\mathbf{H}_2$ was $\mathbf{H}_2(h_1, \ldots, h_n, \mathbf{W})$, the game continues as $\mathbf{G}_1$ does. Otherwise, it aborts. If $\mathbf{G}_1$ outputs 1, there has to be some indices $i_1^*, i_2^*$ that correspond to the hash queries of $\mathcal{A}$'s final output, and such that $i_1^*$th query to $\mathbf{H}_1$ occurs before the $i_2^*$th query to $\mathbf{H}_2$. Therefore, $\mathbf{G}_2$ outputs 1 if and only if $i_1 = i_1^*$ and $i_2 = i_2^*$ and $\mathbf{G}_1$ outputs 1. Note that $\mathcal{A}$'s view is independent of the indices $i_1, i_2$ until a potential abort occurs. Thus, we have

 $$ \mathrm{P r}\left[\mathbf{G}_{1}\Rightarrow1\right]\leq\bar{Q}_{\mathrm{H}_{1}}\bar{Q}_{\mathrm{H}_{2}}\cdot\mathrm{P r}\left[\mathbf{G}_{2}\Rightarrow1\right]. $$

Now, we can easily bound the probability that  $ G_{2} $ outputs 1 using a reduction B that runs in the game specified in Lemma 35. The reduction is as follows.

1. Reduction B simulates  $ G_{2} $ for A, including all aborts specified before.

2. Let the $i_{1}$th query to $\mathrm{H}_{1}$ be $\mathrm{H}_{1}(h_{1},\ldots,h_{n})$ and the $i_{2}$th query to $\mathrm{H}_{2}$ be $\mathrm{H}_{2}(h_{1},\ldots,h_{n},\mathbf{W})$. We know that the $i_{1}$th query to $\mathrm{H}_{1}$ occurs first, as otherwise $\mathbf{G}_{2}$ and the reduction would abort.

(a) When the $i_1$th query to $\mathbf{H}_1$ happens, $\mathcal{B}$ extracts a matrix $\hat{\mathbf{X}}$ as follows: For each $j \in [n]$, reduction $\mathcal{B}$ checks if there is a previous random oracle query of the form $\mathsf{H}(\hat{\mathbf{X}}_j) = h_j$, where $\hat{\mathbf{X}}_j \in \mathbb{F}^k$. As we ruled out event HashColl, there can be at most one such query. If such a query is found, it sets the $j$th column of $\hat{\mathbf{X}}$ to be $\hat{\mathbf{X}}_j$. Otherwise, it sets the $j$th column of $\hat{\mathbf{X}}$ to be $\mathbf{0}$. Then, the reduction outputs $\hat{\mathbf{X}}$ to the game, and gets as input a matrix $\mathbf{R}$. The reduction sets $\mathsf{H}_1(h_1, \ldots, h_n) := \mathbf{R}$, and continues the execution of $\mathcal{A}$.

(b) When the $i_2$th query to $\mathrm{H}_2$ happens, the reduction outputs $\mathbf{W}$ to the game, and gets as input a set $J$. It sets $\mathrm{H}_2(h_1, \ldots, h_n, \mathbf{W}) := J$, and continues $\mathcal{A}$'s execution.

3. When $\mathcal{A}$ terminates with final output $\mathbf{com} = \left((h_j)_{j \in [n]}, \mathbf{W}, (\mathbf{X}_j)_{j \in J}\right)$ and $\mathbf{X}_j' \in \mathbb{F}^k$ for all $j$ in some set $J' \subseteq [n]$, the reduction first does all checks as in $\mathbf{G}_2$. Note that if all checks pass, we know that all $\mathbf{X}_j$ and all $\mathbf{X}_j'$ are consistent with $\hat{\mathbf{X}}$ (cf. events HashColl and HashPre). The reduction now outputs $J'$ and terminates.

It is clear that the reduction perfectly simulates $\mathbf{G}_{2}$ for $\mathcal{A}$. Also, one can observe that if $\mathbf{G}_{2}$ outputs 1, then all winning conditions in the game specified in Lemma 35 hold. Thus, using Lemma 35, we have

 $$ \Pr\left[\mathbf{G}_{2}\Rightarrow1\right]\leq\left(\frac{\Delta_{1}+1}{\left|\mathbb{F}\right|}\right)^{P}+\left(1-\frac{\Delta_{1}+1}{n}\right)^{L}+\left(1-\frac{\Delta_{2}}{n}\right)^{L}+\frac{1}{\left|\mathbb{F}\right|^{P}}. $$

#### I.2 Omitted Details from Section 9.2

Lemma 36. Let A be any stateful algorithm, and consider the following experiment G:

1. Generate hk ↔ HF.Gen(1λ).

2. Run A on input hk to obtain  $ h_1, \ldots, h_n \in \mathcal{R} $.

3. Sample a matrix  $ \mathbf{R} \leftarrow s \mathbb{F}^P \times k $.

4. Run A on input  $ \mathbf{R} $, and get a matrix  $ \mathbf{W} \in \mathbb{F}^{P \times n} $. Let  $ \mathbf{W}_j \in \mathbb{F}^P $ be the  $ j $th column of  $ \mathbf{W} $, for each  $ j \in [n] $.

5. Sample a matrix  $ \mathbf{S} \leftarrow s \mathbb{F}^{n \times L} $.

6. Run A on input S, and obtain an output Y,  $ J' $,  $ (\mathbf{X}_j)_{j \in J'} $ from A.

7. Set Win := 0. If the following four conditions hold, set Win := 1:

(a) There is no  $ \mathbf{X}' \in \mathcal{C}^{\equiv k} $, such that for each  $ j \in J' $, the jth column of  $ \mathbf{X}' $ is equal to  $ \mathbf{X}_j $.

(b) For all  $ j \in J' $, we have  $ \mathbf{W}_j = \mathbf{R}\mathbf{X}_j $ and HF.Eval(hk,  $ \mathbf{X}_j) = h_j $.

(c) For each row  $ \mathbf{w}^\top \in \mathbb{F}^{1 \times n} $ of  $ \mathbf{W} $, we have  $ \mathbf{w} \in \mathcal{C} $.

(d) For each  $ j \in [L] $, we have HF.Eval(hk, Y_j) = [h_1, ... h_n]S_j and RY = WS.

Then, for any PPT algorithm A in the above game, there is an EPT algorithm B with expected running time  $ \mathbf{E}\mathbf{T}(\mathcal{B}) \approx (1 + n)\mathbf{T}(\mathcal{A}) $ we have

 $$ \Pr_{\mathcal{G}}\left[\mathrm{W i n}=1\right]\leq\frac{n}{\left|\mathbb{F}\right|^{L}}+\frac{1}{\left|\mathbb{F}\right|^{P}}+\frac{1}{\left|\mathbb{F}\right|^{L}}+\mathsf{A d v}_{\mathcal{B},\mathsf{H F}}^{\mathrm{c o l l}}(\lambda). $$

Proof. Our proof strategy is as follows. We first sample a random a hash key hk and adversarial randomness, and fix it. Then, we run game G with this fixed key and randomness multiple times with independent challenges, until we can extract preimages of all hash values  $ h_1, \ldots, h_n $. We run  $ G' $ a final time, rule out inconsistencies by reducing to collision-resistance, and use statistical arguments to finish the proof.

We will now proceed more formally. Let $\mathcal{A}$ be a PPT algorithm in the game $\mathcal{G}$ specified in the lemma. We define $\varepsilon_0 := \operatorname{Pr}_\mathcal{G} [\operatorname{Win} = 1]$. We want to bound this probability $\varepsilon_0$. Assume that $\mathcal{A}$ makes use of $\ell = \text{poly}(\lambda)$ random coins. By making states and randomness explicit, we can write $\mathcal{A}$ as a triple of PPT algorithms $(\mathcal{A}_0, \mathcal{A}_1, \mathcal{A}_2)$, with the following syntax:

-  $ \mathcal{A}_0(\mathsf{hk};\rho) \to (St_0, h_1, \ldots, h_n) $ takes as input the key  $ \mathsf{hk} $ and random coins  $ \rho \in \{0,1\}^\ell $. It outputs a state  $ St_0 $ and values  $ h_1, \ldots, h_n \in \mathcal{R} $.

•  $ \mathcal{A}_1(St_0, \mathbf{R}) \to (St_1, \mathbf{W}) $ is deterministic, takes as input  $ St_0 $, a matrix  $ \mathbf{R} $, and outputs a state  $ St_1 $ and a matrix  $ \mathbf{W} $.

•  $ \mathcal{A}_2(St_1, \mathbf{S}) \to (\mathbf{Y}, J', (\mathbf{X}_j)_{j \in J'}) $ is deterministic, takes as input  $ St_1 $ and a matrix  $ \mathbf{S} $, and outputs  $ \mathbf{Y}, J', (\mathbf{X}_j)_{j \in J'} $.

Note that assuming that $\mathcal{A}$ gets all its random coins in the beginning is without loss of generality, as $\mathcal{A}_0$ can just pass these coins to $\mathcal{A}_1$ and $\mathcal{A}_2$ via its state. We introduce another notation. Namely, we denote the game $\mathcal{G}$ with fixed hash key $\mathsf{hk}$ and fixed adversarial random coins $\rho$ by $\mathcal{G}(\mathsf{hk},\rho)$. Also, we define $\varepsilon_{\mathsf{hk},\rho} := \operatorname{Pr}_{\mathcal{G}(\mathsf{hk},\rho)}[\mathsf{Win} = 1]$ for any $\mathsf{hk},\rho$.

 $ \underline{\text{Game G'}} $: We define a new game G'. In this game, we run the adversary multiple times with the same hk and  $ \rho $. Formally, we define G' as follows.

1. Generate hk ↔ HF.Gen(1λ) and sample ρ ↔ s {0,1}ℓ.

2. Run  $ \mathcal{G}(\mathsf{hk},\rho) $ and denote all variables  $ x $ involved in this game run by  $ x^0 $. For example, variables  $ \text{Win}, \text{S} $ in this game run are denoted by  $ \text{Win}^{(0)}, \mathbf{S}^{(0)} $, respectively. If  $ \text{Win}^{(0)} = 0 $, abort.

3. Initialize an empty list  $ S := \emptyset $, an empty map  $ SY[\cdot] $, and a counter  $ q := 1 $.

4. While  $ |\mathcal{S}| < n $, repeat the following:

(a) Run  $ \mathcal{G}(\mathsf{hk},\rho) $. Denote all variables  $ x $ involved in this game run by  $ x^{(q)} $. For example, variables Win, S in this game run are denoted by  $ \mathrm{Win}^{(q)} $,  $ \mathrm{S}^{(q)} $, respectively.

(b) If  $ \mathrm{Win}^{(q)} = 1 $, then insert  $ \mathbf{S}^{(q)} $ into S. Further, set  $ \mathrm{SY}[\mathbf{S}] := \mathbf{Y} $.

(c) Set  $ q := q + 1 $.

5. Set  $ q^* := q $.

We will now analyze this game. Namely, we shall show two things. First, we establish a relation between the probability of  $ \mathrm{Win}=1 $ in  $ \mathcal{G} $ and  $ \mathrm{Win}^{(0)}=1 $ in  $ \mathcal{G}' $. Second, we argue that the game runs in expected polynomial time.

Claim 7. Consider the notations and assumptions from the proof of Lemma 36. We have

 $$ \Pr_{\mathcal{G}^{\prime}}\left[\mathrm{W i n}^{(0)}=1\right]=\Pr_{\mathcal{G}}\left[\mathrm{W i n}=1\right]=\varepsilon_{0}. $$

We prove Claim 7. Namely, first observe that if hk,  $ \rho $ is fixed in  $ G' $, then Step 2 is clearly independent of the rest of the game. Therefore, we have

 $$ \Pr_{\mathcal{G}^{\prime}}\left[\mathrm{W i n}^{(0)}=1\middle|\left(\mathsf{h}\mathsf{k},\rho\right)=\left(\bar{\mathsf{h}}\bar{\mathsf{k}},\bar{\rho}\right)\right]=\Pr_{\mathcal{G}(\bar{\mathsf{h}}\bar{\mathsf{k}},\bar{\rho})}\left[\mathrm{W i n}=1\right]=\Pr_{\mathcal{G}}\left[\mathrm{W i n}=1\middle|\left(\mathsf{h}\mathsf{k},\rho\right)=\left(\bar{\mathsf{h}}\bar{\mathsf{k}},\bar{\rho}\right)\right] $$

for each hk,  $ \bar{\rho} $. Now, we can use the law of total probability to finish the proof of the claim, i.e.

 $$ \begin{align*}\Pr_{\mathcal{G}^{\prime}}\left[\mathsf{Win}^{(0)}=1\right]&=\sum_{\bar{\mathsf{h}}\bar{\mathsf{k}},\bar{\rho}}\Pr_{\mathcal{G}^{\prime}}\left[\mathsf{Win}^{(0)}=1\middle|\left(\mathsf{h}\mathsf{k},\rho\right)=\left(\bar{\mathsf{h}}\bar{\mathsf{k}},\bar{\rho}\right)\right]\cdot\Pr_{\mathsf{h}\mathsf{k},\rho}\left[\left(\mathsf{h}\mathsf{k},\rho\right)=\left(\bar{\mathsf{h}}\bar{\mathsf{k}},\bar{\rho}\right)\right]\\&=\sum_{\bar{\mathsf{h}}\bar{\mathsf{k}},\bar{\rho}}\Pr_{\mathcal{G}}\left[\mathsf{Win}=1\middle|\left(\mathsf{h}\mathsf{k},\rho\right)=\left(\bar{\mathsf{h}}\bar{\mathsf{k}},\bar{\rho}\right)\right]\cdot\Pr_{\mathsf{h}\mathsf{k},\rho}\left[\left(\mathsf{h}\mathsf{k},\rho\right)=\left(\bar{\mathsf{h}}\bar{\mathsf{k}},\bar{\rho}\right)\right]\\&=\Pr_{\mathcal{G}}\left[\mathsf{Win}=1\right].\end{align*} $$

Claim 8. Consider the notations and assumptions from the proof of Lemma 36. The expected running time of  $ G' $ is at most  $ 1+n $ times the running time of G.

We prove Claim 8. We show the bound on the running time for any fixed hk,  $ \rho $, which implies that it holds for random hk,  $ \rho $. Denote the random variable modeling the running time of  $ \mathcal{G}' $ by  $ T' $ and the running time of  $ \mathcal{G} $ by  $ T $. Consider the case where  $ \varepsilon_{hk,\rho} = 0 $. Then, game  $ \mathcal{G}' $ always stops in Step 2. Thus, we can assume that  $ \varepsilon_{hk,\rho} > 0 $ from now on. We shall first argue that the expected number of iterations  $ q^* $ of the loop in Step 4 is bounded by  $ n/\varepsilon_{hk,\rho} $. Then, we can conclude using the law of total expectation and linearity of expectation. Namely,

 $$ \begin{align*}\mathbb{E}\left[T^{\prime}\right]&=\Pr\left[\mathsf{Win}^{(0)}=0\right]\mathbb{E}\left[T^{\prime}\mid\mathsf{Win}^{(0)}=0\right]+\Pr\left[\mathsf{Win}^{(0)}=1\right]\mathbb{E}\left[T^{\prime}\mid\mathsf{Win}^{(0)}=1\right].\\&=\left(1-\varepsilon_{\mathsf{hk},\rho}\right)\cdot T+\varepsilon_{\mathsf{hk},\rho}\cdot\left(T+\mathbb{E}\left[q^{*}\mid\mathsf{Win}^{(0)}=1\right]\cdot T\right)=\left(1+\varepsilon_{\mathsf{hk},\rho}\cdot\mathbb{E}\left[q^{*}\right]\right)\cdot T=\left(1+n\right)\cdot T,\end{align*} $$

where we used that for fixed hk,  $ \rho $, the random variable  $ q^* $ is independent of  $ \text{Win}^{(0)} $. It remains to argue that  $ \mathbb{E}[q^*] \leq n/\varepsilon_{\text{hk}, \rho} $. For each  $ i \in [n] $, let  $ X_i $ be the random variable equal to the number of iterations of Step 4 needed to increase the size of  $ \mathcal{S} $ from  $ i - 1 $ to  $ i $. Then, by linearity of expectation and the fact that  $ q^* = \sum_{i=1}^n $, it is sufficient bound the expectation of each  $ X_i $ by  $ 1/\varepsilon_{\text{hk}, \rho} $. For that, consider the probability that in a fixed iteration of the loop in Step 4, a matrix is added to the list  $ \mathcal{S} $. By definition, it is added if  $ \text{Win}^{(q)} = 1 $. The probability of  $ \text{Win}^{(q)} = 1 $ is exactly  $ \varepsilon_{\text{hk}, \rho} $. Thus,  $ X_i $ follows a geometric distribution with parameter  $ \varepsilon_{\text{hk}, \rho} $, which has expectation  $ 1/\varepsilon_{\text{hk}, \rho} $, as desired. This finishes the proof of Claim 8.

 $ \underline{\text{Game \mathcal{G}'}} $: We slightly modify game \mathcal{G}' into a game \mathcal{G}''. Formally, we define \mathcal{G}' as follows.

1. Run Steps 1 to 5 of game G′.

2. Set  $ \bar{\mathbf{X}} = \mathbf{0} $. Also, initialize an empty set  $ S' = \emptyset $ and an empty map  $ SY'[\cdot] $.

3. Iterate over the matrices in S. Namely, for each  $ i \in [n] $, do the following:

(a) Let  $ \mathbf{S} \in \mathbb{F}^{n \times L} $ be the ith matrix in  $ \mathcal{S} $.

(b) If there is no column s of S that is linearly independent to the set  $ S' $, then set  $ \text{Extr} := 0 $ and abort the game.

(c) Otherwise, let s be such a column, say the jth. Insert s into  $ S' $, and set  $ SY' := y $, where y is the jth column of  $ SY[S] $.

4. Set Extr := 1.

5. By construction, the vectors contained in $\mathcal{S}'$ are linearly independent. Arrange them as columns into an invertible matrix $\bar{\mathbf{S}} \in \mathbb{F}^{n \times n}$. Similarly, arrange the $n$ vectors in the multi-set $\{SY'[\mathbf{s}] \mid \mathbf{s} \in \mathcal{S}'\}$ into a matrix $\bar{\mathbf{Y}} \in \mathbb{F}^{k \times n}$. Ensure that for each $\mathbf{s} \in \mathcal{S}'$, if $\mathbf{s}$ is the $j$th column of $\bar{\mathbf{S}}$, then $\mathbf{y} := SY'[\mathbf{s}]$ is the $j$th column of $\bar{\mathbf{Y}}$.

6. Compute  $ \bar{\mathbf{X}} := \bar{\mathbf{Y}}\bar{\mathbf{S}}^{-1} $. We denote the columns of  $ \bar{\mathbf{X}} $ by  $ \bar{\mathbf{X}}_j $ for each  $ j \in [n] $.

In Claim 9, we bound the probability of  $ \text{Extr} = 0 $ conditioned on the game not aborting and any fixed hash key and randomness. Using this claim, we get for any fixed  $ \bar{h}\bar{k}, \bar{\rho} $ with  $ \varepsilon_{\bar{h}\bar{k}, \bar{\rho}} > 0 $, that

 $$ \begin{align*}\Pr_{\mathcal{G}^{\prime\prime}}\Big[\mathrm{Win}^{(0)}&=1\wedge\mathrm{Extr}=0\mid(\mathsf{h}\mathsf{k},\rho)=(\bar{\mathsf{h}}\mathsf{k},\bar{\rho})\Big]=\quad&\Pr_{\mathcal{G}^{\prime\prime}}\Big[\mathrm{Extr}=0\mid\mathrm{Win}^{(0)}=1\wedge(\mathsf{h}\mathsf{k},\rho)=(\bar{\mathsf{h}}\mathsf{k},\bar{\rho})\Big]\\ &\quad\cdot\Pr_{\mathcal{G}^{\prime\prime}}\Big[\mathrm{Win}^{(0)}=1\mid(\mathsf{h}\mathsf{k},\rho)=(\bar{\mathsf{h}}\mathsf{k},\bar{\rho})\Big]\\ &\leq\quad\frac{n}{\varepsilon_{\mathsf{h}\bar{\mathsf{k}},\bar{\rho}}\cdot|\mathbb{F}|^{L}}\cdot\varepsilon_{\mathsf{h}\bar{\mathsf{k}},\bar{\rho}}=\frac{n}{|\mathbb{F}|^{L}}.\end{align*} $$

The same upper bound holds trivially for any  $ \hbar\bar{k},\bar{\rho} $ with  $ \varepsilon_{\hbar\bar{k},\bar{\rho}}=0 $. This implies that

 $$ \begin{align*}\Pr_{\mathcal{G}^{\prime\prime}}\left[\mathrm{Win}^{(0)}=1\wedge\mathrm{Extr}=0\right]&=\sum_{\bar{\mathsf{h}}\bar{\mathsf{k}},\bar{\rho}}\Pr_{\mathcal{G}^{\prime\prime}}\left[\mathrm{Win}^{(0)}=1\wedge\mathrm{Extr}=0\mid(\mathsf{h}\mathsf{k},\rho)=(\bar{\mathsf{h}}\bar{\mathsf{k}},\bar{\rho})\right]\cdot\Pr_{\mathcal{G}^{\prime\prime}}\left[(\mathsf{h}\mathsf{k},\rho)=(\bar{\mathsf{h}}\bar{\mathsf{k}},\bar{\rho})\right]\\&\leq\sum_{\bar{\mathsf{h}}\bar{\mathsf{k}},\bar{\rho}}\frac{n}{|\mathbb{F}|^{L}}\Pr_{\mathcal{G}^{\prime\prime}}\left[(\mathsf{h}\mathsf{k},\rho)=(\bar{\mathsf{h}}\bar{\mathsf{k}},\bar{\rho})\right]=\frac{n}{|\mathbb{F}|^{L}}.\end{align*} $$

Thus, we have

 $$ \begin{align*}\varepsilon_{0}=\Pr_{\mathcal{G}^{\prime}}\left[\mathrm{Win}^{(0)}=1\right]&\leq\Pr_{\mathcal{G}^{\prime\prime}}\left[\mathrm{Win}^{(0)}=1\wedge\mathrm{Extr}=1\right]+\Pr_{\mathcal{G}^{\prime\prime}}\left[\mathrm{Win}^{(0)}=1\wedge\mathrm{Extr}=0\right]\\&\leq\Pr_{\mathcal{G}^{\prime\prime}}\left[\mathrm{Win}^{(0)}=1\wedge\mathrm{Extr}=1\right]+\frac{n}{|\mathbb{F}|^{L}}.\end{align*} $$

Finally, we will bound the probability that  $ \text{Win}^{(0)} = 1 $ and  $ \text{Extr} = 1 $ in game  $ \mathcal{G}' $. For that, we introduce the following events in  $ \mathcal{G}' $.

• Event HColl: This event occurs, if  $ \mathbf{Y}^{(0)} \neq \bar{\mathbf{X}}\mathbf{S}^{(0)} $ or there is a  $ j \in J'^{(0)} $, such that  $ \bar{\mathbf{X}}_j \neq \mathbf{X}_j^{(0)} $.

• Event InCode: This event occurs, if  $ \mathbf{R}^{(0)}\bar{\mathbf{X}}\in\mathcal{C}^{\equiv P} $.

By the law of total probability, we have

 $$ \begin{align*}\Pr_{\mathcal{G}^{\prime\prime}}\left[\mathrm{Win}^{(0)}=1\wedge\mathrm{Extr}=1\right]&\leq\Pr_{\mathcal{G}^{\prime\prime}}\left[\mathrm{Win}^{(0)}=1\wedge\mathrm{Extr}=1\wedge\mathrm{HColl}\right]\\&\quad+\Pr_{\mathcal{G}^{\prime\prime}}\left[\mathrm{Win}^{(0)}=1\wedge\mathrm{Extr}=1\wedge\neg\mathrm{HColl}\wedge\mathrm{InCode}\right]\\&\quad+\Pr_{\mathcal{G}^{\prime\prime}}\left[\mathrm{Win}^{(0)}=1\wedge\mathrm{Extr}=1\wedge\neg\mathrm{HColl}\wedge\neg\mathrm{InCode}\right].\end{align*} $$

We bound these terms separately in claims 10 to 12. In combination, this will conclude the proof.

Claim 9. Consider the notations and assumptions from the proof of Lemma 36. Let  $ \bar{h}k \in \text{HF.Gen}(1^\lambda) $ and  $ \bar{\rho} \in \{0,1\}^\ell $ be fixed arbitrarily. Then, we have

 $$ \Pr_{\mathcal{G}^{\prime\prime}}\left[\mathsf{E x t r}=0\mid\mathsf{W i n}^{(0)}=1\wedge(\mathsf{h k},\rho)=(\bar{\mathsf{h k}},\bar{\rho})\right]\leq\frac{n}{\varepsilon_{\mathsf{h}\bar{\mathsf{k}},\bar{\rho}}\cdot\left|\mathbb{F}\right|^{L}}. $$

We prove Claim 9. To this end, consider a fixed  $ \hbar\kappa $ and  $ \bar{\rho} $ and assume  $ \mathrm{Win}^{(0)} = 1 $. We can bound the probability of  $ \mathrm{Extr} = 0 $ occurring in a fixed iteration of the loop, say the ith. Then, the result will follow using a union bound over all the  $ n $ iterations. So, consider the  $ i $th iteration of the loop, and assume that at the beginning of this  $ i $th iteration of the loop, we have  $ r := |\mathcal{S}'| < n $. Then,  $ \mathcal{S}' $ is a set of  $ r $ linearly independent vectors over  $ \mathbb{F} $, which span a subspace  $ D \subset \mathbb{F}^n $ of dimension  $ r < n $. Let  $ q_i $ be the iteration of the loop in Step 4 of game  $ \mathcal{G}' $ in which the  $ i $th matrix of  $ \mathcal{S} $ has been added to  $ \mathcal{S} $. Recall that in this  $ q_i $th iteration,  $ \mathcal{G}(\hbar, \bar{\rho}) $ has been executed, and the only random choices in this game are the challenge matrices  $ \mathbf{R}^{(q_i)} $ and  $ \mathbf{S}^{(q_i)} $. As we know that  $ \mathrm{Win}^{(q_i)} = 1 $, we can think of  $ \mathbf{R}^{(q_i)} $,  $ \mathbf{S}^{(q_i)} $ as being sampled uniformly at random from the set  $ \Gamma \subseteq \mathbb{F}^{P \times k} \times \mathbb{F}^{n \times L} $ of matrices  $ (\mathbf{R}, \mathbf{S}) $ for which  $ \mathrm{Win} = 1 $ in  $ \mathcal{G}(\hbar, \bar{\rho}) $ with challenges  $ \mathbf{R}, \mathbf{S} $. This set has size at least one. More precisely, by definition of  $ \varepsilon_{\hbar, \bar{\rho}} $, it has size  $ \varepsilon_{\hbar, \bar{\rho}} \cdot |\mathbb{F}^{P \times k}| \cdot |\mathbb{F}^{n \times L}| > 0 $. Then, by what we have discussed so far, the probability of  $ \mathrm{Extr} = 0 $ occurring in the  $ i $th iteration of the loop is at most

 $$ \begin{align*}\Pr_{(\mathbf{R}^{(q_{i})},\mathbf{S}^{(q_{i})})\leftrightarrow\mathbf{s}}\left[\mathbf{S}^{(q_{i})}\in D^{L}\right]&=\frac{|\mathbb{F}^{P\times k}|\cdot|D|^{L}}{|\Gamma|}=\frac{|\mathbb{F}^{P\times k}|\cdot|\mathbb{F}|^{rL}}{\varepsilon_{\bar{\mathsf{h k}},\bar{\rho}}\cdot|\mathbb{F}^{P\times k}|\cdot|\mathbb{F}^{n\times L}|}\\&=\frac{1}{\varepsilon_{\bar{\mathsf{h k}},\bar{\rho}}\cdot|\mathbb{F}|^{(n-r)L}}\leq\frac{1}{\varepsilon_{\bar{\mathsf{h k}},\bar{\rho}}\cdot|\mathbb{F}|^{L}},\end{align*} $$

where we used r < n. This finishes the proof of Claim 9.

Claim 10. Consider the notations and assumptions from the proof of Lemma 36. Then, there is an algorithm  $ \mathcal{B} $ with expected running time  $ \mathbf{ET}(\mathcal{B}) \approx (1 + n)\mathbf{T}(\mathcal{A}) $ and

 $$ \operatorname*{P r}_{\mathcal{G}^{\prime\prime}}\left[\mathsf{W i n}^{(0)}=1\wedge\mathsf{E x t r}=1\wedge\mathsf{H C o l l}\right]\leq\mathsf{A d v}_{\mathcal{B},\mathsf{H F}}^{\mathsf{c o l l}}(\lambda). $$

To prove Claim 10, we will argue that the two sub-events specified in event HColl imply a collision for HF. Then, one can construct a reduction to collision-resistance. Such a reduction gets as input the hashing key hk, runs G'', and outputs the collision if event Win}^{(0)} = 1 and Extr = 1 and HColl occurs. In this way, the reduction perfectly simulates G'' for A, and the expected running time of the reduction is polynomial. It remains to argue that Win}^{(0)} = 1 and Extr = 1 and HColl implies a collision. The reader may then observe that these collisions can be efficiently found by the reduction. So, assume that these three events occur. First, it is clear that for each  $ q \in [q^*] \cup \{0\} $, the hash values  $ h_1^{(q)}, \ldots, h_n^{(q)} $ sent by A are the same. This is because A gets the same hk and randomness  $ \rho $ in every run of G. Thus, we can just denote these hash values by  $ h_1, \ldots, h_n $. Now, we claim that for each column  $ j \in [n] $, we have HF.Eval(hk,  $ \mathbf{X}_j) = h_j $. To see this, fix an arbitrary  $ j^* \in [n] $. We have

 $$ \mathsf{H F.E v a l}(\mathsf{h k},\bar{\mathbf{X}}_{j^{*}})=\mathsf{H F.E v a l}(\mathsf{h k},\bar{\mathbf{Y}}\bar{\mathbf{S}}_{j^{*}}^{-1})=\left[\mathsf{H F.E v a l}(\mathsf{h k},\bar{\mathbf{Y}}_{1})\mid\cdots\mid\mathsf{H F.E v a l}(\mathsf{h k},\bar{\mathbf{Y}}_{n})\right]\bar{\mathbf{S}}_{j^{*}}^{-1} $$

using the definition of  $ \mathbf{X} := \mathbf{Y}\mathbf{S}^{-1} $ and the homomorphic property of HF. We continue using the fact that the responses are accepting, namely

 $$ \begin{align*}\left[\mathsf{H F.Eval}(\mathsf{h k},\bar{\mathbf{Y}}_{1})\mid\cdots\mid\mathsf{H F.Eval}(\mathsf{h k},\bar{\mathbf{Y}}_{n})\right]\bar{\mathbf{S}}_{j^{*}}^{-1}&=\left[\sum_{j=1}^{n}h_{j}\bar{\mathbf{S}}_{j,1}\middle|\cdots\middle|\sum_{j=1}^{n}h_{j}\bar{\mathbf{S}}_{j,n}\right]\bar{\mathbf{S}}_{j^{*}}^{-1}\\&=[h_{1}\mid\cdots\mid h_{n}]\cdot\bar{\mathbf{S}}\cdot\bar{\mathbf{S}}_{j^{*}}^{-1}=h_{j^{*}}.\end{align*} $$

Now that we established this, it is clear that the two sub-events of HColl imply a collision, and the claim follows.

Claim 11. Consider the notations and assumptions from the proof of Lemma 36. Then

 $$ \Pr_{\mathcal{G}^{\prime\prime}}\left[\mathrm{W i n}^{(0)}=1\wedge\mathrm{E x t r}=1\wedge\neg\mathrm{H C o l l}\wedge\mathrm{I n C o d e}\right]\leq\frac{1}{|\mathbb{F}|^{P}}. $$

To prove Claim 11, assume event  $ \text{Win}^{(0)} = 1 \land \text{Extr} = 1 \land \neg \text{HColl} \land \text{InCode occurs in } \mathcal{G}'' $. Then, because of  $ \neg \text{HColl} $, we know that the columns  $ \mathbf{X}_j^{(0)} $ for  $ j \in J'(0) $ are consistent with the columns of  $ \bar{\mathbf{X}} $. Because of

the second condition required for  $ \mathrm{Win}^{(0)} = 1 $, we thus know that  $ \bar{\mathbf{X}} \notin \mathcal{C}^{\equiv k} $. Thus, the event of interest implies that

 $$ \bar{\mathbf{X}}\notin\mathcal{C}^{\equiv k}\wedge\mathbf{R}^{(0)}\bar{\mathbf{X}}\in\mathcal{C}^{\equiv P}, $$

where  $ \bar{\mathbf{X}} $ is independent of  $ \mathbf{R}^{(0)} \in \mathbb{F}^{P \times k} $. Let  $ \mathbf{H} \in \mathbb{F}^{(n-k) \times n} $ be the parity-check matrix of  $ \mathbf{G} $. That is, for all  $ \mathbf{a} \in \mathbb{F}^n $, we have  $ \mathbf{H}\mathbf{a} = \mathbf{0} $ if and only if  $ \mathbf{a} \in \mathcal{C} $. Then, we have

 $$ \bar{\mathbf{X}}\mathbf{H}^{\top}\neq\mathbf{0}\wedge\mathbf{R}^{(0)}\bar{\mathbf{X}}\mathbf{H}^{\top}=\mathbf{0}. $$

As all rows of  $ \mathbf{R}^{(0)} $ are independent, this event occurs with probability at most  $ 1/|\mathbb{F}|^{P} $.

Claim 12. Consider the notations and assumptions from the proof of Lemma 36. Then

 $$ \Pr_{\mathcal{G}^{\prime\prime}}\left[\mathrm{W i n}^{(0)}=1\wedge\mathrm{E x t r}=1\wedge\neg\mathrm{H C o l l}\wedge\neg\mathrm{I n C o d e}\right]\leq\frac{1}{|\mathbb{F}|^{L}}. $$

To prove Claim 12, assume that event  $ \text{Win}^{(0)} = 1 \land \text{Extr} = 1 \land \neg \text{HColl} \land \neg \text{InCode occurs in } \mathcal{G}''  $. Then, we know that  $ \mathbf{R}^{(0)} \mathbf{Y}^{(0)} = \mathbf{W}^{(0)} \mathbf{S}^{(0)} $, because  $ \text{Win}^{(0)} = 1 $. Also, we know that  $ \mathbf{Y}^{(0)} = \bar{\mathbf{X}} \mathbf{S}^{(0)} $ because  $ \neg \text{HColl} $. This implies that  $ \mathbf{R}^{(0)} \bar{\mathbf{X}} \mathbf{S}^{(0)} = \mathbf{W}^{(0)} \mathbf{S}^{(0)} $. Because  $ \neg \text{InCode} $, we also know that  $ \mathbf{R}^{(0)} \bar{\mathbf{X}} \neq \mathbf{W}^{(0)} $. Thus, we obtain that

 $$ (\mathbf{R}^{(0)}\bar{\mathbf{X}}-\mathbf{W}^{(0)})\mathbf{S}^{(0)}=\mathbf{0}\wedge\mathbf{R}^{(0)}\bar{\mathbf{X}}-\mathbf{W}^{(0)}\neq\mathbf{0}, $$

where  $ \mathbf{R}^{(0)}\bar{\mathbf{X}}-\mathbf{W}^{(0)} $ and  $ \mathbf{S}^{(0)}\in\mathbb{F}^{n\times L} $ are independent. This occurs with probability at most  $ 1/|\mathbb{F}|^L $, as all columns of  $ \mathbf{S}^{(0)} $ are sampled independently.

Proof of Lemma 22. We prove the lemma using Lemma 36. Except for that, the proof is almost identical to the proof of Lemma 20.

 $ \underline{\text{Game G}_0 $: Let }  $ \mathcal{A} $ be an algorithm as in the lemma, running in the code-binding game of CC[HF]. We call this code-binding game  $ \mathbf{G}_0 $. Recall that in this game,  $ \mathcal{A} $ receives a commitment key  $ \text{ck} = \text{hk} \leftarrow \text{HF.Gen}(1^\lambda) $ and gets oracle access random oracles  $ \mathbf{H}_1, \mathbf{H}_2 $. We assume that  $ \mathcal{A} $ makes at most  $ Q_{\mathbf{H}_1}, Q_{\mathbf{H}_2} $ queries to random oracles  $ \mathbf{H}_1, \mathbf{H}_2 $, respectively. Then,  $ \mathcal{A} $ outputs a commitment  $ \text{com} = \big((h_j)_{j \in [n]}, \mathbf{W}, \mathbf{Y}\big) $ and symbols  $ \mathbf{X}_j' \in \mathbb{F}^k $ for all  $ j $ in some set  $ J' \subseteq [n] $. The game  $ \mathbf{G}_0 $ outputs 1, if there is no  $ \hat{\mathbf{X}} \in \mathcal{C}^{\equiv k} $ such that  $ \hat{\mathbf{X}} $ is consistent with  $ (\mathbf{X}_j')_{j \in J',} $ and all openings verify, i.e.  $ \text{VerCom}(\text{ck}, \text{com}) = 1 $ and for all  $ j \in J' $ it holds that  $ \text{VerCol}(\text{ck}, \text{com}, j, \mathbf{X}_j') = 1 $. As in the proof of Lemma 20, we assume without loss of generality that  $ \mathcal{A} $ never queries the same input to the same random oracle twice, and that  $ \mathcal{A} $ made all queries that algorithm  $ \text{Ver} $ makes to check  $ \mathcal{A}' $s final output. Also, we assume that whenever  $ \mathcal{A} $ makes a query  $ \mathbf{H}_2(h_1, \ldots, h_n, \mathbf{W}) $, it queried  $ \mathbf{H}_1(h_1, \ldots, h_n) $ before. As in the proof of Lemma 20, this increases  $ Q_{\mathbf{H}_1} $ and  $ Q_{\mathbf{H}_2} $ to  $ \bar{Q}_{\mathbf{H}_1} := Q_{\mathbf{H}_1} + Q_{\mathbf{H}_2} + 1 $ and  $ \bar{Q}_{\mathbf{H}_2} := Q_{\mathbf{H}_2} + 1 $, respectively. We have

 $$ \mathrm{P r}\left[\mathbf{G}_{0}\Rightarrow1\right]=\mathrm{A d v}_{\mathcal{A},\mathrm{C C}[\mathrm{H F}]}^{\mathrm{c o d e-b i n d}}(\lambda). $$

Game $\mathbf{G}_1$: In game $\mathbf{G}_1$, we let the game guess the random oracle queries related to $\mathcal{A}$'s final output. Namely, in the beginning of the game, indices $i_1 \leftarrow s$ $\left[\bar{Q}_{\mathbf{H}_1}\right]$ and $i_2 \leftarrow s$ $\left[\bar{Q}_{\mathbf{H}_2}\right]$ are sampled. Then, $\mathbf{G}_1$ behaves as $\mathbf{G}_0$. Let the $i_1$th query to $\mathbf{H}_1$ be $\mathbf{H}_1(h_1, \ldots, h_n)$ and the $i_2$th query to $\mathbf{H}_2$ be $\mathbf{H}_2(h_1', \ldots, h_n', \mathbf{W})$. If $(h_1, \ldots, h_n) \neq (h_1', \ldots, h_n')$, or the $i_1$th query to $\mathbf{H}_1$ occurs after the $i_2$th query to $\mathbf{H}_2$, the game aborts. Once $\mathcal{A}$ outputs $\mathbf{com} = \left((h_j)_{j \in [n]}$, \mathbf{W}, \mathbf{Y}\right)$ and $\mathbf{X}_j' \in \mathbb{F}^k$ for all $j \in J',$ the game checks if the $i_1$th query to $\mathbf{H}_1$ was $\mathbf{H}_1(h_1, \ldots, h_n)$ and the $i_2$th query to $\mathbf{H}_2$ was $\mathbf{H}_2(h_1, \ldots, h_n', \mathbf{W})$. If not, the game aborts. Otherwise, it continues as $\mathbf{G}_0$ does. One can easily see that

 $$ \mathrm{P r}\left[\mathbf{G}_{0}\Rightarrow1\right]\leq\bar{Q}_{\mathrm{H}_{1}}\bar{Q}_{\mathrm{H}_{2}}\cdot\mathrm{P r}\left[\mathbf{G}_{1}\Rightarrow1\right]. $$

Now, we can bound the probability that  $ \mathbf{G}_1 $ outputs 1 using a reduction, which runs in the game given in Lemma 36. Roughly, it embeds its challenges into the  $ i_1 $th and  $ i_2 $th random oracle queries to  $ \mathbf{H}_1 $ and  $ \mathbf{H}_2 $, respectively. By Lemma 36, we get that there is an algorithm  $ \mathcal{B} $ with

 $$ \mathrm{P r}\left[\mathbf{G}_{1}\Rightarrow1\right]\leq\frac{n}{\left|\mathbb{F}\right|^{L}}+\frac{1}{\left|\mathbb{F}\right|^{P}}+\frac{1}{\left|\mathbb{F}\right|^{L}}+\mathsf{A d v}_{\mathcal{B},\mathsf{H F}}^{\mathrm{c o l l}}(\lambda). $$

### J Simulation of Index Samplers

While the analytical results in Section 6.2 provide bounds on the quality of different index samplers, their analysis makes heavy use of bounds, e.g., the union bound. Thus, it is natural to ask whether one can obtain more precise results by analyzing and comparing index samplers other means, e.g., via simulation.

**Experiment.** We can think of index sampling as the following balls-into-bins experiment. We have  $ N $ bins and  $ \ell $ players. Each player is allowed to throw  $ Q $ balls into the bins, following some fixed strategy, which is given by the index sampler algorithm  $ \text{Sample}(1^Q, 1^N) $. More precisely, the players all start with the same state. Further, they are not aware of any identifiers to break symmetry and can not communicate. Each player starts with a random tape and runs  $ (i_j)_{j \in [Q]} \leftarrow \text{Sample}(1^Q, 1^N) $. Then, it throws its balls into the bins  $ i_1, \ldots, i_Q $. We want to estimate the probability that less than  $ K $ bins are non-empty after the experiment.

Setup. For our simulation, we implemented the experiment in C++. We ran the experiment for the three index samplers Samplewr (sampling uniformly with replacement), Samplewor (sampling uniformly without replacement), and Sampleseg (segment sampling). We estimated the probability of interest by averaging over 20000 runs of the experiment. This process was repeated for various combinations of  $ \ell $, Q, N, K. When we select such parameter sets, we pay attention to avoid divisibility issues. For example, say we used segment sampling with Q = 64 and we want to have at least K = N/4 non-empty bins out of N. A first intuition would tell us that for N = 1152 we would need less samples to ensure that than for N = 1280. However, we would observe the opposite due to a divisibility phenomenon. Namely, for N = 1152 we would have to collect at least K/Q = 4.5 out of N/Q = 18 segments, i.e., 5 out of 18. For N = 1280 we would have to collect K/Q = 5 out of N/Q = 20 segments, i.e., 5 out of 20. Collecting 5 out of 20 requires less samples than 5 out of 18, contradicting our initial intuition. Such phenomenon's distract from the actual message we want to convey and the asymptotic behavior of index samples. Therefore, we choose parameters that avoid these divisibility issues. The code of our simulation can be found in

 $$ \underset{(https://github.com/b-wagn/collectiveBallsInBins.)}{ https://github.com/b-wagn/collectiveBallsInBins.} $$

Results. We present our some of our simulation results in Figures 4 and 5. We briefly want to discuss them here. First, consider Figure 4. The figure shows how the failure probability  $ p $, i.e., the probability of having less than  $ K $ non-empty bins out of  $ N $ bins in total, relates to the total number of samples  $ \ell \cdot Q $. We see that both for collecting quarter and half of the bins, the failure probability rapidly decreases when the number of samples is slightly more than  $ K $. For collecting three quarters, we see that we need about  $ 2K $ samples to reach that point, which fits our intuition. Comparing the different samplers, we see that for sampling uniformly range in which the failure probability decreases is smaller than for segment sampling.

Second, consider Figure 5. The figure shows how many samples we need to get the failure probability p below a fixed threshold. Again, we see that segment sampling with a large segment size Q = 32 leads to worse results. Namely, to get p below the threshold, we need significantly more samples than for uniform sampling with and without replacement. Segment sampling with a small segment size Q = 8 has only a minimal impact. Also, Figure 5 shows that there is almost no difference between sampling with replacement and sampling without replacement. We expect the difference to grow when Q approaches K. For all samplers, Figure 5 suggests that the number of samples is linear in the number of bins N, which is in line with our analytical results in Section 6.2.

Conclusion. Our simulation suggests that sampling without replacement does not perform significantly better than sampling with replacement. As sampling with replacement is much easier to implement efficiently, we may disregard sampling without replacement. Segment sampling with small segment sizes seems to lead only to a minimal loss in quality. Due to its reduced randomness complexity, the improved locality, and ease of implementation, it qualifies a good choice in practice.

<div style="text-align: center;"><img src="images/HAS23 - Fig 4 - Evaluation of different DAS constructions.jpg" alt="Image" width="68%" /></div>


<div style="text-align: center;"><div style="text-align: center;">Figure 4: Simulation results for the failure probability p, i.e., the probability of having less than K non-empty bins out of N bins in total after  $ \ell $ players threw Q balls into the bins according to the given index sampler.</div> </div>


<div style="text-align: center;"><img src="images/HAS23 - Fig 5 - DAS Evaluation continues.jpg" alt="Image" width="70%" /></div>


<div style="text-align: center;"><div style="text-align: center;">Figure 5: Simulation results for the total number of samples  $ \ell \cdot Q $ needed to get  $ p \leq 0.001 $, where p is the failure probability, i.e., the probability of having less than K non-empty bins out of N bins in total after  $ \ell $ players threw Q balls into the bins according to the given index sampler.</div> </div>


### K Script for Parameter Computation

Listing 1: Python script to compute the parameters for different codes. A discussion is given in Section 10.

from dataclasses import dataclass
import math

# Statistical Security Parameter for Soundness
SECPAR_SOUND = 40

# Dataclass
class Code:
    size_msg_symbol: int  # size of one symbol in the message
    size_code_symbol: int  # size of one symbol in the code
    msg_len: int  # number of symbols in the message
    codeword_len: int  # number of symbols in the codeword
    reception: int  # number of symbols seeded to reconstruct (worst case)
    samples: int  # number of random samples to reconstruct with high probability

    def interleave(self, el1):
        return Code(
            size_msg_symbol = self.size_msg_symbol * el1,
            size_code_symbol = self.size_code_symbol * el1,
            msg_len = self.msg_len,
            codeword_len = self.codeword_len,
            reception = self.reception,
            samples = self.samples
        )

    def tensor(self, col):
        assert self.size_msg_symbol == col.size_msg_symbol
        assert self.size_code_symbol == col.size_code_symbol
        assert self.size_msg_symbol == self.size_code_symbol

        row_dist = self.codeword_len - self.reception + 1
        col_dist = col.codeword_len - col.reception + 1
        codeword_len = self.codeword_len + col.codeword_len

        Example:
        D | o o
        D | o o
        o o | o o
        o o | o o
        Where D is the data.
        The reception is 8, since 7 is not enough to reconstruct:
        o o | o x
        o o | o x
        o o | o x
        x x | x x
        Given the symbols marked with x, I cannot reconstruct the data.
        reception = codeword_len - row_dist * col_dist + 1

        To determine the number of samples, we have multiple options.
        we can use the minimum of all resulting number of samples
        Option 1: use reception and generalized coupon collector
        As reception is a "worst case bound", this may not be tight
        Option 2: use a more direct analysis.
        not being able to reconstruct
        -> there is a row we can not reconstruct
        -> union bound over all rows
        -> for fixed row, assume we can not reconstruct
        -> there is a set of t_r - 1 positions (t_r = reception in rows)
        such that all queries in that row are in that set
        -> we union bounding over all of these sets
        -> for each fixed set, the probability that
        all queries in that row are in that set is
        (1-(n_r - t_r + 1)/(n_r + n_r)) (number of samples)
        so the total probability of not being able to reconstruct is at most
        n_c * (n_r choose t_r - 1) * (1-(n_r - t_r + 1)/(n_r + n_r)) (number of samples)
        and (n_r choose t_r - 1) < (n_r * e / (t_r - 1)) (t_r - 1)

        Option 3: same as Option 2 but reversed roles
        Asymptotic example: Tensor C: F*k -> F*(2k) with itself
        Option 1 -> Omega(k*2 + sec_par) samples
        Option 2/3 -> Omega(k*2 + sec_par * k) samples

        Concretely, Option 2/3 will be tighter, especially for large k

        samples_via_reception = samples_from_reception(SECPAR_SOUND, reception, codeword_len)
        loge = math.log2(math.e)
        lognc = math.log2(col.codeword_len)
        lognr = math.log2(self.codeword_len)
        logbinnor = (self.reception - 1) * (lognr + loge - math.log2(self.reception - 1))
        loginnerr = math.log2(1:0 - (self.codeword_len - self.reception + 1) / codeword_len)
        logbinonc = (col.reception - 1) * (lognc + loge - math.log2(col.reception - 1))
        loginnerrc = math.log2(1:0 - (col.codeword_len - col.reception + 1) / codeword_len)
        samples_direct_via_rows = int(math.cell(-(lognc + logbinnor + SECPAR_SOUND) / loginnerr)
        samples_direct_via_col = int(math.cell(-(lognr + logbinonc + SECPAR_SOUND) / loginnerr)
        samples_direct = min(samples_direct_via_rows, samples_direct_via_col)
        samples = min(samples_direct, samples_via_reception)
        return Code(
            size_msg_symbol = self.size_msg_symbol,

msg_len = self.msg_len * col.msg_len,
size_code_symbol = self.size_code_symbol,
codeword_len = codeword_len,
reception = reception,
samples = samples

def __eq__(self, other):
    return (
        self.size_msg_symbol == other.size_msg_symbol
        and self.size_code_symbol == other.size_code_symbol
        and self.msg_len == other.msg_len
        and self.codeword_len == other.codeword_len
        and self.reception == other.reception
    )

    def is_identity(self):
        return (
            self.size_msg_symbol == self.size_code_symbol
            and self.msg_len == self.codeword_len
        )

    def samples_from_reception(sec_par, reception, codeword_len):
    ...
    Compute the number of samples needed to reconstruct data with probability at least 1-2^{-(sec_par)} based on the reception efficiency and a generalized coupon collector.
    Note: this may not be the tightest for all schemes (e.g. Tensor)
    ...
    # special case: if only one symbol is needed, we are done if reception == 1:
        return 1

    # special case: if all symbols are needed: just regular coupon collector if reception == codeword_len:
        n = codeword_len
        s = math.ceil((n / math.log(math.e, 2)) * (math.log(n, 2) + sec_par))
        return int(s)

    # generalized coupon collector
    delts = reception - 1
    c = delts / codeword_len
    s = math.ceil(-sec_par / math.log2(c) + (1.0 - math.log(math.e, c)) * delta)
    return int(s)

# Identity code
def makeTrivialCode(chunksize, k):
    return Code(
        size_msg_symbol = chunksize,
        msg_len = k,
        size_code_symbol = chunksize,
        codeword_len = k,
        reception = k,
        samples = samples_from_reception(SECPAR_SOUND, k, k)
    )

# Reed-Solomon Code
# Polynomial of degree k-1 over field with field element length fsize
# Evaluated at n points
def makeRSCode(fsize, k, n):
    assert k < n
    assert 2 * fsize >= n, 'no such reed-solomon code: ('
    return Code(
        size_msg_symbol = fsize,
        msg_len = k,
        size_code_symbol = fsize,
        codeword_len = n,
        reception = k,
        samples = samples_from_reception(SECPAR_SOUND, k, n)
    )

# tests
assert makeRSCode(5, 2, 4).tensor(makeRSCode(5, 2, 4)).reception == 8
assert makeRSCode(5, 2, 4).reception == 2

Listing 2: Python script to compute the parameters for different data availability sampling schemes. A discussion is given in Section 10.

#!/usr/bin/env python

import math

# Some constants.
# Sizes of group elements, field elements, and hashes in bits
BLS_FE_SIZE = 48.0 * 8.0
BLS_GE_SIZE = 48.0 * 8.0

# Let's say we use the SECP256_k1 curve
PEDERSEN_FE_SIZE = 32.0 * 8.0
PEDERSEN_GE_SIZE = 33.0 * 8.0

# Let's say we use SHA256
HASH_SIZE = 256

from dataclasses import dataclass

from codes import *

@dataclass

class Scheme:
    code: Code
        com_size: int
        opening_overhead: int
        def samples(self):

i.e. the number of random samples needed to collect
enough symbols except with small probability

return self.code.samples

def total_coms(self):
    ...
    Compute the total communication in bits.
    ...
    return self.com_per_query() • self.samples()

def comm_per_query(self):
    ...
    Compute the communication per query in bits.
    ...
    return math_log2(self.code.codeword_len) + self.opening_overhead + self.code.size_code_symbol

def encoding_size(self):
    ...
    Compute the size of the encoding in bits.
    ...
    return self.code.codeword_len • (self.opening_overhead + self.code.size_code_symbol)

def reception(self):
    ...
    Compute the reception of the code.
    ...
    return self.code.reception

def encoding_length(self):
    ...
    Compute the length of the encoding.
    ...
    return self.code.codeword_len

# Naive scheme
# Put all the data in one symbol, and let the commitment be a hash
def makeNaiveScheme(datasetize):
    return Scheme(
        code = Code(
            size_msg_symbol = datasetize,
            msg_len = 1,
            size_code_symbol = datasetize,
            codeword_len = 1,
            reception = 1,
            samples = 1
        ),
        com_size = HASH_SIZE,
        opening_overhead = 0
    )

# Merkle scheme
# Take a merkle tree and the identity code
def makeMerkleScheme(datasetize, chunksize=1024):
    k = math.ceil(datasetize / chunksize)
    return Scheme(
        code = makeTrivialCode(chunksize, k),
        con_size = HASH_SIZE,
        opening_overhead = math.ceil(math.log(k, 2)) • HASH_SIZE
    )

# KZG Commitment, interpreted as an erasure code commitment for the RS code
# The RS Code is set to have parameters k,n with n = invrate + k
def makeKZGScheme(datasetize, invrate=4):
    k = math.ceil(datasetize / BLS_FE_SIZE)
    return Scheme(
        code = makeRSCode(
            BLS_FE_SIZE,
            k,
            k • invrate
        ),
        con_size = BLS_GE_SIZE,
        opening_overhead = BLS_GE_SIZE,
    )

# Tensor Code Commitment, where each dimension is expanded with inverse rate invrate.
# That is, data is a k x k matrix, and the codeword is a n x n matrix, with n = invrate + k
# Both column and row code are RS codes.
def makeTensorScheme(datasetize, invrate=2):
    m = math.ceil(datasetize / BLS_FE_SIZE)
    k = math.ceil(math.sqrt(m))
    n = invrate * k
    rs = makeRSCode(BLS_FE_SIZE, k, n)
    return Scheme(
        code = rs.tensor(rs),
        con_size = BLS_GE_SIZE * k,
        opening_overhead = BLS_GE_SIZE,
    )

# Hash-Based Code Commitment, over field with elements of size fsize,
# parallel repetition parameters P and L. Data is treated as a k x k matrix,
# and codewords are k x n matrices, where n = k*invrate.
def makeHashBasedScheme(datasetize, fsize=32, P&S, L=64, invrate=4):
    m = math.ceil(datasetize / fsize)
    k = math.ceil(math.sqrt(m))
    n = invrate * k
    rs = makeRSCode(fsize, k, n)
    return Scheme(
        code = rs.interleave(k),
        con_size = n • HASH_SIZE + P • n • fsize + L • k • fsize,
        opening_overhead = 0,
    )

# Homomorphic Hash-Based Code Commitment

instantiated with Pedersen Hash
# parallel repetition parameters P and L. Data is treated as a k x k matrix,
# and codewords are k x n matrices, where n = k*invrate.
def makeHomHashBasedScheme(domain, P=2, L=2, invrate=4):
    m = math.ceil(domain / PEDERSEN_FE_SIZE)
    k = math.ceil(math.sqrt(m))
    n = invrate * k
    rs = makeRSCode(PEDERSEN_FE_SIZE, k, n)

    return Scheme(
        code = rs.interleave(k),
        com.size = n * PEDERSEN_GE_SIZE + P * n * PEDERSEN_FE_SIZE + L * k * PEDERSEN_FE_SIZE,
        opening_overhead = 0,
    )

##### Listing 3: Python script to compute the tables in Section 10.

!!/usr/bin/env python

import math
import sys
from tabulate import tabulate

from schemes import *

def makeRow(name, scheme, tex):
    comsize = '(:.2f)'.format(round(scheme.com_size/8000.0,2))
    encodingsize = '(:.2f)'.format(round(scheme.encoding_size() / 8000000.0,2))
    compqsize = '(:.2f)'.format(round(scheme.com_per_query() / 8000.0,2))
    reception = scheme.reception()
    encodinglength = scheme.encoding_length()
    samples = scheme.samples()
    comsize = '(:.2f)'.format(round(scheme.total_com() / 8000000.0,2))
    if tex:
        row = ["\Inst*name,comsize,encodingsize,compqsize,samples,comsize]
    else:
        row = [name,comsize,encodingsize,compqsize,(reception,encodinglength),samples,comsize]
    return row

*****

opts = [opt for opt in sys.argv[1:] if opt.startswith("")]
args = [arg for arg in sys.argv[1:] if not arg.startswith("")]

if len(args) == 0:
    print("Missing Argument: Datasize in Negabytes.")
    print("Hint: To print the table in LaTeX code, add the option -1.")
    sys.exit(-1)

datasize = int(args[0]) + 8000000

# Print to LaTeX
tex = "-1" in opts

if tex:
    table = ["Name," | com|", |Encoding|", Comm. p. Q.","Samples","Comm Total"]
else:
    table = ["Name," | com| [KB)," | Encoding| [MB]","Comm. p. Q. [KB)," | Reception", "Samples","Comm Total [MB]"]

scheme = makeNaiveScheme(datasize)
table.append(makeRow("Naive", scheme, tex))

scheme = makeMerkleScheme(datasize)
table.append(makeRow("Merkle", scheme, tex))

scheme = makeKZGScheme(datasize)
table.append(makeRow("RS", scheme, tex))

scheme = makeTensorScheme(datasize)
table.append(makeRow("Tensor", scheme, tex))

scheme = makeHashBasedScheme(datasize)
table.append(makeRow("Hash", scheme, tex))

scheme = makeHomHashBasedScheme(datasize)
table.append(makeRow("HomHash", scheme, tex))

if tex:
    print(tabulate(table, headers='firstrow', tablefont='latex_raw', disable_numparse=True))
else:
    print(tabulate(table, headers='firstrow', tablefont='fancy_grid'))

##### Listing 4: Python script to compute the graphs in Section 10.

#!/usr/bin/env python

import math
import sys
import csv
import os

from schemes import *

DATASIZEUNIT = 8000*1000  # Megabytes
DATASIZERANGE = range(1,156,15)

def writeCSV(path,d):
    with open(path, mode="w") as outfile:
        writer = csv.writer(outfile, delimiter='')
        for x in d:
            writer.writerow([x,d[x]])

# Writes the graphs for a given scheme

into a csv file
def writeScheme(name, makeScheme):
    commitment = {}
    compqp = {}
    commtotal = {}
    encoding = {}
    for s in DATASIZERANGE:
        datasize = s.DATASIZEUNIT
        scheme = makeScheme(datasize)
        commitment[s] = scheme.com_size / 8000000  # MB
        compqp[s] = scheme.com_per_query() / 8000  # KB
        commtotal[s] = scheme.total_com() / 800000000  # GB
        encoding[s] = scheme.encoding_size() / 8000000000  # GB

    if not os.path.exists("./csvdata/"):
        os.makedirs(*./csvdata/*):
            writeCSV(*./csvdata/*+name+".com.csv",commitment)
        writeCSV(*./csvdata/*+name+".com.pq.csv",comppq)
        writeCSV(*./csvdata/*+name+".comn.total.csv",commtotal)
        writeCSV(*./csvdata/*+name+".encoding.csv",encoding)

writeScheme("rs", makeKZGScheme)
writeScheme("tensor", makeTensorScheme)
writeScheme("hash", makeHashBasedScheme)
writeScheme("homhash", makeHomHashBasedScheme)
