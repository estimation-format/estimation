# Base-R tests of the readers and views (no testthat). The spec's example records and
# collections are read too when the repo's schema/examples folder is found (running from
# r/tests, or ESTREC_EXAMPLES naming it).
library(estrec)
tidy <- estrec:::tidy.estimation_record
glance <- estrec:::glance.estimation_record
eq <- function(a, b, tol = 1e-10) stopifnot(isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = tol)))
out <- tempfile("estrec-read"); dir.create(out)
quiet_print <- function(x) invisible(utils::capture.output(print(x)))

# A hand-made record: a clustered default vcov and an iid one, two FEs, a collinear term, a
# non-finite metric and an IV-style first-stage row
rec <- list(
  schema = "estrec/0.1",
  meta = list(id = "6f1c0000-0000-4000-8000-0000000000aa", created = "2026-11-05T07:00:00Z",
              status = "ok", estimator = list(family = "linear", method = "ols"),
              responses = I("y"), profiles = I(c("inference/0.1", "linear-fe/0.1")),
              title = "hand-made"),
  specification = list(formula = list(text = "y ~ x1 + x2 | firm + year", syntax = "fixest"),
                       fixed_effects = I(c("firm", "year")), clusters = I("firm")),
  metrics = list(nobs = 1000, r2 = 0.6, r2_within = list(value = 0.2, definition = "demeaned"),
                 f_stat = "Inf", rss = 100, tss = 250, conf_level = 0.95),
  parameters = list(
    list(term = "x1", estimate = 0.5, std_error = 0.1, statistic = 5, p_value = 1e-6,
         conf_low = 0.3, conf_high = 0.7),
    list(term = "x2", estimate = -0.2, std_error = 0.05, statistic = -4, p_value = 1e-4,
         conf_low = -0.3, conf_high = -0.1),
    list(term = "x3", dropped = "collinear"),
    list(term = "z", component = "first_stage", response = "x1", estimate = 0.6,
         std_error = 0.03, statistic = 20, p_value = 1e-80)),
  structures = list(
    vcov = list(
      list(kind = "matrix", labels = I(c("x1", "x2")), data = list(I(c(0.01, 0)), I(c(0, 0.0025))),
           type = "CRV1", cluster = I("firm"), df_t = 49, default = TRUE),
      list(kind = "matrix", labels = I(c("x1", "x2")), data = list(I(c(0.0004, 0)), I(c(0, 0.0001))),
           type = "iid", df_t = 997, default = FALSE)),
    fixed_effects = list(list(kind = "object", name = "firm", levels = 50),
                         list(kind = "object", name = "year", levels = 10))))
path <- write_estimation(rec, file.path(out, "hand.estrec.json"))
r <- read_estimation(path)
stopifnot(inherits(r, "estimation_record"), is_estimation_record(r))
quiet_print(r)

# tidy: main component, no dropped rows, values as written
t0 <- tidy(r)
stopifnot(identical(t0$term, c("x1", "x2")), !"component" %in% names(t0))
eq(t0$std.error, c(0.1, 0.05)); eq(t0$conf.low, c(0.3, -0.3))
stopifnot(identical(tidy(r, component = "first_stage")$term, "z"),
          nrow(tidy(r, component = "all", dropped = TRUE)) == 4L,
          !"conf.low" %in% names(tidy(r, conf.int = FALSE)))
# another vcov: SEs from its diagonal, t tests on its df_t
for (sel in list("iid", 2)) {
  t1 <- tidy(r, vcov = sel)
  eq(t1$std.error, c(0.02, 0.01)); eq(t1$statistic, c(25, -20))
  eq(t1$p.value, 2 * pt(-c(25, 20), 997))
  eq(t1$conf.high, t1$estimate + qt(0.975, 997) * t1$std.error)
}
eq(tidy(r, vcov = "firm")$std.error, c(0.1, 0.05))   # the default, by cluster variable
# a new level recomputes the interval on the default vcov's df
t9 <- tidy(r, conf.level = 0.9)
eq(t9$conf.low, c(0.5, -0.2) - qt(0.95, 49) * c(0.1, 0.05))
stopifnot(inherits(try(tidy(r, vcov = "HC3"), silent = TRUE), "try-error"))

# glance: broom names, {value} metrics unwrapped, non-finite decoded, FE and vcov columns
g <- glance(r)
stopifnot(nrow(g) == 1L, g$nobs == 1000, g$r.squared == 0.6, g$r2.within == 0.2,
          is.infinite(g$F), g$vcov.type == "by: firm", g$`FE: firm` == "X",
          g$`FE: year` == "X", !"conf_level" %in% names(g))
stopifnot(glance(r, vcov = "iid")$vcov.type == "iid")
eq(g$rmse, sqrt(100 / 1000)); stopifnot(!"rss" %in% names(g), !"tss" %in% names(g))
ga <- glance(r, metrics = "all")
stopifnot(ga$rss == 100, ga$tss == 250, !"rmse" %in% names(ga))

# a read record writes back unchanged
path2 <- write_estimation(r, file.path(out, "again.estrec.json"))
canon <- function(p) estrec:::.est_canonical_json(jsonlite::fromJSON(p, simplifyVector = FALSE))
stopifnot(identical(canon(path), canon(path2)))

# a folder: every record, named by file stem
all <- read_estimation(out)
stopifnot(identical(names(all), c("again", "hand")))

# collections, embedded and in a members file
if (requireNamespace("fixest", quietly = TRUE)) {
  suppressMessages(library(fixest))
  d <- data.frame(id = rep(1:20, each = 10), x = rnorm(200)); d$y <- d$x + rnorm(200)
  f1 <- feols(y ~ x, d, vcov = "iid"); f2 <- feols(y ~ x | id, d, cluster = ~id)
  for (m in c("embed", "jsonl")) {
    cp <- file.path(out, paste0(m, ".estrec-collection.json"))
    suppressMessages(write_collection(list(base = f1, fe = f2), cp, kind = "batch", members = m,
                                      locators = list("col. 1", list(table = "2", column = "2"))))
    cl <- read_collection(cp)
    stopifnot(identical(names(cl), c("base", "fe")),
              all(vapply(cl, inherits, TRUE, "estimation_record")),
              identical(attr(cl$fe, "member")$label, "fe"),
              is.null(attr(cl, "collection")$members[[1]]$record))
    eq(tidy(cl$fe)$std.error, sqrt(diag(vcov(f2))))
    stopifnot(glance(cl$fe)$`FE: id` == "X", glance(cl$base)$nobs == 200)
    quiet_print(cl$fe)
    # records read from a collection go into another one
    suppressMessages(write_collection(cl, file.path(out, paste0("re-", m, ".estrec-collection.json")),
                                      kind = "batch"))
  }
  stopifnot(inherits(try(read_estimation(cp), silent = TRUE), "try-error"))

  # modelsummary gives the same table from the records as from the fits
  if (requireNamespace("modelsummary", quietly = TRUE) && requireNamespace("broom", quietly = TRUE)) {
    d$z <- rnorm(200); d$x <- d$x + d$z; d$cnt <- rpois(200, exp(0.2 * d$x))
    fits <- list(ols = feols(y ~ x, d), fe = feols(y ~ x | id, d, cluster = ~id),
                 iv = feols(y ~ 1 | id | x ~ z, d, vcov = "hetero"), pois = fepois(cnt ~ x, d))
    mp <- file.path(out, "ms.estrec-collection.json")
    suppressMessages(write_collection(fits, mp, kind = "batch"))
    recs <- read_collection(mp)
    ms <- function(m, ...) {
      t <- modelsummary::modelsummary(m, output = "data.frame", fmt = 8, stars = TRUE, ...)
      attributes(t) <- attributes(t)[c("names", "row.names", "class")]
      t
    }
    stopifnot(identical(ms(fits, gof_omit = ".*"), ms(recs, gof_omit = ".*")))
    gf <- ms(fits); gr <- ms(recs)
    # every model: N, AIC, BIC, FEs; linear models: the R2s and RMSE (fixest shows a Poisson
    # fit's pseudo R2s as R2; records keep McFadden's as R2 Pseudo, and have no RSS for a GLM)
    linear <- c("ols", "fe", "iv")
    rows <- list(`Num.Obs.` = names(fits), AIC = names(fits), BIC = names(fits), `FE: id` = names(fits),
                 R2 = linear, `R2 Adj.` = linear, RMSE = linear, `R2 Within` = c("fe", "iv"))
    for (row in names(rows)) {
      a <- unlist(gf[gf$term == row, rows[[row]]]); b <- unlist(gr[gr$term == row, rows[[row]]])
      if (!identical(unname(a), unname(b))) stop("modelsummary row ", row, ": ", toString(a), " vs ", toString(b))
    }
  }
}

# the spec's examples
ex <- Sys.getenv("ESTREC_EXAMPLES", "../../schema/examples")
if (dir.exists(ex)) {
  recs <- read_estimation(ex)
  for (nm in names(recs)) {
    quiet_print(recs[[nm]])
    tidy(recs[[nm]]); glance(recs[[nm]])
  }
  iv <- recs[["iv"]]
  stopifnot(!any(tidy(iv)$term == "z"), nrow(tidy(iv, component = "first_stage")) > 0)
  df <- recs[["dfeols-linear-fe"]]
  stopifnot(glance(df)$vcov.type == "by: firm")
  eq(tidy(df, vcov = "iid")$std.error, sqrt(c(8.1e-05, 7.9e-05)))
  for (f in list.files(ex, "\\.estrec-collection\\.json$", full.names = TRUE)) {
    cl <- read_collection(f)
    for (x in cl) { quiet_print(x); tidy(x); glance(x) }
  }
}
cat("test-read: ok\n")
