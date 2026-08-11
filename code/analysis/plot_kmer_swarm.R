#!/usr/bin/env Rscript
#
# Swarm/violin plot of pairwise Mash distances, in four categories
# relative to the focal assembly (role=focal in the genome-list control
# file):
#   1. Intra-strain (excl. focal)          -- baseline same-strain noise
#   2. focal vs same-strain assemblies     -- the anomaly
#   3. focal vs other strains              -- quality control
#   4. Inter-strain (excl. focal)          -- reference distribution
#
# The focal assembly and every genome's strain come from the genome-list
# control file's role/strain columns, not a CLI argument -- adding or
# removing panel members never requires re-specifying anything here.

suppressPackageStartupMessages({
  library(optparse)
  library(ggplot2)
  library(ggrepel)
})

# ─── CLI ─────────────────────────────────────────────────────────────────────
option_list <- list(
  make_option(c("-d","--distances"),  type="character", default="data/processed/distances.tsv",
    metavar="FILE", help="Pairwise distances TSV (asm1, asm2, mash_d -- no header). [default: %default]"),
  make_option(c("-g","--genomes"),    type="character", default="config/genomes.tsv",
    metavar="FILE", help="Genome-list control file (strain, suffix, role, url). [default: %default]"),
  make_option(c("-o","--output"),     type="character", default="output/figures/swarm_plot.svg",
    metavar="FILE",
    help="Output file; PDF, PNG, or SVG detected from extension. [default: %default]"),
  make_option(c("-W","--width"),  type="double", default=4.5,
    help="Plot width in inches. [default: %default]"),
  make_option(c("-H","--height"), type="double", default=4.5,
    help="Plot height in inches. [default: %default]"),
  make_option(c("--label_thresh"), type="integer", default=5, metavar="N",
    help="Categories with fewer than N points skip violin/boxplot and label each point individually. [default: %default]")
)

parser <- OptionParser(
  usage       = "%prog [options]",
  option_list = option_list,
  description = paste(
    "\nPlot pairwise Mash distances in four categories relative to the",
    "focal assembly (role=focal in the genome-list control file):",
    "  1. Intra-strain (excl. focal)         -- baseline same-strain noise",
    "  2. focal vs same-strain assemblies    -- the anomaly",
    "  3. focal vs other strains             -- quality control",
    "  4. Inter-strain (excl. focal)         -- reference distribution",
    sep="\n"
  )
)
opt <- parse_args(parser)

for (f in c(opt$distances, opt$genomes)) {
  if (!file.exists(f)) stop(sprintf("File not found: %s", f), call.=FALSE)
}

# ─── Genome list → label/strain lookup, focal assembly ───────────────────────
genomes <- read.table(opt$genomes, header=TRUE, sep="\t", stringsAsFactors=FALSE)
genomes$label <- paste(genomes$strain, genomes$suffix, sep="_")
strain_of <- setNames(genomes$strain, genomes$label)

focal_rows <- genomes[genomes$role == "focal", ]
if (nrow(focal_rows) != 1)
  stop(sprintf("Expected exactly one role=focal genome in %s, found %d.",
               opt$genomes, nrow(focal_rows)), call.=FALSE)

focal_name   <- focal_rows$label[1]
focal_strain <- focal_rows$strain[1]
focal_pretty <- gsub("_", " ", focal_name)
cat(sprintf("Focal assembly : %s  (strain: %s)\n", focal_name, focal_strain))

# ─── Load distances ───────────────────────────────────────────────────────────
df <- read.table(opt$distances, header=FALSE, sep="\t",
                 col.names=c("asm1","asm2","d"), stringsAsFactors=FALSE)
df$s1 <- unname(strain_of[df$asm1])
df$s2 <- unname(strain_of[df$asm2])

cat(sprintf("Pairs loaded   : %d\n", nrow(df)))

# ─── Classify ────────────────────────────────────────────────────────────────
focal_inv <- df$asm1 == focal_name | df$asm2 == focal_name
same_str  <- df$s1 == df$s2

df$category <- ifelse(
   focal_inv &  same_str, "CAT2",
  ifelse(
   focal_inv & !same_str, "CAT3",
  ifelse(
  !focal_inv &  same_str, "CAT1",
                           "CAT4"
  )))

cat_labels <- c(
  CAT1 = "Intra-strain\n(excl. focal)",
  CAT2 = sprintf("%s\nvs same-strain",   focal_pretty),
  CAT3 = sprintf("%s\nvs other strains", focal_pretty),
  CAT4 = "Inter-strain\n(excl. focal)"
)
cat_order <- c("CAT1","CAT2","CAT3","CAT4")

df$category <- factor(as.character(df$category), levels=cat_order)

for (k in cat_order)
  cat(sprintf("  %-6s (%s): %d pairs\n", k,
              gsub("\n"," ", cat_labels[k]),
              sum(df$category==k)))

df$pair_label <- paste(gsub("_"," ",df$asm1), "/", gsub("_"," ",df$asm2))

# ─── Split small-n vs large-n ────────────────────────────────────────────────
# CAT1 (intra-strain, excl. focal) always gets the small-n treatment
# (individual points + labels, no violin/jitter) regardless of its count --
# the swarm/violin rendering added nothing for this category and the
# labels are more informative here than the distribution shape.
thresh   <- opt$label_thresh
cat_n    <- table(df$category)
big_cats <- setdiff(names(cat_n)[cat_n >= thresh], "CAT1")
sml_cats <- union(names(cat_n)[cat_n <  thresh], "CAT1")

df_big <- df[df$category %in% big_cats, ]
df_big$category <- factor(as.character(df_big$category), levels=cat_order)

df_sml <- df[df$category %in% sml_cats, ]
df_sml$category <- factor(as.character(df_sml$category), levels=cat_order)

# CAT1's labels are placed manually (not via ggrepel) so the stack order is
# guaranteed rather than merely requested. Several CAT1 points sit within
# ~0.00001 of each other in d, and ggrepel's direction="y" collision
# resolution stacks overlapping labels by each point's own original data
# value regardless of nudge_y -- nudging the *start* position doesn't
# change the *order* it resolves them into. Explicit coordinates
# sidestep that entirely.
df_cat1 <- df_sml[df_sml$category == "CAT1", ]
df_sml  <- df_sml[df_sml$category != "CAT1", ]

cat1_layout <- data.frame(
  pair_label = c("CS DSPR / CS Wierz",  "CS Wierz / CS DLPD",
                 "A3 DSPR / A3 Shukla", "A4 DSPR / A4 Shukla",
                 "CS DSPR / CS DLPD",   "iso-1 R6 / iso-1 Shukla"),
  # Two columns: left column (x=1.1) hugs the point cluster and stacks
  # the 4 labels with room above/below 0.002; the bottom two get pushed
  # right (x=1.5) to clear the left column instead of cramming further
  # down toward the points at y~0.
  label_x    = c(0.6,    0.6,    1.3,    1.3,    1.6,    1.6),
  label_y    = c(0.0028, 0.0023, 0.0018, 0.0013, 0.0006, 0.0001),
  stringsAsFactors = FALSE
)
df_cat1 <- merge(df_cat1, cat1_layout, by="pair_label", sort=FALSE)

# ─── Colors ───────────────────────────────────────────────────────────────────
cat_colors <- setNames(
  c("#4393c3",   # CAT1 intra-strain, not focal -- blue
    "#d6604d",   # CAT2 focal vs same-strain    -- red
    "#f4a582",   # CAT3 focal vs other strains  -- muted orange
    "#878787"),  # CAT4 inter-strain baseline   -- grey
  cat_order
)

# ─── Plot ─────────────────────────────────────────────────────────────────────
p <- ggplot(df, aes(x=category, y=d, color=category)) +

  geom_violin(
    data  = df_big,
    aes(fill=category),
    alpha = 0.2, color=NA, trim=TRUE, scale="width"
  ) +

  # Large-n categories only -- jitter is meaningful here
  geom_jitter(data=df_big, width=0.12, size=2.2, alpha=0.75) +

  # Small-n categories -- exact positions so label leader lines are correct
  geom_point(data=df_sml,  size=2.2, alpha=0.75) +
  geom_point(data=df_cat1, size=2.2, alpha=0.75) +

  geom_label_repel(
    data               = df_sml,
    aes(label=pair_label),
    ylim	       = c(0.0008, NA),
    xlim               = c(2.25, NA),
    size               = 1.9,
    label.padding      = unit(0.15,"lines"),
    box.padding        = unit(0.5,"lines"),
    point.padding      = unit(0.1,"lines"),
    min.segment.length = 0,
    max.overlaps       = Inf,
    show.legend        = FALSE,
    color              = "grey20",
    fill               = "white",
    label.size         = 0.25
  ) +

  # CAT1 -- manually stacked, see comment above df_cat1's construction
  geom_segment(
    data  = df_cat1,
    aes(xend=label_x, yend=label_y),
    color = "grey20", linewidth = 0.3
  ) +
  geom_label(
    data          = df_cat1,
    aes(x=label_x, y=label_y, label=pair_label),
    size          = 1.9,
    label.padding = unit(0.15,"lines"),
    color         = "grey20",
    fill          = "white",
    label.size    = 0.25,
    hjust         = 0
  ) +

  scale_color_manual(values=cat_colors, guide="none") +
  scale_fill_manual( values=cat_colors, guide="none") +
  scale_x_discrete(labels=cat_labels, drop=FALSE) +

  labs(
    x        = NULL,
    y        = expression(hat(pi) ~ "(Mash distance)"),
    title    = "Pairwise genomic distances\nby comparison category",
    subtitle = sprintf(
      "Focal: %s  |  %d assemblies, %d pairs",
      focal_pretty,
      length(unique(c(df$asm1, df$asm2))),
      nrow(df)
    )
  ) +

  theme_classic(base_size=11) +
  theme(
    axis.text.x   = element_text(size=8, lineheight=1.1),
    plot.title    = element_text(size=12, face="bold"),
    plot.subtitle = element_text(size=8, color="grey45")
  )

# ─── Write output ─────────────────────────────────────────────────────────────
dir.create(dirname(opt$output), recursive=TRUE, showWarnings=FALSE)
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
