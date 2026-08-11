#!/usr/bin/env Rscript
#
# Neighbor-joining tree from the full pairwise Mash-distance matrix, with
# same-strain highlight boxes for every strain group of >=2 members.
#
# Highlight rule (generic, derived from the genome-list control file --
# no hardcoded per-strain tip names):
#   - Any strain with >=2 members in the panel gets one blue box, the
#     MRCA of that strain's members.
#   - Exception: the focal assembly's own strain gets *two* boxes --
#     peach spanning all members (including focal), and blue spanning
#     just the non-focal members, drawn in that order with an opaque
#     white box in between (peach, then white over the non-focal
#     subset, then blue over that same subset) so the focal tip alone
#     reads peach and every other member of its strain reads blue.
#   - A strain with only 1 member gets no box.

suppressPackageStartupMessages({
  library(optparse)
  library(ape)
  library(ggtree)
  library(ggplot2)
})

# ─── CLI ─────────────────────────────────────────────────────────────────────
option_list <- list(
  make_option(c("-d","--distances"),  type="character", default="data/processed/distances.tsv",
    metavar="FILE", help="Pairwise distances TSV (asm1, asm2, mash_d -- no header). [default: %default]"),
  make_option(c("-g","--genomes"),    type="character", default="config/genomes.tsv",
    metavar="FILE", help="Genome-list control file (strain, suffix, role, url). [default: %default]"),
  make_option(c("-o","--output"),     type="character", default="output/figures/nj_tree.svg",
    metavar="FILE", help="Output file; PDF, PNG, or SVG detected from extension. [default: %default]"),
  make_option(c("-W","--width"),  type="double", default=7.5,
    help="Plot width in inches. [default: %default]"),
  make_option(c("-H","--height"), type="double", default=8.5,
    help="Plot height in inches. [default: %default]")
)

parser <- OptionParser(usage = "%prog [options]", option_list = option_list)
opt <- parse_args(parser)

for (f in c(opt$distances, opt$genomes)) {
  if (!file.exists(f)) stop(sprintf("File not found: %s", f), call.=FALSE)
}

# ─── Genome list → strain groups, focal assembly ──────────────────────────────
genomes <- read.table(opt$genomes, header=TRUE, sep="\t", stringsAsFactors=FALSE)
genomes$label <- paste(genomes$strain, genomes$suffix, sep="_")

focal_rows <- genomes[genomes$role == "focal", ]
if (nrow(focal_rows) != 1)
  stop(sprintf("Expected exactly one role=focal genome in %s, found %d.",
               opt$genomes, nrow(focal_rows)), call.=FALSE)
focal_label  <- focal_rows$label[1]
focal_strain <- focal_rows$strain[1]

# ─── Build the tree fresh from the full distance matrix ──────────────────────
df <- read.table(opt$distances, header=FALSE, sep="\t",
                 col.names=c("a","b","d"), stringsAsFactors=FALSE)
df$d <- pmax(df$d, 0)

samples <- sort(unique(c(df$a, df$b)))
n <- length(samples)
mat <- matrix(0.0, nrow=n, ncol=n, dimnames=list(samples, samples))
for (i in seq_len(nrow(df))) {
  mat[df$a[i], df$b[i]] <- df$d[i]
  mat[df$b[i], df$a[i]] <- df$d[i]
}
tree <- nj(as.dist(mat))

rds_out <- sub("\\.[^.]+$", ".rds", opt$output)
dir.create(dirname(opt$output), recursive=TRUE, showWarnings=FALSE)
saveRDS(tree, rds_out)
cat(sprintf("Wrote: %s\n", rds_out))

# ─── Same-strain highlight boxes, generic over strain groups ─────────────────
peach_fill <- "#f4a582"; peach_alpha <- 0.4
blue_fill  <- "lightblue"; blue_alpha <- 1

p <- ggtree(tree, layout = "rectangular", size = 0.8)

strain_groups <- split(genomes$label, genomes$strain)
for (strain in names(strain_groups)) {
  members <- intersect(strain_groups[[strain]], tree$tip.label)
  if (length(members) < 2) next

  if (strain == focal_strain) {
    non_focal <- setdiff(members, focal_label)
    node_all <- MRCA(tree, members)
    p <- p + geom_hilight(node = node_all, fill = peach_fill, alpha = peach_alpha)
    if (length(non_focal) >= 2) {
      node_non_focal <- MRCA(tree, non_focal)
      p <- p + geom_hilight(node = node_non_focal, fill = "white", alpha = 1)
      p <- p + geom_hilight(node = node_non_focal, fill = blue_fill, alpha = blue_alpha)
    }
    # length(non_focal) == 1: single non-focal tip, no internal node to box --
    # the peach box above already distinguishes the whole strain group.
  } else {
    node <- MRCA(tree, members)
    p <- p + geom_hilight(node = node, fill = blue_fill, alpha = blue_alpha)
  }
}

# Display-only: underscore -> space in tip labels. This touches p$data
# (ggtree's plot data), not tree$tip.label itself -- the highlight-box
# logic above already ran and matched against the real (underscored)
# identifiers, so this can't affect which boxes got drawn where.
p$data$label[p$data$isTip] <- gsub("_", " ", p$data$label[p$data$isTip])

p <- p +
  geom_tree(size = 0.8) +
  geom_tiplab(align = TRUE, linetype = "dotted", size = 7,
              fontface = "bold", offset = max(node.depth.edgelength(tree)) * 0.02) +
  geom_treescale(x = 0, y = -0.4, fontsize = 7, linesize = 0.6) +
  theme_tree2() +
  ggtitle("Mash Distance NJ Tree") +
  coord_cartesian(clip = "off") +
  theme(
    plot.margin  = margin(5, 130, 5, 15),
    axis.text.x  = element_text(size = 18),
    axis.title.x = element_text(size = 18),
    plot.title   = element_text(size = 24, face = "bold")
  )

# Explicit device selection rather than ggsave()'s extension-guessing --
# ggsave() only supports SVG via the svglite package (not installed;
# errors rather than falling back to base R's own svg() device), so this
# matches plot_kmer_swarm.R's approach instead of adding a dependency.
ext <- tolower(tools::file_ext(opt$output))
if (ext == "png") {
  png(opt$output, width=opt$width, height=opt$height, units="in", res=300)
} else if (ext == "svg") {
  svg(opt$output, width=opt$width, height=opt$height)
} else {
  pdf(opt$output, width=opt$width, height=opt$height)
}
print(p)
invisible(dev.off())
cat(sprintf("Wrote: %s\n", opt$output))
