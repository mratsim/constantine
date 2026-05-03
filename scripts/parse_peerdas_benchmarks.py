#!/usr/bin/env python3
"""
Parse PeerDAS (EIP-7594) and EIP-4844 benchmark files and generate a single markdown comparison table.

Usage:
    python3 parse_peerdas_benchmarks.py
"""

import re
from pathlib import Path

def parse_constantine_eip4844(filepath):
    """Parse constantine EIP-4844 benchmark file."""
    results = {}
    with open(filepath, 'r') as f:
        for line in f:
            match = re.search(r'^(verify_blob_kzg_proof \(batch (\d+)\)|\w+)\s+serial\s+\d+\.\d+\s+ops/s\s+(\d+)\s+ns/op', line)
            if match:
                bench_name = match.group(1)
                ns_op = int(match.group(3))
                if bench_name.startswith('verify_blob_kzg_proof (batch'):
                    batch_num = match.group(2)
                    results[f'verify_blob_kzg_proof_batch {batch_num}'] = ns_op
                else:
                    results[bench_name] = ns_op
    return results

def parse_constantine_eip7594(filepath):
    """Parse constantine EIP-7594 (PeerDAS) benchmark file."""
    results = {}
    with open(filepath, 'r') as f:
        for line in f:
            match = re.search(r'^compute_cells \(half-FFT optimization\)\s+\d+\.\d+\s+ops/s\s+(\d+)\s+ns/op', line)
            if match:
                results['compute_cells'] = int(match.group(1))
            
            match = re.search(r'^compute_cells_and_kzg_proofs \(FK20\)\s+\d+\.\d+\s+ops/s\s+(\d+)\s+ns/op', line)
            if match:
                results['compute_cells_and_kzg_proofs'] = int(match.group(1))
            
            match = re.search(r'^recover_cells_and_kzg_proofs \(50% availability', line)
            if match:
                ns_match = re.search(r'(\d+)\s+ns/op', line)
                if ns_match:
                    results['recover_cells_and_kzg_proofs'] = int(ns_match.group(1))
            
            match = re.search(r'^verify_cell_kzg_proof_batch \(count=(\d+), 1 blob\)\s+\d+\.\d+\s+ops/s\s+(\d+)\s+ns/op', line)
            if match:
                count = int(match.group(1))
                results[f'verify_cell_kzg_proof_batch_{count}'] = int(match.group(2))
            
            match = re.search(r'^verify_cell_kzg_proof_batch \(128 cells, (\d+) blobs\)\s+\d+\.\d+\s+ops/s\s+(\d+)\s+ns/op', line)
            if match:
                blobs = int(match.group(1))
                results[f'verify_cell_kzg_proof_batch_128c_{blobs}b'] = int(match.group(2))
    
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
    with open(filepath, 'r') as f:
        for line in f:
            match = re.search(r'^Benchmark/ComputeCells\s+\d+\s+(\d+)\s+ns/op', line)
            if match:
                results['compute_cells'] = int(match.group(1))
            
            for i in range(9):
                match = re.search(rf'^Benchmark/ComputeCellsAndKZGProofs\(precompute={i}\)\s+\d+\s+(\d+)\s+ns/op', line)
                if match:
                    results[f'compute_cells_and_kzg_proofs_pre{i}'] = int(match.group(1))
            
            match = re.search(r'^Benchmark/RecoverCellsAndKZGProofs\(missing=50\.0%\)\s+\d+\s+(\d+)\s+ns/op', line)
            if match:
                results['recover_cells_and_kzg_proofs'] = int(match.group(1))
            
            match = re.search(r'^Benchmark/VerifyCellKZGProofBatch\s+\d+\s+(\d+)\s+ns/op', line)
            if match:
                results['verify_cell_kzg_proof_batch_serial'] = int(match.group(1))
            
            match = re.search(r'^Benchmark/VerifyCellKZGProofBatchParallel\s+\d+\s+(\d+)\s+ns/op', line)
            if match:
                results['verify_cell_kzg_proof_batch_parallel'] = int(match.group(1))
    
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
    lines = []
    lines.append("# KZG Benchmark Comparison: c-kzg-4844 vs constantine")
    lines.append("")
    lines.append("All benchmarks run on **Intel(R) Core(TM) Ultra 7 265K** (serial).")
    lines.append("")
    lines.append("|             Bench              | c-kzg-4844 (serial) | constantine (serial) |    Δ%    |")
    lines.append("|:------------------------------:|:-------------------:|:--------------------:|:--------:|")
    
    # EIP-4844 benchmarks
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
        
        ckzg_str = f"{ns_to_ms(ckzg_val):.3f} ms" if ckzg_val else "-"
        const_str = f"{ns_to_ms(const_val):.3f} ms" if const_val else "-"
        
        if ckzg_val and const_val:
            pct = calc_pct_diff(ckzg_val, const_val)
            pct_str = f"{pct:+.1f}%"
        else:
            pct_str = "-"
        
        lines.append(f"| {display_name:<30} | {ckzg_str:>19} | {const_str:>20} | {pct_str:>8} |")
    
    # PeerDAS benchmarks
    lines.append("| **PeerDAS (EIP-7594)**               |                     |                      |          |")
    
    # compute_cells
    ckzg_val = ckzg_peerdas.get('compute_cells')
    const_val = const_peerdas.get('compute_cells')
    ckzg_str = f"{ns_to_ms(ckzg_val):.3f} ms" if ckzg_val else "-"
    const_str = f"{ns_to_ms(const_val):.3f} ms" if const_val else "-"
    pct = calc_pct_diff(ckzg_val, const_val) if ckzg_val and const_val else None
    pct_str = f"{pct:+.1f}%" if pct is not None else "-"
    lines.append(f"| compute_cells                    | {ckzg_str:>19} | {const_str:>20} | {pct_str:>8} |")
    
    # compute_cells_and_kzg_proofs - multiple precompute levels
    for pre in [0, 2, 4, 8]:
        ckzg_val = ckzg_peerdas.get(f'compute_cells_and_kzg_proofs_pre{pre}')
        if pre == 0:
            const_val = const_peerdas.get('compute_cells_and_kzg_proofs')
            const_str = f"{ns_to_ms(const_val):.3f} ms" if const_val else "-"
            pct = calc_pct_diff(ckzg_val, const_val) if ckzg_val and const_val else None
            pct_str = f"{pct:+.1f}%" if pct is not None else "-"
            lines.append(f"| compute_cells_and_kzg_proofs (pre={pre}) | {f'{ns_to_ms(ckzg_val):.3f} ms':>19} | {const_str:>20} | {pct_str:>8} |")
        else:
            ckzg_str = f"{ns_to_ms(ckzg_val):.3f} ms" if ckzg_val else "-"
            lines.append(f"| compute_cells_and_kzg_proofs (pre={pre}) | {ckzg_str:>19} | {'-':>20} | {'-':>8} |")
    
    # recover_cells_and_kzg_proofs - pre=0 and pre=8
    for pre in [0, 8]:
        if pre == 8:
            ckzg_val = ckzg_peerdas.get('recover_cells_and_kzg_proofs')
            ckzg_str = f"{ns_to_ms(ckzg_val):.3f} ms" if ckzg_val else "-"
            lines.append(f"| recover_cells_and_kzg_proofs¹ (pre={pre}) | {ckzg_str:>19} | {'-':>20} | {'-':>8} |")
        else:
            const_val = const_peerdas.get('recover_cells_and_kzg_proofs')
            const_str = f"{ns_to_ms(const_val):.3f} ms" if const_val else "-"
            lines.append(f"| recover_cells_and_kzg_proofs¹ (pre={pre}) | {'-':>19} | {const_str:>20} | {'-':>8} |")
    
    # verify_cell_kzg_proof_batch (64 blobs = 8192 cells)
    ckzg_val = ckzg_peerdas.get('verify_cell_kzg_proof_batch_serial')
    const_val = const_peerdas.get('verify_cell_kzg_proof_batch_128c_64b')
    ckzg_str = f"{ns_to_ms(ckzg_val):.3f} ms" if ckzg_val else "-"
    const_str = f"{ns_to_ms(const_val):.3f} ms" if const_val else "-"
    pct = calc_pct_diff(ckzg_val, const_val) if ckzg_val and const_val else None
    pct_str = f"{pct:+.1f}%" if pct is not None else "-"
    lines.append(f"| verify_cell_kzg_proof_batch²     | {ckzg_str:>19} | {const_str:>20} | {pct_str:>8} |")
    
    lines.append("")
    lines.append("**Notes:**")
    lines.append("- ¹ Recovery: c-kzg-4844 uses precompute=8 (96 MiB); constantine has no precompute")
    lines.append("- ² c-kzg-4844 verifies 8192 cells (64 blobs); constantine matches this config")
    lines.append("- Δ% shows constantine relative to c-kzg-4844 (negative = faster)")
    lines.append("- Precompute=8 trades 96 MiB memory for ~34% speedup in FK20 operations")
    lines.append("")
    lines.append("## Source Files")
    lines.append("")
    lines.append("- c-kzg-4844: `c-kzg-4844/bindings/go/bench_i7_265K.txt`")
    lines.append("- constantine EIP-4844: `constantine/benchmarks/bench_eip4844.txt`")
    lines.append("- constantine PeerDAS: `constantine/benchmarks/bench_eip7594.txt`")
    
    content = "\n".join(lines)
    if output_path:
        with open(output_path, 'w') as f:
            f.write(content)
    return content

def main():
    constantine_file = Path("constantine/benchmarks/bench_eip4844.txt")
    constantine_peerdas_file = Path("constantine/benchmarks/bench_eip7594.txt")
    c_kzg_file = Path("c-kzg-4844/bindings/go/bench_i7_265K.txt")
    output_file = Path("kzg_benchmark_comparison.md")
    
    print(f"Parsing constantine EIP-4844: {constantine_file}")
    print(f"Parsing constantine PeerDAS: {constantine_peerdas_file}")
    print(f"Parsing c-kzg-4844: {c_kzg_file}")
    print()
    
    const_eip4844 = parse_constantine_eip4844(constantine_file)
    const_peerdas = parse_constantine_eip7594(constantine_peerdas_file)
    ckzg_eip4844 = parse_c_kzg_go_eip4844(c_kzg_file)
    ckzg_peerdas = parse_c_kzg_go_peerdas(c_kzg_file)
    
    content = generate_report(const_eip4844, const_peerdas, ckzg_eip4844, ckzg_peerdas, output_file)
    print(f"Report written to: {output_file}")
    print()
    print(content)

if __name__ == '__main__':
    main()