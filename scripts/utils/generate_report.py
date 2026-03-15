#!/usr/bin/env python3
"""
Post-process pVACseq output: extract top-N neoantigens, generate report
and ColabFold input file. No external dependencies — stdlib only.
"""

import csv
import sys
import os
from pathlib import Path


# Columns to include in the final report
REPORT_COLUMNS = [
    ("Rank", None),
    ("Gene Name", "Gene"),
    ("HLA Allele", "HLA_Allele"),
    ("MT Epitope Seq", "Mutant_Peptide"),
    ("Median MT IC50 Score", "IC50_nM"),
    ("Median MT Percentile", "Percentile"),
    ("WT Epitope Seq", "WT_Peptide"),
    ("Corresponding Fold Change", "Fold_Change"),
    ("Tumor DNA VAF", "Tumor_VAF"),
    ("Gene Expression", "Expression"),
    ("Chromosome", "Chr"),
    ("Start", "Position"),
    ("Variant Type", "Variant_Type"),
]


def load_pvacseq_tsv(path):
    """Read pVACseq filtered TSV and return list of dicts."""
    rows = []
    with open(path, newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            rows.append(row)
    return rows


def sort_by_binding(rows):
    """Sort by Median MT IC50 Score ascending (strongest binders first)."""
    def key(row):
        try:
            return float(row.get("Median MT IC50 Score", "999999"))
        except (ValueError, TypeError):
            return 999999.0
    return sorted(rows, key=key)


def write_top_n_tsv(rows, n, output_path):
    """Write top-N neoantigens TSV."""
    top = rows[:n]
    headers = [alias or src for src, alias in REPORT_COLUMNS]

    with open(output_path, "w", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(headers)
        for i, row in enumerate(top, 1):
            out_row = [str(i)]  # Rank
            for src, _ in REPORT_COLUMNS[1:]:
                out_row.append(row.get(src, "N/A"))
            writer.writerow(out_row)
    return top


def write_colabfold_input(top_rows, output_path):
    """Generate FASTA file with peptide sequences for ColabFold."""
    with open(output_path, "w") as f:
        for i, row in enumerate(top_rows, 1):
            gene = row.get("Gene Name", "unknown")
            peptide = row.get("MT Epitope Seq", "")
            hla = row.get("HLA Allele", "")
            f.write(f">{gene}_rank{i}_{hla}\n")
            f.write(f"{peptide}\n")


def print_summary(top_rows):
    """Print human-readable summary to stdout."""
    print("")
    print("=" * 80)
    print("  TOP NEOANTIGEN CANDIDATES")
    print("=" * 80)
    print(f"{'Rank':<5} {'Gene':<12} {'HLA Allele':<16} {'Peptide':<14} {'IC50 nM':<10} {'%ile':<8}")
    print("-" * 80)
    for i, row in enumerate(top_rows, 1):
        gene = row.get("Gene Name", "?")[:11]
        hla = row.get("HLA Allele", "?")[:15]
        pep = row.get("MT Epitope Seq", "?")[:13]
        ic50 = row.get("Median MT IC50 Score", "?")
        pct = row.get("Median MT Percentile", "?")
        print(f"{i:<5} {gene:<12} {hla:<16} {pep:<14} {ic50:<10} {pct:<8}")
    print("=" * 80)
    print("")


def main():
    if len(sys.argv) < 2:
        print("Usage: generate_report.py <pvacseq_filtered.tsv> [top_n] [output_dir]")
        sys.exit(1)

    input_path = sys.argv[1]
    top_n = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    output_dir = sys.argv[3] if len(sys.argv) > 3 else os.path.dirname(input_path)

    if not os.path.isfile(input_path):
        print(f"ERROR: File not found: {input_path}")
        sys.exit(1)

    Path(output_dir).mkdir(parents=True, exist_ok=True)

    rows = load_pvacseq_tsv(input_path)
    if not rows:
        print("WARNING: No neoantigens found in the input file.")
        sys.exit(0)

    sorted_rows = sort_by_binding(rows)

    tsv_out = os.path.join(output_dir, "top10_neoantigens.tsv")
    top = write_top_n_tsv(sorted_rows, top_n, tsv_out)
    print(f"Wrote {len(top)} neoantigens to: {tsv_out}")

    fasta_out = os.path.join(output_dir, "colabfold_input.fasta")
    write_colabfold_input(top, fasta_out)
    print(f"Wrote ColabFold input to: {fasta_out}")

    print_summary(top)

    print("Next step: Open notebooks/colabfold_neoantigen_structures.ipynb in Google Colab")
    print("           to predict 3D structures of these peptide-MHC complexes.")


if __name__ == "__main__":
    main()
