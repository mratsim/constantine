#!/usr/bin/env python3
"""
Parse PeerDAS (EIP-7594) and EIP-4844 benchmark files and generate a single markdown comparison table.

Usage:
    python3 scripts/parse_peerdas_benchmarks.py
"""

import re
from pathlib import Path


# c-kzg-4844 precompute memory sizes from README
CKZG_PRECOMP_MEM = {
    0: "0 KiB", 1: "768 KiB", 2: "1536 KiB", 3: "3 MiB",
    4: "6 MiB", 5: "12 MiB", 6: "24 MiB", 7: "48 MiB",
    8: "96 MiB", 9: "192 MiB", 10: "384 MiB", 11: "768 MiB",
    12: "1536 MiB", 13: "3 GiB", 14: "6 GiB", 15: "12 GiB",
}


def parse_constantine_eip4844(filepath):
    """Parse constantine EIP-4844 benchmark file (new format with 'serial' keyword)."""
    results = {}
    with open(filepath, 'r') as f:
        for line in f:
            match = re.search(r'^(\w+(?:\s+\(batch\s+\d+\))?)\s+serial\s+[\d.]+\s+ops/s\s+(\d+)\s+ns/op', line)
            if match:
                bench_name = match.group(1).strip()
                ns_op = int(match.group(2))
                if bench_name.startswith('verify_blob_kzg_proof (batch'):
                    batch_num = re.search(r'batch\s+(\d+)', bench_name).group(1)
                    results[f'verify_blob_kzg_proof_batch {batch_num}'] = ns_op
                elif bench_name == 'blob_to_kzg_commitment':
                    results['blob_to_kzg_commitment'] = ns_op
                elif bench_name == 'compute_kzg_proof':
                    results['compute_kzg_proof'] = ns_op
                elif bench_name == 'compute_blob_kzg_proof':
                    results['compute_blob_kzg_proof'] = ns_op
                elif bench_name == 'verify_kzg_proof':
                    results['verify_kzg_proof'] = ns_op
                elif bench_name == 'verify_blob_kzg_proof':
                    results['verify_blob_kzg_proof'] = ns_op
    return results


def parse_constantine_eip7594(filepath):
    """Parse constantine EIP-7594 (PeerDAS) benchmark file (new format)."""
    results = {}
    compute_rows = []
    with open(filepath, 'r') as f:
        for line in f:
            # compute_cells (half-FFT optimization)
            match = re.search(r'^compute_cells \(half-FFT optimization\)\s+[\d.]+\s+ops/s\s+(\d+)\s+ns/op', line)
            if match:
                results['compute_cells'] = int(match.group(1))

            # compute_cells_and_kzg_proofs (no precompute, 1.8 MiB)
            match = re.search(r'^compute_cells_and_kzg_proofs \(no precompute,([^)]*)\)\s+[\d.]+\s+ops/s\s+(\d+)\s+ns/op', line)
            if match:
                mem = match.group(1).strip()
                compute_rows.append(('no precompute', mem, int(match.group(2))))
                continue

            # compute_cells_and_kzg_proofs (t= 64, b= 6, ~   32.2 MiB)
            match = re.search(r'^compute_cells_and_kzg_proofs \(t=(\s*\d+), b=(\s*\d+), ~([^\)]*)\)\s+[\d.]+\s+ops/s\s+(\d+)\s+ns/op', line)
            if match:
                t = match.group(1).strip()
                b = match.group(2).strip()
                mem = match.group(3).strip()
                compute_rows.append((f't={t}, b={b}', mem, int(match.group(4))))
                continue

            # recover_cells_and_kzg_proofs (50% cells)
            match = re.search(r'^recover_cells_and_kzg_proofs \(50%', line)
            if match:
                ns_match = re.search(r'(\d+)\s+ns/op', line)
                if ns_match:
                    results['recover_cells_and_kzg_proofs'] = int(ns_match.group(1))
                continue

            # verify_cell_kzg_proof_batch (128 cells, N blobs)
            match = re.search(r'^verify_cell_kzg_proof_batch \(128 cells, (\d+) blobs\)\s+[\d.]+\s+ops/s\s+(\d+)\s+ns/op', line)
            if match:
                blobs = int(match.group(1))
                results[f'verify_cell_kzg_proof_batch_128c_{blobs}b'] = int(match.group(2))

    results['_compute_rows'] = compute_rows
    return results


def parse_c_kzg_go_eip4844(filepath):
    """Parse c-kzg-4844 Go bindings EIP-4844 benchmarks."""
    results = {}
    with open(filepath, 'r') as f:
        for line in f:
            match = re.search(r'^Benchmark/(\w+(?:\([^)]+\))?)\s+\d+\s+(\d+)\s+ns/op', line)
            if match:
                bench_name = match.group(1)
                ns_op = int(match.group(2))

                if bench_name == 'BlobToKZGCommitment':
                    results['blob_to_kzg_commitment'] = ns_op
                elif bench_name == 'ComputeKZGProof':
                    results['compute_kzg_proof'] = ns_op
                elif bench_name == 'ComputeBlobKZGProof':
                    results['compute_blob_kzg_proof'] = ns_op
                elif bench_name == 'VerifyKZGProof':
                    results['verify_kzg_proof'] = ns_op
                elif bench_name == 'VerifyBlobKZGProof':
                    results['verify_blob_kzg_proof'] = ns_op
                elif bench_name.startswith('VerifyBlobKZGProofBatch(count='):
                    count = re.search(r'count=(\d+)', bench_name).group(1)
                    results[f'verify_blob_kzg_proof_batch {count}'] = ns_op
                elif bench_name.startswith('LoadTrustedSetupFile(precompute='):
                    precomp = re.search(r'precompute=(\d+)', bench_name).group(1)
                    if precomp == '0':
                        results['precompute_load'] = ns_op
    return results


def parse_c_kzg_go_peerdas(filepath):
    """Parse c-kzg-4844 Go bindings PeerDAS benchmarks."""
    results = {}
    compute_rows = []
    with open(filepath, 'r') as f:
        for line in f:
            match = re.search(r'^Benchmark/ComputeCells\s+\d+\s+(\d+)\s+ns/op', line)
            if match:
                results['compute_cells'] = int(match.group(1))

            match = re.search(r'^Benchmark/ComputeCellsAndKZGProofs\(precompute=(\d+)\)\s+\d+\s+(\d+)\s+ns/op', line)
            if match:
                pre = int(match.group(1))
                mem = CKZG_PRECOMP_MEM.get(pre, "?")
                compute_rows.append((f'precomp={pre}', mem, int(match.group(2))))
                continue

            match = re.search(r'^Benchmark/RecoverCellsAndKZGProofs\(missing=50\.0%\)\s+\d+\s+(\d+)\s+ns/op', line)
            if match:
                results['recover_cells_and_kzg_proofs'] = int(match.group(1))

            match = re.search(r'^Benchmark/VerifyCellKZGProofBatch\s+\d+\s+(\d+)\s+ns/op', line)
            if match:
                results['verify_cell_kzg_proof_batch_serial'] = int(match.group(1))

    results['_compute_rows'] = compute_rows
    return results


def ns_to_ms(ns):
    """Convert nanoseconds to milliseconds with 3 decimal places."""
    return ns / 1_000_000


def calc_pct_diff(val1, val2):
    """Calculate percentage difference: (val2 - val1) / val1 * 100."""
    if val1 == 0:
        return 0
    return ((val2 - val1) / val1) * 100


def generate_report(const_eip4844, const_peerdas, ckzg_eip4844, ckzg_peerdas, output_path=None):
    """Generate single markdown table with all benchmarks."""
    EM = "\u2014"  # em dash
    lines = []

    lines.append("| Benchmark              | Precompute          | c-kzg-4844 (serial) | constantine (serial) |   \u0394%    |")
    lines.append("|:-----------------------|:--------------------|:-------------------:|:--------------------:|:-------:|")

    # EIP-4844 benchmarks (no precompute column needed)
    eip4844_benches = [
        ('blob_to_kzg_commitment', 'blob_to_kzg_commitment'),
        ('compute_kzg_proof', 'compute_kzg_proof'),
        ('compute_blob_kzg_proof', 'compute_blob_kzg_proof'),
        ('verify_kzg_proof', 'verify_kzg_proof'),
        ('verify_blob_kzg_proof', 'verify_blob_kzg_proof'),
        ('verify_blob_kzg_proof_batch 1', 'verify_blob_kzg_proof_batch 1'),
        ('verify_blob_kzg_proof_batch 2', 'verify_blob_kzg_proof_batch 2'),
        ('verify_blob_kzg_proof_batch 4', 'verify_blob_kzg_proof_batch 4'),
        ('verify_blob_kzg_proof_batch 8', 'verify_blob_kzg_proof_batch 8'),
        ('verify_blob_kzg_proof_batch 16', 'verify_blob_kzg_proof_batch 16'),
        ('verify_blob_kzg_proof_batch 32', 'verify_blob_kzg_proof_batch 32'),
        ('verify_blob_kzg_proof_batch 64', 'verify_blob_kzg_proof_batch 64'),
        ('precompute_load (L0)', 'precompute_load'),
    ]

    for display_name, key in eip4844_benches:
        ckzg_val = ckzg_eip4844.get(key)
        const_val = const_eip4844.get(key)

        ckzg_str = f"{ns_to_ms(ckzg_val):.3f} ms" if ckzg_val else EM
        const_str = f"{ns_to_ms(const_val):.3f} ms" if const_val else EM

        if ckzg_val and const_val:
            pct = calc_pct_diff(ckzg_val, const_val)
            pct_str = f"{pct:+.1f}%"
        else:
            pct_str = EM

        lines.append(f"| {display_name:<21} | {EM:<19} | {ckzg_str:>19} | {const_str:>20} | {pct_str:>8} |")

    # PeerDAS section header
    lines.append("| **PeerDAS (EIP-7594)**     |                     |                     |                      |         |")

    # compute_cells
    ckzg_val = ckzg_peerdas.get('compute_cells')
    const_val = const_peerdas.get('compute_cells')
    ckzg_str = f"{ns_to_ms(ckzg_val):.3f} ms" if ckzg_val else EM
    const_str = f"{ns_to_ms(const_val):.3f} ms" if const_val else EM
    pct = calc_pct_diff(ckzg_val, const_val) if ckzg_val and const_val else None
    pct_str = f"{pct:+.1f}%" if pct is not None else EM
    lines.append(f"| compute_cells              | {EM:<19} | {ckzg_str:>19} | {const_str:>20} | {pct_str:>8} |")

    # extract compute rows
    ckzg_rows = ckzg_peerdas.get('_compute_rows', [])
    const_rows = const_peerdas.get('_compute_rows', [])

    # --- compare ckzg precomp=0 vs ctt no-precompute directly ---
    ckzg_pre0 = None
    ckzg_other_rows = []
    for label, mem, ns_val in ckzg_rows:
        if 'precomp=0' in label:
            ckzg_pre0 = (mem, ns_val)
        else:
            ckzg_other_rows.append((label, mem, ns_val))

    ctt_nopre = None
    ctt_other_rows = []
    for label, mem, ns_val in const_rows:
        if 'no precompute' in label:
            ctt_nopre = (mem, ns_val)
        else:
            ctt_other_rows.append((label, mem, ns_val))

    # Direct comparison: no precompute
    if ckzg_pre0 and ctt_nopre:
        _, ckzg_ns = ckzg_pre0
        ctt_mem, ctt_ns = ctt_nopre
        ckzg_str = f"{ns_to_ms(ckzg_ns):.3f} ms"
        const_str = f"{ns_to_ms(ctt_ns):.3f} ms"
        pct = calc_pct_diff(ckzg_ns, ctt_ns)
        pct_str = f"{pct:+.1f}%"
        lines.append(f"| compute_cells_and_kzg_proofs   | no precomp           | {ckzg_str:>19} | {const_str:>20} | {pct_str:>8} |")

    # ckzg-only rows
    for label, mem, ns_val in ckzg_other_rows:
        ckzg_str = f"{ns_to_ms(ns_val):.3f} ms"
        lines.append(f"| compute_cells_and_kzg_proofs | ckzg {label}, {mem:<14} | {ckzg_str:>19} | {EM:>20} | {EM:>8} |")

    # ctt-only rows
    for label, mem, ns_val in ctt_other_rows:
        const_str = f"{ns_to_ms(ns_val):.3f} ms"
        lines.append(f"| compute_cells_and_kzg_proofs | ctt {label}, {mem:<15} | {EM:>19} | {const_str:>20} | {EM:>8} |")

    # recover_cells_and_kzg_proofs
    ckzg_val = ckzg_peerdas.get('recover_cells_and_kzg_proofs')
    const_val = const_peerdas.get('recover_cells_and_kzg_proofs')
    ckzg_str = f"{ns_to_ms(ckzg_val):.3f} ms" if ckzg_val else EM
    const_str = f"{ns_to_ms(const_val):.3f} ms" if const_val else EM
    if ckzg_val and const_val:
        pct = calc_pct_diff(ckzg_val, const_val)
        pct_str = f"{pct:+.1f}%"
    else:
        pct_str = EM
    lines.append(f"| recover_cells_and_kzg_proofs¹ | see ¹                | {ckzg_str:>19} | {const_str:>20} | {pct_str:>8} |")

    # verify_cell_kzg_proof_batch (128 cells, 64 blobs)
    ckzg_val = ckzg_peerdas.get('verify_cell_kzg_proof_batch_serial')
    const_val = const_peerdas.get('verify_cell_kzg_proof_batch_128c_64b')
    ckzg_str = f"{ns_to_ms(ckzg_val):.3f} ms" if ckzg_val else EM
    const_str = f"{ns_to_ms(const_val):.3f} ms" if const_val else EM
    pct = calc_pct_diff(ckzg_val, const_val) if ckzg_val and const_val else None
    pct_str = f"{pct:+.1f}%" if pct is not None else EM
    lines.append(f"| verify_cell_kzg_proof_batch\u00b2 | {EM:<19} | {ckzg_str:>19} | {const_str:>20} | {pct_str:>8} |")

    lines.append("")
    lines.append("**Notes:**")
    lines.append("- \u00b9 Recovery: c-kzg-4844 uses precompute=8 (96 MiB); constantine uses t=256, b=8 (24 MiB)")
    lines.append("- \u00b2 c-kzg-4844 verifies 8192 cells (64 blobs); constantine matches this config")
    lines.append("- \u0394% shows constantine relative to c-kzg-4844 (negative = faster)")
    lines.append("- c-kzg-4844 precompute levels and constantine (t, b) configs are not directly comparable")
    lines.append("- Precompute=8 (c-kzg-4844) trades 96 MiB memory for ~34% speedup in FK20 operations")
    lines.append("")
    lines.append("## Source Files")
    lines.append("")
    lines.append("- c-kzg-4844: `benchmarks/ckzg4844_bench_i7_265K.txt`")
    lines.append("- constantine EIP-4844: `benchmarks/ctt_kzg_bench.txt`")
    lines.append("- constantine PeerDAS: `benchmarks/ctt_peerdas_bench.txt`")

    content = "\n".join(lines)
    if output_path:
        with open(output_path, 'w') as f:
            f.write(content)
    return content


def main():
    ctt_kzg_file = Path("benchmarks/ctt_kzg_bench.txt")
    ctt_peerdas_file = Path("benchmarks/ctt_peerdas_bench.txt")
    ckzg_file = Path("benchmarks/ckzg4844_bench_i7_265K.txt")
    output_file = Path("bench-results.md")

    print(f"Parsing constantine EIP-4844: {ctt_kzg_file}")
    print(f"Parsing constantine PeerDAS: {ctt_peerdas_file}")
    print(f"Parsing c-kzg-4844: {ckzg_file}")
    print()

    const_eip4844 = parse_constantine_eip4844(ctt_kzg_file)
    const_peerdas = parse_constantine_eip7594(ctt_peerdas_file)
    ckzg_eip4844 = parse_c_kzg_go_eip4844(ckzg_file)
    ckzg_peerdas = parse_c_kzg_go_peerdas(ckzg_file)

    content = generate_report(const_eip4844, const_peerdas, ckzg_eip4844, ckzg_peerdas, output_file)
    print(f"Report written to: {output_file}")
    print()
    print(content)


if __name__ == '__main__':
    main()
