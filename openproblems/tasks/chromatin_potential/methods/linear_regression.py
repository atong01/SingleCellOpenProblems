import numpy as np
import pandas as pd
import scanpy as sc
import scipy.sparse
from ....tools.decorators import method


def _chrom_limit(x, tss_size=2e5):
    """Extend TSS to upstream and downstream intervals.

    Parameters
    ----------
    x : pd.Series
        a pd.Series containing [start, end, direction]
        where start and end are ints and direction is {'+', '-'}.
    tss_size: int
        a int that defines the upstream and downstream regions around TSS
    """
    y = x.values
    gene_direction = y[-1]
    gene_start = y[-3]
    gene_end = y[-2]
    if gene_direction == "+":
        return [gene_start - tss_size // 2, gene_start + tss_size // 2]
    else:
        return [gene_end - tss_size // 2, gene_end + tss_size // 2]


def _atac_genes_score(adata, top_genes=500, threshold=1):
    """Calculate gene scores and insert into .obsm."""
    import pybedtools

    # basic quality control
    sc.pp.filter_cells(adata, min_genes=200)
    sc.pp.filter_genes(adata, min_cells=5)

    adata.var["mt"] = adata.var.gene_short_name.str.lower().str.startswith(
        "mt-"
    )  # annotate the group of mitochondrial genes as 'mt'

    adata = adata[:, ~pd.isnull(adata.var["mt"])].copy()

    sc.pp.calculate_qc_metrics(
        adata, qc_vars=["mt"], percent_top=None, log1p=False, inplace=True
    )

    adata = adata[
        (adata.obs.n_genes_by_counts < 2000) & (adata.obs.pct_counts_mt < 10), :
    ].copy()

    sc.pp.normalize_total(adata, target_sum=1e4)
    sc.pp.log1p(adata)
    sc.pp.highly_variable_genes(adata, n_top_genes=top_genes)

    adata = adata[:, adata.var.highly_variable].copy()

    sc.pp.regress_out(adata, ["total_counts", "pct_counts_mt"])
    sc.pp.scale(adata, max_value=10)

    # generate peak to gene weight matrix
    # remove genes without annotation
    adata = adata[:, ~pd.isnull(adata.var.loc[:, "chr"])]
    adata = adata[adata.var.loc[:, "chr"].isin(np.unique(adata.uns["mode2_var_chr"]))]

    # filter atac-seq matrix
    sel = np.isin(adata.uns["mode2_var_chr"], adata.var.loc[:, "chr"].unique())
    adata.uns["mode2_var"] = adata.uns["mode2_var"][sel]
    adata.uns["mode2_var_chr"] = adata.uns["mode2_var_chr"][sel]
    adata.uns["mode2_var_start"] = adata.uns["mode2_var_start"][sel]
    adata.uns["mode2_var_end"] = adata.uns["mode2_var_end"][sel]
    adata.obsm["mode2"] = adata.obsm["mode2"][:, sel]

    # extend tss upstream and downstream
    extend_tss = adata.var.loc[:, ["start", "end", "strand"]].apply(
        _chrom_limit, axis=1
    )

    extend_tss = pd.concat(
        [
            adata.var.loc[:, "chr"],
            extend_tss.map(lambda x: x[0]).astype("int32"),
            extend_tss.map(lambda x: x[1]).astype("int32"),
            pd.Series(np.arange(adata.shape[1]), index=adata.var_names),
        ],
        axis=1,
    )

    # peak summits
    peaks = pd.DataFrame(
        {
            "chr": adata.uns["mode2_var_chr"],
            "start": adata.uns["mode2_var_start"].astype("int32"),
            "end": adata.uns["mode2_var_end"].astype("int32"),
        }
    )

    summits = pd.concat(
        [
            peaks.iloc[:, 0],
            peaks.iloc[:, [1, 2]].mean(axis=1).astype("int32"),
            (peaks.iloc[:, [1, 2]].mean(axis=1) + 1).astype("int32"),
            pd.Series(np.arange(peaks.shape[0])),
        ],
        axis=1,
    )

    # overlap TSS bins with peaks
    x = pybedtools.BedTool.from_dataframe(summits)
    y = pybedtools.BedTool.from_dataframe(extend_tss)
    tss_to_peaks = x.intersect(y, wb=True, wa=True, loj=True).to_dataframe()

    # remove non-overlapped TSS and peaks
    tss_to_peaks = tss_to_peaks.loc[
        (tss_to_peaks.thickEnd != ".") | (tss_to_peaks.score != "."), :
    ]

    # weight matrix by peak to TSS distances
    tss_to_peaks["distance"] = tss_to_peaks.apply(
        lambda x: abs((int(x[5]) + int(x[6])) / 2 - int(x[1])) * 1.0 / 1e5, axis=1
    )
    tss_to_peaks["weight"] = np.exp(-0.5 - 4 * tss_to_peaks["distance"].values)

    gene_to_peak_weight = scipy.sparse.csr_matrix(
        (
            tss_to_peaks.weight.values,
            (tss_to_peaks.thickEnd.astype("int32").values, tss_to_peaks.name.values),
        ),
        shape=(adata.shape[1], adata.uns["mode2_var"].shape[0]),
    )
    adata.obsm["gene_score"] = scipy.sparse.csr_matrix.dot(
        gene_to_peak_weight, adata.obsm["mode2"].T >= threshold
    ).T
    return adata


@method(
    method_name="BETA",
    paper_name="Target analysis by integration of transcriptome "
    "and ChIP-seq data with BETA",
    paper_url="https://pubmed.ncbi.nlm.nih.gov/24263090/",
    paper_year=2013,
    code_version="1.0",
    code_url="http://cistrome.org/BETA/src/BETA_1.0.7.zip",
)
def linear_regression_exponential_decay(adata, n_top_genes=5000, threshold=1):
    adata = _atac_genes_score(adata, top_genes=n_top_genes, threshold=threshold)
    return adata