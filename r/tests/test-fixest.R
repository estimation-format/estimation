# Base-R tests (no testthat). Records are also checked with the reference validator when the
# `estimation` CLI is on PATH or ESTREC_VALIDATOR names it.
if (!requireNamespace("fixest", quietly = TRUE)) quit(save = "no")
suppressMessages(library(fixest))
library(estrec)

set.seed(1); n <- 400
d <- data.frame(id = sample(40, n, TRUE), yr = sample(8, n, TRUE), g = sample(c("a", "b"), n, TRUE))
d$z <- rnorm(n); d$z2 <- rnorm(n); d$x <- d$z + d$z2 + rnorm(n); d$x2 <- rnorm(n)
d$y <- d$x + d$x2 + rnorm(n); d$y2 <- d$y + rnorm(n); d$w <- runif(n)
d$y[3] <- NA; d$x2[10] <- Inf; d$id[5] <- 999L          # a missing value, an Inf, a singleton

validator <- Sys.getenv("ESTREC_VALIDATOR", Sys.which("estimation"))
out <- tempfile("estrec"); dir.create(out)
check <- function(rec, name) {
  path <- write_estimation(rec, file.path(out, paste0(name, ".estimation.json")))
  if (nzchar(validator)) {
    res <- system2(validator, c("validate", path), stdout = TRUE, stderr = TRUE)
    status <- attr(res, "status")
    if (!is.null(status) && status != 0) stop(name, " failed validation:\n", paste(res, collapse = "\n"))
  }
  invisible(path)
}
eq <- function(a, b, tol = 1e-12) stopifnot(isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = tol)))
dropped <- function(rec) rec$specification$sample$dropped

# OLS with fixed effects, clustered; sample drops by reason
f <- feols(y ~ x + x2 | id + yr, d, cluster = ~id)
r <- to_estimation(f)
check(r, "ols")
stopifnot(identical(r$meta$profiles, I(c("inference/0.1", "linear-fe/0.1"))))
eq(sapply(r$parameters, `[[`, "estimate"), coef(f))
eq(sapply(r$parameters, `[[`, "std_error"), se(f))
stopifnot(dropped(r)$missing == 1, dropped(r)$non_finite == 1, dropped(r)$singletons == 1,
          r$metrics$n_singletons == 1, r$metrics$nobs == f$nobs,
          r$specification$sample$rows_input - sum(unlist(dropped(r))) == f$nobs)
stopifnot(identical(r$structures$vcov[[1]]$cluster, I("id")), r$structures$vcov[[1]]$type == "CRV1",
          r$structures$vcov[[1]]$n_clusters$id == length(unique(d$id[obs(f)])))

# Several vcovs: the first is the default and gives the parameters
r <- to_estimation(f, vcov = list("hetero", ~id + yr, "iid"))
check(r, "vcovs")
stopifnot(vapply(r$structures$vcov, `[[`, "", "type") == c("HC1", "CRV1", "iid"),
          vapply(r$structures$vcov, `[[`, TRUE, "default") == c(TRUE, FALSE, FALSE))
eq(sapply(r$parameters, `[[`, "std_error"), se(summary(f, vcov = "hetero")))
stopifnot(identical(r$structures$vcov[[2]]$cluster, I(c("id", "yr"))))

# Without fixed effects: inference/0.1 only; weights
f0 <- feols(y ~ x + x2, d, weights = ~w)
r <- to_estimation(f0)
check(r, "nofe")
stopifnot(identical(r$meta$profiles, I("inference/0.1")), is.null(dropped(r)$singletons),
          r$specification$weights$variable == "w")

# Multiple estimation with split and subset: one record per model
m <- feols(c(y, y2) ~ csw(x2, x) | id, d, split = ~g, subset = ~yr > 2)
rs <- to_estimation(m)
stopifnot(length(rs) == length(m))
paths <- write_estimation(m, file.path(out, "multi.estimation.json"))
stopifnot(length(paths) == length(m), all(file.exists(paths)), grepl("multi-8\\.estimation\\.json$", paths[8]))
for (i in seq_along(rs)) {
  ri <- rs[[i]]; mi <- m[[i]]
  check(ri, paste0("multi", i))
  eq(sapply(ri$parameters, `[[`, "estimate"), coef(mi))
  stopifnot(ri$specification$sample$rows_input - sum(unlist(dropped(ri))) == mi$nobs,
            dropped(ri)$restriction == n - sum(d$yr > 2 & d$g == mi$model_info$sample$value),
            grepl("split: g ==", ri$specification$sample$restriction))
}

# IV: iv/0.1 with first-stage statistics; fit_x is canonically x
fi <- feols(y ~ x2 | id | x ~ z + z2, d)
r <- to_estimation(fi)
check(r, "iv")
stopifnot("iv/0.1" %in% r$meta$profiles, r$meta$estimator$method == "2sls",
          identical(r$specification$endogenous, I("x")),
          r$parameters[[1]]$term == "fit_x", r$parameters[[1]]$canonical$name == "x")
fs <- r$structures$first_stage
eq(fs$per_endogenous[[1]]$f_stat$statistic, fitstat(fi, ~ivf1)[[1]]$stat)
stopifnot(fs$overid[[1]]$name == "sargan", fs$endogeneity[[1]]$name == "wu_hausman")

# Without the data: drops recorded as `other`, with a warning message
g <- function() { dd <- d; feols(y ~ x + x2 | id, dd) }
fg <- g()
rm_env <- fg; rm_env$call_env <- new.env()
r <- to_estimation(rm_env)
check(r, "nodata")
stopifnot(dropped(r)$other == n - fg$nobs, r$meta$messages[[1]]$code == "sample_unclassified")
r <- to_estimation(rm_env, data = d)
stopifnot(dropped(r)$singletons == 1)

# Writing a record leaves the caller's random numbers alone
set.seed(42); a <- runif(1); set.seed(42); invisible(to_estimation(f)); stopifnot(runif(1) == a)

# Unsupported fits fail clearly
stopifnot(inherits(try(to_estimation(fepois(round(abs(y)) ~ x | id, d)), silent = TRUE), "try-error"),
          inherits(try(to_estimation(lm(y ~ x, d)), silent = TRUE), "try-error"))
cat("estrec tests passed", if (nzchar(validator)) "(records validated)" else "(validator not found)", "\n")
