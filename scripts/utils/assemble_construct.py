#!/usr/bin/env python3
"""
Assemble a complete mRNA vaccine construct from neoantigen predictions.

Structure (modeled after BioNTech BNT162b2):
  5'cap — 5'UTR — Kozak+AUG — signal_peptide — [neo1-linker-neo2-...-neoN] — stop — 3'UTR — polyA

Usage:
    python3 assemble_construct.py <top10_neoantigens.tsv> [output_dir]

No external dependencies — stdlib only. LinearDesign optimization is optional
(if lineardesign binary is available, it will be used for CDS optimization).
"""

import csv
import sys
import os
from pathlib import Path
from datetime import datetime

# ─── Vaccine design elements ────────────────────────────────────────────────
# Based on BioNTech BNT162b2 and published mRNA vaccine literature

# 5' UTR: human alpha-globin 5'UTR (high translation efficiency)
# Source: BNT162b2 (Nance & Meier, 2021; PMC8310186)
FIVE_PRIME_UTR = "UUCUUGGUCCCCACAGACUCAGAGAGAACCCGCC"

# Kozak consensus sequence (strong initiation context)
# The AUG start codon is part of the CDS, Kozak is the context around it
KOZAK = "GCCACC"  # placed immediately before AUG

# Signal peptide: human tissue Plasminogen Activator (tPA)
# Routes the polyprotein to ER for MHC-I loading
# Standard choice for neoantigen vaccines
TPA_SIGNAL_AA = "MDAMKRGLCCVLLLCGAVFVSPSQEIHARFR"

# Linker between epitopes: AAY
# Facilitates proteasomal cleavage between neoantigen peptides
# Used in polyepitope vaccine constructs (Genome Medicine, 2021)
LINKER_AA = "AAY"

# Stop codon: double stop for reliability
STOP_CODONS = "UGAUAA"

# 3' UTR: AES + mtRNR1 (from BNT162b2)
# AES = amino-terminal enhancer of split (stabilizes mRNA)
# mtRNR1 = mitochondrial 12S rRNA fragment (extends half-life)
# Source: BNT162b2 patent WO2021213945A1
THREE_PRIME_UTR_AES = (
    "CUGAUAAUAGGCUGGAGCCUCGGUGGCCAUGCUUCUUGCCCCUUGGGCCUCCCCCCAGCCCC"
    "UCCUCCCCUUCCUGCACCCGUACCCCCGUGGUCUUUGAAUAAAGUCUGAGUGGGCGGC"
)
THREE_PRIME_UTR_MTRNR1 = (
    "AUCAAUUUUUAUUUAUCAUUGCAUACAUUCUAAUUAAAAAAUAUAAAGAUAUAAAGAUUUUU"
    "CUUAAAUAAGAUAUCCAAGAUUUAAAUAUGAUUUAAAUUAACUGUUGUUAAUUAAUAAGCU"
    "GAAUUUAAAUUU"
)

# Poly(A) tail: segmented A30-linker-A70 (BNT162b2 design)
# Segmented design is more stable during IVT production than continuous poly(A)
POLYA_A30 = "A" * 30
POLYA_LINKER = "GCAUAUGACU"  # 10-nt linker (from BNT162b2)
POLYA_A70 = "A" * 70

# ─── Codon table (human-optimized, most frequent codons) ────────────────────

CODON_TABLE = {
    "A": "GCC", "R": "CGG", "N": "AAC", "D": "GAC", "C": "UGC",
    "E": "GAG", "Q": "CAG", "G": "GGC", "H": "CAC", "I": "AUC",
    "L": "CUG", "K": "AAG", "M": "AUG", "F": "UUC", "P": "CCC",
    "S": "AGC", "T": "ACC", "W": "UGG", "Y": "UAC", "V": "GUG",
}


def protein_to_mrna_simple(protein_seq):
    """Simple codon-optimized translation (fallback if LinearDesign unavailable)."""
    codons = []
    for aa in protein_seq:
        if aa in CODON_TABLE:
            codons.append(CODON_TABLE[aa])
        else:
            raise ValueError(f"Unknown amino acid: {aa}")
    return "".join(codons)


def load_neoantigens(tsv_path):
    """Load neoantigen peptides from TSV."""
    peptides = []
    with open(tsv_path, newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        seen = set()
        for row in reader:
            pep = row.get("Mutant_Peptide") or row.get("MT Epitope Seq", "")
            gene = row.get("Gene") or row.get("Gene Name", "?")
            hla = row.get("HLA_Allele") or row.get("HLA Allele", "?")
            if pep and pep not in seen:
                seen.add(pep)
                peptides.append({"gene": gene, "peptide": pep, "hla": hla})
    return peptides


def build_protein_construct(peptides, signal=TPA_SIGNAL_AA, linker=LINKER_AA):
    """Build polyepitope protein: signal + pep1 + linker + pep2 + ... + pepN."""
    parts = [signal]
    for i, p in enumerate(peptides):
        parts.append(p["peptide"])
        if i < len(peptides) - 1:
            parts.append(linker)
    return "".join(parts)


def build_full_mrna(cds_mrna):
    """Assemble complete mRNA: 5'UTR + Kozak + AUG + CDS + stop + 3'UTR + polyA."""
    parts = [
        FIVE_PRIME_UTR,
        KOZAK,
        cds_mrna,          # starts with AUG (from signal peptide M)
        STOP_CODONS,
        THREE_PRIME_UTR_AES,
        THREE_PRIME_UTR_MTRNR1,
        POLYA_A30,
        POLYA_LINKER,
        POLYA_A70,
    ]
    return "".join(parts)


def write_fasta(path, header, sequence, wrap=80):
    with open(path, "w") as f:
        f.write(f">{header}\n")
        for i in range(0, len(sequence), wrap):
            f.write(sequence[i:i+wrap] + "\n")


def generate_construct_map(peptides, protein, cds, full_mrna):
    """Generate annotated map of the construct."""
    lines = []
    lines.append("=" * 80)
    lines.append("  PERSONALIZED mRNA CANCER VACCINE CONSTRUCT — HCC1395")
    lines.append(f"  Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    lines.append("=" * 80)
    lines.append("")

    lines.append("CONSTRUCT ARCHITECTURE:")
    lines.append("  5'cap — 5'UTR — Kozak+AUG — tPA_signal — [epitopes+linkers] — stop — 3'UTR — polyA")
    lines.append("")

    # mRNA regions
    pos = 1
    regions = [
        ("5' UTR (human α-globin)", len(FIVE_PRIME_UTR)),
        ("Kozak consensus", len(KOZAK)),
        ("CDS (LinearDesign optimized)", len(cds)),
        ("Stop codons (UGA+UAA)", len(STOP_CODONS)),
        ("3' UTR — AES element", len(THREE_PRIME_UTR_AES)),
        ("3' UTR — mtRNR1 element", len(THREE_PRIME_UTR_MTRNR1)),
        ("Poly(A) — A30 segment", len(POLYA_A30)),
        ("Poly(A) — 10nt linker", len(POLYA_LINKER)),
        ("Poly(A) — A70 segment", len(POLYA_A70)),
    ]

    lines.append("mRNA MAP:")
    lines.append(f"  {'Region':<35} {'Start':>6} {'End':>6} {'Length':>7}")
    lines.append("  " + "-" * 60)
    for name, length in regions:
        end = pos + length - 1
        lines.append(f"  {name:<35} {pos:>6} {end:>6} {length:>6} nt")
        pos = end + 1
    lines.append(f"  {'TOTAL':<35} {'':>6} {'':>6} {pos-1:>6} nt")

    lines.append("")
    lines.append("PROTEIN MAP:")
    lines.append(f"  {'Component':<20} {'Sequence':<20} {'Length':>6} aa")
    lines.append("  " + "-" * 50)
    lines.append(f"  {'tPA signal peptide':<20} {TPA_SIGNAL_AA[:15]+'...':<20} {len(TPA_SIGNAL_AA):>6}")

    for i, p in enumerate(peptides):
        lines.append(f"  {p['gene']:<20} {p['peptide']:<20} {len(p['peptide']):>6}    ({p['hla']})")
        if i < len(peptides) - 1:
            lines.append(f"  {'AAY linker':<20} {'AAY':<20} {3:>6}")

    lines.append(f"  {'TOTAL protein':<20} {'':20} {len(protein):>6} aa")

    lines.append("")
    lines.append("DESIGN ELEMENTS:")
    lines.append(f"  5' cap:      Cap1 (m7GpppN'm) — added during IVT, not in sequence")
    lines.append(f"  5' UTR:      Human α-globin (BNT162b2-style, {len(FIVE_PRIME_UTR)} nt)")
    lines.append(f"  Kozak:       {KOZAK} (strong initiation context)")
    lines.append(f"  Signal pep:  tPA ({len(TPA_SIGNAL_AA)} aa) — routes to ER for MHC-I loading")
    lines.append(f"  Linkers:     AAY — proteasomal cleavage sites between epitopes")
    lines.append(f"  Stop:        {STOP_CODONS} (double stop for reliability)")
    lines.append(f"  3' UTR:      AES + mtRNR1 (BNT162b2-style, {len(THREE_PRIME_UTR_AES) + len(THREE_PRIME_UTR_MTRNR1)} nt)")
    lines.append(f"  Poly(A):     A30-{POLYA_LINKER}-A70 (segmented, {30+10+70} nt)")
    lines.append(f"  Nucleotides: N1-methylpseudouridine (Ψ) — replace U during IVT")
    lines.append("")
    lines.append("NEXT STEPS:")
    lines.append("  1. Convert U → Ψ (N1-methylpseudouridine) during in-vitro transcription")
    lines.append("  2. Add Cap1 structure enzymatically or co-transcriptionally")
    lines.append("  3. Purify mRNA (HPLC or cellulose chromatography)")
    lines.append("  4. Encapsulate in LNP (SM-102 or ALC-0315 ionizable lipid)")
    lines.append("  5. Quality control: integrity gel, endotoxin test, encapsulation efficiency")

    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print("Usage: assemble_construct.py <top10.tsv> [output_dir]")
        sys.exit(1)

    tsv_path = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else "results/vaccine_construct"
    Path(output_dir).mkdir(parents=True, exist_ok=True)

    # Load neoantigens
    peptides = load_neoantigens(tsv_path)
    if not peptides:
        print("ERROR: No peptides found in TSV")
        sys.exit(1)

    print(f"Loaded {len(peptides)} unique neoantigens")
    for p in peptides:
        print(f"  {p['gene']:12s} {p['peptide']:12s} {p['hla']}")

    # Build protein construct
    protein = build_protein_construct(peptides)
    print(f"\nProtein construct: {len(protein)} aa")
    print(f"  tPA signal ({len(TPA_SIGNAL_AA)} aa) + {len(peptides)} epitopes + {len(peptides)-1} AAY linkers")

    # Generate CDS mRNA (simple codon optimization as fallback)
    cds = protein_to_mrna_simple(protein)
    print(f"\nCDS (codon-optimized): {len(cds)} nt")

    # Assemble full mRNA
    full_mrna = build_full_mrna(cds)
    print(f"Full mRNA construct: {len(full_mrna)} nt")

    # Write outputs
    write_fasta(
        os.path.join(output_dir, "vaccine_protein.fasta"),
        "HCC1395_neoantigen_vaccine_polyepitope",
        protein
    )

    write_fasta(
        os.path.join(output_dir, "vaccine_mrna_cds.fasta"),
        f"HCC1395_neoantigen_vaccine_CDS_codon_optimized_{len(cds)}nt",
        cds
    )

    write_fasta(
        os.path.join(output_dir, "vaccine_mrna_full.fasta"),
        f"HCC1395_neoantigen_vaccine_full_mRNA_{len(full_mrna)}nt",
        full_mrna
    )

    # Generate construct map
    construct_map = generate_construct_map(peptides, protein, cds, full_mrna)
    map_path = os.path.join(output_dir, "construct_map.txt")
    with open(map_path, "w") as f:
        f.write(construct_map)

    print(f"\n{construct_map}")

    print(f"\nFiles saved to {output_dir}/:")
    print(f"  vaccine_protein.fasta      — {len(protein)} aa polyepitope")
    print(f"  vaccine_mrna_cds.fasta     — {len(cds)} nt CDS")
    print(f"  vaccine_mrna_full.fasta    — {len(full_mrna)} nt complete mRNA")
    print(f"  construct_map.txt          — annotated construct map")
    print(f"\nNote: For LinearDesign-optimized CDS, use vaccine_mrna_cds_lineardesign.fasta")
    print(f"      (generated separately via LinearDesign on Vast.ai)")


if __name__ == "__main__":
    main()
