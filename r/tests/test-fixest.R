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
cat_of <- function(rec) vapply(rec$tests, `[[`, "", "category")
fs <- r$tests[cat_of(r) == "first_stage"][[1]]
eq(fs$statistic, fitstat(fi, ~ivf1)[[1]]$stat)
stopifnot(fs$response == "x", fs$component == "first_stage", is.null(r$structures$first_stage),
          all(c("model", "weak_identification", "endogeneity", "overidentification") %in% cat_of(r)),
          r$tests[cat_of(r) == "overidentification"][[1]]$name == "sargan")

# Tests: the model Wald test from fixest; hypotheses added from the record's own b and V
r <- to_estimation(f)
mt <- r$tests[[1]]
stopifnot(mt$category == "model", mt$name == "wald", mt$origin == "estimation", mt$vcov == "CRV1")
eq(mt$statistic, fitstat(f, ~wald)$wald$stat)
r2 <- add_test(r, "x = 0, x2 = 0")
w <- r2$tests[[2]]
eq(w$statistic, wald(f, keep = "^x", print = FALSE)$stat, 1e-10)   # same restrictions, same vcov
stopifnot(w$category == "restriction", w$df1 == 2, w$df2 == r$structures$vcov[[1]]$df_t,
          w$origin == "postestimation", !is.null(w$added), r2$history[[2]]$action == "extended")
r2 <- add_test(r2, "x + x2", label = "total effect")
lc <- r2$tests[[3]]
V <- vcov(f)
eq(lc$estimate, sum(coef(f)[c("x", "x2")]))
eq(lc$std_error, sqrt(V["x", "x"] + V["x2", "x2"] + 2 * V["x", "x2"]))
stopifnot(lc$category == "linear_combination", lc$name == "t", lc$label == "total effect",
          lc$conf_low < lc$estimate, lc$conf_high > lc$estimate)
r3 <- try(add_test(r2, "x = x2", vcov = "HC1"), silent = TRUE)   # the record has no HC1 vcov
stopifnot(inherits(r3, "try-error"))
r <- to_estimation(f, vcov = list(~id, "hetero"),
                   tests = list("x = x2", wald(f, keep = "^x2$", print = FALSE)))
r <- add_test(r, "2*x - x2 = 1", vcov = "HC1")
stopifnot(length(r$tests) == 4, r$tests[[4]]$vcov$type == "HC1",
          identical(as.numeric(r$tests[[4]]$hypothesis$restrictions$R[[1]]), c(2, -1)),
          r$tests[[4]]$hypothesis$restrictions$q == 1, r$tests[[3]]$source$name == "fixest")
check(r, "tests")
stopifnot(inherits(try(add_test(r, "x^2 = 0"), silent = TRUE), "try-error"),
          inherits(try(add_test(r, "nope = 0"), silent = TRUE), "try-error"))

# An interaction at given values, marginaleffects-style: one test per value, each with its
# estimate and SE; and an event-study pre-trend test by regex, as fixest::wald(keep =)
d$counter <- sample(-6:3, n, TRUE)
fe <- feols(y ~ i(counter, x2, ref = -1) + x * x2 | id, d)
r <- add_test(to_estimation(fe), sprintf("x + `x:x2` * %.4f = 0", c(0.25, 0.5)))
V <- vcov(fe); g <- c(1, 0.5); nm <- c("x", "x:x2")
lc <- r$tests[[3]]
eq(lc$estimate, sum(g * coef(fe)[nm]), 1e-10)
eq(lc$std_error, sqrt(drop(g %*% V[nm, nm] %*% g)), 1e-10)
eq(lc$statistic, (lc$estimate / lc$std_error)^2, 1e-10)
stopifnot(length(r$tests) == 3, lc$name == "wald", lc$conf_low < lc$estimate)
keep <- "^counter::-[2-6]:"
r <- add_test(r, keep = keep, label = "pre-trends")
pt <- r$tests[[4]]
eq(pt$statistic, wald(fe, keep = keep, print = FALSE)$stat, 1e-10)
stopifnot(pt$df1 == 5, length(pt$hypothesis$terms) == 5, pt$label == "pre-trends",
          inherits(try(add_test(r, keep = "^nope"), silent = TRUE), "try-error"))
# A results table: marginaleffects::hypotheses() output, one test per row
tab <- structure(data.frame(hypothesis = c("b1 = 0", "b2 = 0"), estimate = c(1, 2),
                            std.error = c(0.5, 0.4), statistic = c(2, 5), p.value = c(0.05, 1e-6),
                            conf.low = c(0, 1.2), conf.high = c(2, 2.8)),
                 class = c("hypotheses", "data.frame"), vcov.type = "HC3")
r <- add_test(r, tab)
stopifnot(length(r$tests) == 6, r$tests[[6]]$name == "z", r$tests[[6]]$estimate == 2,
          r$tests[[6]]$source$name == "marginaleffects", r$tests[[6]]$options$vcov_type == "HC3")
check(r, "hypotheses")

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
