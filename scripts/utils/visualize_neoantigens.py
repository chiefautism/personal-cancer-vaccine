#!/usr/bin/env python3
"""
Neoantigen pipeline visualization — publication-quality plots + HTML report.

Usage:
    python3 visualize_neoantigens.py <input.tsv> [output_dir]

Auto-detects whether IC50 or Percentile data is available and adapts plots accordingly.
"""

import sys
import os
import csv
import base64
from pathlib import Path
from io import BytesIO
from datetime import datetime

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import matplotlib.patches as mpatches
    from matplotlib.gridspec import GridSpec
    import matplotlib.ticker as ticker
except ImportError:
    print("ERROR: matplotlib required. Install: pip install matplotlib seaborn")
    sys.exit(1)

try:
    import seaborn as sns
    sns.set_style("whitegrid")
except ImportError:
    pass

# ─── Style ───────────────────────────────────────────────────────────────────

COLORS = {
    "blue": "#4477AA", "cyan": "#66CCEE", "green": "#228833",
    "yellow": "#CCBB44", "red": "#EE6677", "purple": "#AA3377",
    "grey": "#BBBBBB", "dark": "#222222",
}
HLA_LOCUS_COLORS = {"A": "#4477AA", "B": "#EE6677", "C": "#228833"}
DPI = 200

plt.rcParams.update({
    "font.family": "sans-serif", "font.size": 11,
    "axes.titlesize": 14, "axes.titleweight": "bold", "axes.labelsize": 12,
    "figure.dpi": DPI, "figure.facecolor": "white",
    "savefig.bbox": "tight", "savefig.pad_inches": 0.3,
})

# ─── Data loading ────────────────────────────────────────────────────────────

COLUMN_MAP = {
    "Gene": "gene", "HLA_Allele": "hla", "Mutant_Peptide": "mt_peptide",
    "IC50_nM": "ic50", "Best_IC50": "ic50",
    "Percentile": "percentile", "Best_Percentile": "percentile",
    "WT_Peptide": "wt_peptide", "Fold_Change": "fold_change",
    "Tumor_VAF": "vaf", "Expression": "expression",
    "Chr": "chr", "Position": "position", "Variant_Type": "variant_type",
    "Rank": "rank",
    "Gene Name": "gene", "HLA Allele": "hla", "MT Epitope Seq": "mt_peptide",
    "Median MT IC50 Score": "ic50", "Median MT Percentile": "percentile",
    "WT Epitope Seq": "wt_peptide", "Corresponding Fold Change": "fold_change",
    "Tumor DNA VAF": "vaf", "Gene Expression": "expression",
    "Chromosome": "chr", "Start": "position", "Variant Type": "variant_type",
    "Best MT IC50 Score": "ic50", "Best MT Percentile": "percentile",
}


def load_data(path):
    rows = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            n = {}
            for k, v in row.items():
                n[COLUMN_MAP.get(k, k.lower().replace(" ", "_"))] = v
            rows.append(n)
    return rows


def to_float(val, default=0.0):
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


def has_valid(data, key):
    """Check if any row has a non-NA numeric value for this key."""
    return any(to_float(d.get(key), None) is not None and d.get(key, "NA") != "NA" for d in data)


def binding_metric(data):
    """Return (key, label, threshold, lower_is_better) for the best available metric."""
    if has_valid(data, "ic50"):
        return "ic50", "IC50 (nM)", 500, True
    return "percentile", "Binding Percentile", 2.0, True


def parse_chr_num(c):
    c = str(c).replace("chr", "")
    if c == "X": return 23
    if c == "Y": return 24
    try: return int(c)
    except ValueError: return 25


# ─── Plot 1: Binding Strength vs Presentation ───────────────────────────────

def plot_binding_landscape(data):
    """Percentile vs Expression — binding strength vs presentation likelihood."""
    fig, ax = plt.subplots(figsize=(8, 6))

    mk, mlabel, mthresh, _ = binding_metric(data)
    scores = [to_float(d.get(mk), mthresh) for d in data]
    exprs = [to_float(d["expression"], 5) for d in data]
    vafs = [to_float(d["vaf"], 0.3) for d in data]
    genes = [d.get("gene", "?") for d in data]

    sizes = [max(v * 400, 50) for v in vafs]

    scatter = ax.scatter(
        scores, exprs, s=sizes, c=vafs,
        cmap="RdYlGn", edgecolors=COLORS["dark"],
        linewidths=0.8, alpha=0.85, zorder=3, vmin=0, vmax=1,
    )

    # Threshold line
    ax.axvline(mthresh, color=COLORS["red"], linestyle="--",
               linewidth=1.5, alpha=0.7, label=f"Threshold = {mthresh}")

    # Quadrant shading — strong binders + high expression
    ax.axvspan(0, mthresh, alpha=0.04, color=COLORS["green"], zorder=0)
    ax.axhline(10, color=COLORS["grey"], linestyle=":", linewidth=1, alpha=0.4)

    for i, gene in enumerate(genes):
        ax.annotate(gene, (scores[i], exprs[i]),
                    textcoords="offset points", xytext=(8, 4),
                    fontsize=9, fontweight="bold", color=COLORS["dark"])

    ax.set_xlabel(f"Binding Strength — {mlabel} (lower = stronger)")
    ax.set_ylabel("Gene Expression (TPM)")
    ax.set_title("Neoantigen Binding vs Expression")
    ax.legend(loc="upper right", framealpha=0.9)

    cbar = fig.colorbar(scatter, ax=ax, shrink=0.8, pad=0.02)
    cbar.set_label("Tumor VAF (clonality)")

    for vaf_val, label in [(0.3, "VAF 0.3"), (0.6, "VAF 0.6")]:
        ax.scatter([], [], s=vaf_val * 400, c=COLORS["grey"],
                   edgecolors=COLORS["dark"], linewidths=0.8, label=label)
    ax.legend(loc="upper right", framealpha=0.9, fontsize=9)

    if mk == "percentile":
        ax.set_xlim(-0.002, max(scores) * 1.5 + 0.005)

    fig.tight_layout()
    return fig


# ─── Plot 2: Ranked Bars ────────────────────────────────────────────────────

def plot_binding_ranked(data):
    """Horizontal bar chart ranked by binding strength."""
    fig, ax = plt.subplots(figsize=(8, max(4, len(data) * 0.55)))

    mk, mlabel, mthresh, _ = binding_metric(data)
    sorted_data = sorted(data, key=lambda d: to_float(d.get(mk), 9999))
    genes = [d.get("gene", "?") for d in sorted_data]
    scores = [to_float(d.get(mk), 0) for d in sorted_data]
    hlas = [d.get("hla", "") for d in sorted_data]

    max_score = max(scores) if max(scores) > 0 else 1
    colors = [plt.cm.RdYlGn_r(s / max_score) for s in scores]

    y_pos = range(len(genes))
    bars = ax.barh(y_pos, scores, color=colors, edgecolor=COLORS["dark"],
                   linewidth=0.5, height=0.7, zorder=3)

    ax.set_yticks(y_pos)
    ax.set_yticklabels([f"{g}  ({h})" for g, h in zip(genes, hlas)], fontsize=10)
    ax.invert_yaxis()

    ax.axvline(mthresh, color=COLORS["red"], linestyle="--",
               linewidth=1.5, alpha=0.7, label=f"Threshold ({mthresh})")

    for i, (v, bar) in enumerate(zip(scores, bars)):
        unit = " nM" if mk == "ic50" else "%"
        ax.text(v + max_score * 0.02, i, f"{v:.2f}{unit}" if mk == "percentile" else f"{v:.0f}{unit}",
                va="center", fontsize=9, fontweight="bold")

    ax.set_xlabel(f"{mlabel} (lower = stronger binder)")
    ax.set_title("Top Neoantigen Candidates (Ranked)")
    ax.legend(loc="lower right")
    ax.set_xlim(right=max_score * 1.3)
    fig.tight_layout()
    return fig


# ─── Plot 3: HLA Distribution ───────────────────────────────────────────────

def plot_hla_distribution(data):
    fig, ax = plt.subplots(figsize=(8, 6))

    hla_counts = {}
    for d in data:
        hla = d.get("hla", "Unknown")
        hla_counts[hla] = hla_counts.get(hla, 0) + 1

    alleles = sorted(hla_counts.keys())
    counts = [hla_counts[a] for a in alleles]
    colors = []
    for a in alleles:
        matched = False
        for locus, color in HLA_LOCUS_COLORS.items():
            if f"-{locus}*" in a:
                colors.append(color)
                matched = True
                break
        if not matched:
            colors.append(COLORS["grey"])

    bars = ax.bar(range(len(alleles)), counts, color=colors,
                  edgecolor=COLORS["dark"], linewidth=0.8, zorder=3)

    ax.set_xticks(range(len(alleles)))
    ax.set_xticklabels(alleles, rotation=30, ha="right", fontsize=10)
    ax.set_ylabel("Number of Neoantigen Candidates")
    ax.set_title("Neoantigen Distribution by HLA Allele")
    ax.yaxis.set_major_locator(ticker.MaxNLocator(integer=True))

    patches = [mpatches.Patch(color=c, label=f"HLA-{l}") for l, c in HLA_LOCUS_COLORS.items()]
    ax.legend(handles=patches, loc="upper right")

    for bar, count in zip(bars, counts):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.1,
                str(count), ha="center", fontweight="bold", fontsize=11)

    fig.tight_layout()
    return fig


# ─── Plot 4: VAF vs Expression ──────────────────────────────────────────────

def plot_vaf_expression(data):
    fig, ax = plt.subplots(figsize=(8, 6))

    vafs = [to_float(d["vaf"], 0) for d in data]
    exprs = [to_float(d["expression"], 0) for d in data]
    pcts = [to_float(d.get("percentile"), 1) for d in data]
    genes = [d.get("gene", "?") for d in data]

    if all(v == 0 for v in exprs):
        ax.text(0.5, 0.5, "Gene expression data not available",
                transform=ax.transAxes, ha="center", va="center", fontsize=14)
        return fig

    max_pct = max(pcts) if max(pcts) > 0 else 1
    colors = [plt.cm.RdYlGn_r(p / max_pct) for p in pcts]
    sizes = [max(80, 250 * (1 - p / max_pct)) for p in pcts]

    ax.scatter(vafs, exprs, s=sizes, c=colors, edgecolors=COLORS["dark"],
               linewidths=0.8, alpha=0.85, zorder=3)

    ax.axvline(0.3, color=COLORS["grey"], linestyle=":", linewidth=1, alpha=0.6)
    ax.axhline(10.0, color=COLORS["grey"], linestyle=":", linewidth=1, alpha=0.6)

    ax.text(0.72, 0.95, "High VAF + High Expr\n(Best presentation)",
            transform=ax.transAxes, ha="center", va="top",
            fontsize=9, color=COLORS["green"], fontstyle="italic")

    for i, gene in enumerate(genes):
        ax.annotate(gene, (vafs[i], exprs[i]),
                    textcoords="offset points", xytext=(6, 4),
                    fontsize=9, fontweight="bold")

    ax.set_xlabel("Tumor DNA Variant Allele Frequency (VAF)")
    ax.set_ylabel("Gene Expression (TPM)")
    ax.set_title("Neoantigen Presentation Likelihood")
    ax.set_xlim(-0.05, 1.05)
    fig.tight_layout()
    return fig


# ─── Plot 5: Chromosome Map ─────────────────────────────────────────────────

def plot_chromosome_map(data):
    fig, ax = plt.subplots(figsize=(12, 5))

    CHR_SIZES = {
        1: 249, 2: 243, 3: 198, 4: 190, 5: 182, 6: 171, 7: 159, 8: 145,
        9: 138, 10: 134, 11: 135, 12: 133, 13: 114, 14: 107, 15: 102,
        16: 90, 17: 84, 18: 80, 19: 59, 20: 65, 21: 47, 22: 51, 23: 156, 24: 57,
    }
    CHR_LABELS = {i: str(i) for i in range(1, 23)}
    CHR_LABELS[23] = "X"
    CHR_LABELS[24] = "Y"

    mk, _, mthresh, _ = binding_metric(data)

    for c_num in sorted(CHR_SIZES.keys()):
        ax.barh(c_num, CHR_SIZES[c_num], height=0.6,
                color=COLORS["grey"], alpha=0.25, edgecolor=COLORS["grey"],
                linewidth=0.5, zorder=1)

    for d in data:
        chr_num = parse_chr_num(d.get("chr", ""))
        pos = to_float(d.get("position", 0)) / 1e6
        score = to_float(d.get(mk), mthresh)
        gene = d.get("gene", "?")
        if chr_num > 24 or pos == 0:
            continue

        color = COLORS["red"] if score < mthresh else COLORS["blue"]
        ax.plot([pos, pos], [chr_num - 0.25, chr_num + 0.25],
                color=color, linewidth=2, zorder=4)
        ax.scatter(pos, chr_num, s=80, c=color, edgecolors=COLORS["dark"],
                   linewidths=0.8, zorder=5)
        ax.annotate(gene, (pos, chr_num),
                    textcoords="offset points", xytext=(5, 8),
                    fontsize=8, fontweight="bold", color=COLORS["dark"], rotation=30)

    ax.set_yticks(list(range(1, 25)))
    ax.set_yticklabels([CHR_LABELS.get(i, "") for i in range(1, 25)], fontsize=9)
    ax.invert_yaxis()
    ax.set_xlabel("Position (Mb)")
    ax.set_title("Chromosomal Distribution of Neoantigen Mutations")

    ax.scatter([], [], s=80, c=COLORS["red"], edgecolors=COLORS["dark"],
               label=f"Strong binder (< {mthresh})")
    ax.scatter([], [], s=80, c=COLORS["blue"], edgecolors=COLORS["dark"],
               label=f"Weaker binder")
    ax.legend(loc="lower right", fontsize=9)
    fig.tight_layout()
    return fig


# ─── Plot 6: Peptide Comparison ─────────────────────────────────────────────

def plot_peptide_comparison(data):
    n = len(data)
    fig_height = max(4, n * 0.8 + 1.5)
    fig, ax = plt.subplots(figsize=(10, fig_height))

    mk, mlabel, _, _ = binding_metric(data)
    short_label = "%ile" if mk == "percentile" else "IC50"

    ax.set_xlim(-0.5, 22)
    ax.set_ylim(-0.5, n)
    ax.invert_yaxis()
    ax.axis("off")
    ax.set_title("Mutant vs Wildtype Peptide Sequences", pad=20)

    ax.text(-0.3, -0.3, "Gene", fontweight="bold", fontsize=10, va="center")
    ax.text(4.5, -0.3, "Wildtype", fontweight="bold", fontsize=10, va="center", ha="center")
    ax.text(10, -0.3, "\u2192", fontweight="bold", fontsize=12, va="center", ha="center")
    ax.text(15.5, -0.3, "Mutant", fontweight="bold", fontsize=10, va="center", ha="center")
    ax.text(21, -0.3, short_label, fontweight="bold", fontsize=10, va="center", ha="center")

    for i, d in enumerate(data):
        gene = d.get("gene", "?")
        wt = d.get("wt_peptide", "")
        mt = d.get("mt_peptide", "")
        score = to_float(d.get(mk, 0))

        y = i + 0.3
        ax.text(-0.3, y, gene, fontsize=10, fontweight="bold",
                va="center", fontfamily="monospace")

        max_len = max(len(wt), len(mt))
        for j in range(max_len):
            wt_aa = wt[j] if j < len(wt) else "-"
            mt_aa = mt[j] if j < len(mt) else "-"
            is_mutated = wt_aa != mt_aa

            wt_x = 2 + j * 0.7
            ax.text(wt_x, y, wt_aa, fontsize=11, fontfamily="monospace",
                    ha="center", va="center",
                    color=COLORS["red"] if is_mutated else COLORS["dark"],
                    fontweight="bold" if is_mutated else "normal")

            mt_x = 13 + j * 0.7
            if is_mutated:
                rect = plt.Rectangle((mt_x - 0.3, y - 0.3), 0.6, 0.6,
                                     facecolor=COLORS["red"], alpha=0.8,
                                     edgecolor="none", zorder=2)
                ax.add_patch(rect)
            text_color = "white" if is_mutated else COLORS["dark"]
            ax.text(mt_x, y, mt_aa, fontsize=11, fontfamily="monospace",
                    ha="center", va="center", color=text_color,
                    fontweight="bold", zorder=3)

        ax.text(10, y, "\u2192", fontsize=10, ha="center", va="center", color=COLORS["grey"])

        fmt = f"{score:.2f}" if mk == "percentile" else f"{score:.0f}"
        ax.text(21, y, fmt, fontsize=10, ha="center", va="center",
                color=COLORS["green"], fontweight="bold")

    fig.tight_layout()
    return fig


# ─── Plot 7: Dashboard ──────────────────────────────────────────────────────

def plot_dashboard(data):
    fig = plt.figure(figsize=(16, 12))
    gs = GridSpec(2, 2, figure=fig, hspace=0.35, wspace=0.3)

    mk, mlabel, mthresh, _ = binding_metric(data)

    # Panel 1: Binding vs Expression
    ax1 = fig.add_subplot(gs[0, 0])
    scores = [to_float(d.get(mk), mthresh) for d in data]
    exprs = [to_float(d["expression"], 5) for d in data]
    vafs = [to_float(d["vaf"], 0.3) for d in data]
    genes = [d.get("gene", "?") for d in data]
    sizes = [max(v * 300, 30) for v in vafs]
    ax1.scatter(scores, exprs, s=sizes, c=COLORS["blue"],
                edgecolors=COLORS["dark"], linewidths=0.5, alpha=0.8, zorder=3)
    ax1.axvline(mthresh, color=COLORS["red"], linestyle="--", linewidth=1, alpha=0.6)
    for i, g in enumerate(genes):
        ax1.annotate(g, (scores[i], exprs[i]), textcoords="offset points",
                     xytext=(5, 3), fontsize=7, fontweight="bold")
    ax1.set_xlabel(mlabel, fontsize=10)
    ax1.set_ylabel("Expression (TPM)", fontsize=10)
    ax1.set_title("Binding vs Expression", fontsize=12)

    # Panel 2: Ranked bars
    ax2 = fig.add_subplot(gs[0, 1])
    sorted_d = sorted(data, key=lambda d: to_float(d.get(mk), 9999))
    g2 = [d.get("gene", "?") for d in sorted_d]
    s2 = [to_float(d.get(mk), 0) for d in sorted_d]
    colors2 = [COLORS["green"] if v < mthresh else COLORS["yellow"] for v in s2]
    ax2.barh(range(len(g2)), s2, color=colors2, edgecolor=COLORS["dark"], linewidth=0.5, height=0.6)
    ax2.set_yticks(range(len(g2)))
    ax2.set_yticklabels(g2, fontsize=9)
    ax2.invert_yaxis()
    ax2.axvline(mthresh, color=COLORS["red"], linestyle="--", linewidth=1, alpha=0.6)
    ax2.set_xlabel(mlabel, fontsize=10)
    ax2.set_title("Ranked by Binding Strength", fontsize=12)

    # Panel 3: VAF vs expression
    ax3 = fig.add_subplot(gs[1, 0])
    ax3.scatter(vafs, exprs, s=100, c=COLORS["purple"],
                edgecolors=COLORS["dark"], linewidths=0.5, alpha=0.8, zorder=3)
    ax3.axvline(0.3, color=COLORS["grey"], linestyle=":", linewidth=1, alpha=0.5)
    ax3.axhline(10.0, color=COLORS["grey"], linestyle=":", linewidth=1, alpha=0.5)
    for i, g in enumerate(genes):
        ax3.annotate(g, (vafs[i], exprs[i]), textcoords="offset points",
                     xytext=(5, 3), fontsize=7, fontweight="bold")
    ax3.set_xlabel("Tumor VAF", fontsize=10)
    ax3.set_ylabel("Expression (TPM)", fontsize=10)
    ax3.set_title("Presentation Likelihood", fontsize=12)

    # Panel 4: Summary stats
    ax4 = fig.add_subplot(gs[1, 1])
    ax4.axis("off")
    n = len(data)
    strong = sum(1 for s in scores if s < mthresh)
    hla_set = set(d.get("hla", "") for d in data)
    gene_set = set(d.get("gene", "") for d in data)

    stats = [
        ("Total Candidates", str(n)),
        (f"Strong Binders (< {mthresh})", str(strong)),
        ("Unique HLA Alleles", str(len(hla_set))),
        ("Unique Genes", str(len(gene_set))),
        (f"Best {mlabel}", f"{min(scores):.3f}" if scores else "N/A"),
        (f"Mean {mlabel}", f"{sum(scores)/n:.3f}" if n else "N/A"),
        ("Mean Tumor VAF", f"{sum(vafs)/n:.2f}" if n else "N/A"),
        ("HLA Alleles", ", ".join(sorted(hla_set))),
    ]

    ax4.text(0.5, 0.95, "Summary Statistics", fontsize=14, fontweight="bold",
             ha="center", va="top", transform=ax4.transAxes)
    for i, (label, value) in enumerate(stats):
        y = 0.82 - i * 0.1
        ax4.text(0.1, y, label + ":", fontsize=11, fontweight="bold",
                 va="center", transform=ax4.transAxes)
        ax4.text(0.95, y, value, fontsize=11, ha="right",
                 va="center", transform=ax4.transAxes, color=COLORS["blue"])
    ax4.text(0.5, 0.02, f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
             fontsize=8, ha="center", va="bottom", transform=ax4.transAxes, color=COLORS["grey"])

    fig.suptitle("Neoantigen Prediction Dashboard \u2014 HCC1395",
                 fontsize=18, fontweight="bold", y=0.98)
    return fig


# ─── HTML Report ─────────────────────────────────────────────────────────────

def fig_to_base64(fig):
    buf = BytesIO()
    fig.savefig(buf, format="png", dpi=DPI, bbox_inches="tight")
    buf.seek(0)
    return base64.b64encode(buf.read()).decode("utf-8")


def generate_html_report(figures, data, output_path):
    n = len(data)
    mk, mlabel, mthresh, _ = binding_metric(data)
    scores = [to_float(d.get(mk, 0)) for d in data]
    strong = sum(1 for s in scores if s < mthresh)

    table_rows = ""
    for i, d in enumerate(data, 1):
        score = to_float(d.get(mk, 0))
        pct = to_float(d.get("percentile", 0))
        row_class = "strong" if score < mthresh else ""
        table_rows += f"""
        <tr class="{row_class}">
            <td>{i}</td>
            <td><strong>{d.get('gene', 'N/A')}</strong></td>
            <td>{d.get('hla', 'N/A')}</td>
            <td class="mono">{d.get('mt_peptide', 'N/A')}</td>
            <td>{pct:.3f}</td>
            <td class="mono">{d.get('wt_peptide', 'N/A')}</td>
            <td>{to_float(d.get('vaf', 0)):.2f}</td>
            <td>{to_float(d.get('expression', 0)):.1f}</td>
        </tr>"""

    fig_sections = ""
    titles = [
        "Binding Strength vs Expression",
        "Ranked by Binding Strength",
        "Distribution by HLA Allele",
        "Presentation Likelihood \u2014 VAF vs Expression",
        "Chromosomal Distribution",
        "Peptide Sequence Comparison",
        "Summary Dashboard",
    ]
    for title, (name, fig) in zip(titles, figures.items()):
        b64 = fig_to_base64(fig)
        fig_sections += f"""
        <div class="figure">
            <h2>{title}</h2>
            <img src="data:image/png;base64,{b64}" alt="{title}">
        </div>"""

    best_score = min(scores) if scores else 0
    best_fmt = f"{best_score:.3f}" if mk == "percentile" else f"{best_score:.0f} nM"

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Neoantigen Prediction Report \u2014 HCC1395</title>
<style>
    * {{ margin: 0; padding: 0; box-sizing: border-box; }}
    body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
           background: #f5f5f5; color: #222; line-height: 1.6; }}
    .container {{ max-width: 1100px; margin: 0 auto; padding: 20px; }}
    header {{ background: linear-gradient(135deg, #1a1a2e, #16213e, #0f3460);
             color: white; padding: 40px 20px; text-align: center; }}
    header h1 {{ font-size: 2em; margin-bottom: 8px; }}
    header p {{ opacity: 0.8; font-size: 1.1em; }}
    .stats {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
              gap: 16px; margin: 30px 0; }}
    .stat {{ background: white; border-radius: 12px; padding: 20px;
             text-align: center; box-shadow: 0 2px 8px rgba(0,0,0,0.08); }}
    .stat .value {{ font-size: 2em; font-weight: 700; color: #4477AA; }}
    .stat .label {{ font-size: 0.85em; color: #666; margin-top: 4px; }}
    table {{ width: 100%; border-collapse: collapse; background: white;
             border-radius: 12px; overflow: hidden;
             box-shadow: 0 2px 8px rgba(0,0,0,0.08); margin: 30px 0; }}
    th {{ background: #1a1a2e; color: white; padding: 12px 10px; font-size: 0.85em; text-align: left; }}
    td {{ padding: 10px; border-bottom: 1px solid #eee; font-size: 0.9em; }}
    tr:hover {{ background: #f8f9ff; }}
    tr.strong td {{ background: #f0faf0; }}
    .mono {{ font-family: 'SF Mono', 'Fira Code', monospace; letter-spacing: 1px; }}
    .figure {{ background: white; border-radius: 12px; padding: 24px;
               margin: 30px 0; box-shadow: 0 2px 8px rgba(0,0,0,0.08); }}
    .figure h2 {{ margin-bottom: 16px; color: #1a1a2e; }}
    .figure img {{ width: 100%; height: auto; border-radius: 8px; }}
    footer {{ text-align: center; padding: 30px; color: #999; font-size: 0.85em; }}
</style>
</head>
<body>
<header>
    <h1>Neoantigen Prediction Report</h1>
    <p>Personalized mRNA Cancer Vaccine Pipeline &mdash; HCC1395 (Breast Cancer Cell Line)</p>
    <p style="font-size:0.85em; margin-top:8px;">Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}</p>
</header>
<div class="container">
    <div class="stats">
        <div class="stat"><div class="value">{n}</div><div class="label">Total Candidates</div></div>
        <div class="stat"><div class="value">{strong}</div><div class="label">Strong Binders (&lt; {mthresh})</div></div>
        <div class="stat"><div class="value">{len(set(d.get('hla','') for d in data))}</div><div class="label">HLA Alleles</div></div>
        <div class="stat"><div class="value">{best_fmt}</div><div class="label">Best {mlabel}</div></div>
    </div>
    <h2 style="margin-top:30px;">Top Neoantigen Candidates</h2>
    <table>
        <thead>
            <tr>
                <th>#</th><th>Gene</th><th>HLA Allele</th><th>Mutant Peptide</th>
                <th>Percentile</th><th>WT Peptide</th><th>VAF</th><th>Expr (TPM)</th>
            </tr>
        </thead>
        <tbody>{table_rows}
        </tbody>
    </table>
    {fig_sections}
</div>
<footer>
    Personalized mRNA Cancer Vaccine Pipeline &mdash;
    <a href="https://github.com/chiefautism/personal-cancer-vaccine">GitHub</a>
</footer>
</body>
</html>"""

    with open(output_path, "w") as f:
        f.write(html)


# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("Usage: visualize_neoantigens.py <input.tsv> [output_dir]")
        sys.exit(1)

    input_path = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(input_path), "figures")

    if not os.path.isfile(input_path):
        print(f"ERROR: File not found: {input_path}")
        sys.exit(1)

    Path(output_dir).mkdir(parents=True, exist_ok=True)

    print(f"Loading: {input_path}")
    data = load_data(input_path)
    if not data:
        print("ERROR: No data rows found.")
        sys.exit(1)

    mk, mlabel, _, _ = binding_metric(data)
    print(f"  {len(data)} neoantigen candidates loaded")
    print(f"  Binding metric: {mlabel} ({'IC50 available' if mk == 'ic50' else 'using Percentile (IC50 is NA)'})")

    print("Generating visualizations...")
    figures = {}

    print("  [1/7] Binding landscape")
    figures["landscape"] = plot_binding_landscape(data)
    print("  [2/7] Ranked bar chart")
    figures["ranked"] = plot_binding_ranked(data)
    print("  [3/7] HLA distribution")
    figures["hla"] = plot_hla_distribution(data)
    print("  [4/7] VAF vs expression")
    figures["vaf_expr"] = plot_vaf_expression(data)
    print("  [5/7] Chromosome map")
    figures["chromo"] = plot_chromosome_map(data)
    print("  [6/7] Peptide comparison")
    figures["peptide"] = plot_peptide_comparison(data)
    print("  [7/7] Summary dashboard")
    figures["dashboard"] = plot_dashboard(data)

    for name, fig in figures.items():
        path = os.path.join(output_dir, f"{name}.png")
        fig.savefig(path, dpi=DPI, bbox_inches="tight")
        print(f"  Saved: {path}")

    html_path = os.path.join(output_dir, "report.html")
    print("Generating HTML report...")
    generate_html_report(figures, data, html_path)
    print(f"  Saved: {html_path}")

    plt.close("all")
    print(f"\nDone! {len(figures)} figures + HTML report in: {output_dir}/")


if __name__ == "__main__":
    main()
